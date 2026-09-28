import Foundation
import Observation

/// Drives the two-pass enrolment and tracks which head angles have been covered.
///
/// Modelled on the iOS flow: the user rotates their head so their face is seen from a
/// spread of angles, and the ring fills in as each direction is captured. The point is
/// not the animation — it is that a single frontal print matches poorly the moment the
/// head tilts, so recognition needs a set of prints taken across the same range of
/// angles the user will actually present at the lock screen.
@Observable
@MainActor
final class EnrollmentModel {

	/// Ticks around the ring. Enough that the fill reads as continuous motion.
	static let segmentCount = 48

	/// How far the head must turn before a direction counts as covered. Below this the
	/// user is effectively looking straight ahead and every segment would fill at once.
	private static let engagementThreshold = 0.22
	/// How far from straight on (radians, about 15 degrees) still counts as centred.
	private static let centredTolerance = 0.26

	/// A scan finishes when the whole ring is filled, as people expect from Face ID.
	/// Pitch-led segments take a gentler nod (see engagement below) so the top and
	/// bottom fill without extreme angles.
	private static let earlyCompletionCoverage = 1.0
	/// Stall escape hatch: past this coverage the set already spans the needed angles.
	private static let stallCompletionCoverage = 0.85
	/// A print counts as clearly turned at this yaw (radians, about 14 degrees).
	private static let clearTurnYaw = 0.25
	/// Seconds without a newly covered segment before guidance names the gap.
	private static let stallGuidanceAfter: TimeInterval = 3
	/// Seconds without a newly covered segment before a stalled scan finishes, when
	/// the coverage and angle minimums are already met.
	private static let stallCompletionAfter: TimeInterval = 6
	/// Prints needed before the set may be saved. Unchanged from the two-pass rule.
	private static let minimumPrints = 8

	/// Vision's own quality score, below which a frame is too blurred, dark or oblique
	/// to enrol from. Keeping junk out of the enrolment set matters more than speed.
	private static let minimumQuality: Float = 0.35

	enum Phase: Equatable {
		case positioning
		case capturing(pass: Int)
		case complete
		case failed(String)
	}

	private(set) var phase: Phase = .positioning
	/// Which ring segments have been captured this pass.
	private(set) var covered = [Bool](repeating: false, count: segmentCount)
	/// Where the user's head is pointing right now, for the live indicator.
	private(set) var currentAngle: Double = 0
	private(set) var isEngaged = false
	private(set) var captureStatus: CaptureStatus = .noFace

	enum CaptureStatus: Equatable {
		case noFace, tooSmall, lowQuality, invalidMeasurements, embeddingUnavailable, inconsistentFace, multipleFaces, steady, turning
	}

	/// The gap to aim at: the nearest uncovered segment to where the head is, held until
	/// it fills. It used to be the first uncovered segment around the ring, which leapt
	/// across the circle each time a gap closed.
	var targetSegment: Int? {
		guard case .capturing = phase, progress > 0.25 else { return nil }
		if let heldTarget, !covered[heldTarget] { return heldTarget }
		return nearestUncovered(to: segmentIndex(for: currentAngle))
	}

	private var heldTarget: Int?
	private var hasFrontalPrint = false
	private var hasLeftPrint = false
	private var hasRightPrint = false
	/// When the ring first filled, so a missing turn cannot hold the scan open forever.
	private var ringFilledAt: Date?
	private static let widerTurnGrace: TimeInterval = 8
	private var lastCoverageAdvance = Date()
	/// Clock seam for the stall timers.
	var now: () -> Date = { Date() }

	private func nearestUncovered(to index: Int) -> Int? {
		let count = Self.segmentCount
		for distance in 0...(count / 2) {
			for candidate in [(index + distance) % count, (index - distance + count) % count] where !covered[candidate] {
				return candidate
			}
		}
		return nil
	}

	/// Measured against the coverage that finishes the scan, so the number climbs to 100%
	/// instead of leaping there from the high 30s when the early-completion rule fires.
	var overallProgress: Double {
		if phase == .complete { return 1 }
		// Both passes as one figure: the first fills 0–50%, the second 50–100%.
		return min(0.99, (Double(pass - 1) + progress) / 2)
	}

	var captureTitle: String {
		if phase == .complete { return "Scan complete" }
		switch captureStatus {
		case .noFace: return "Bring your face back into view"
		case .multipleFaces: return "Only one face in view, please"
		case .tooSmall: return "Move a little closer"
		case .lowQuality: return "Pause in brighter light"
		case .invalidMeasurements, .embeddingUnavailable: return "Hold your face toward the camera"
		case .inconsistentFace: return "Return to the starting position"
		case .steady, .turning:
			if case .positioning = phase { return "Center your face" }
			return targetSegment == nil ? "Move your head slowly" : "Follow the highlighted gap"
		}
	}

	private(set) var prints: [Faceprint] = []
	/// Upper-face prints captured alongside the full ones, for unlocking with a
	/// mask. Stays empty where the embedder cannot describe the upper face alone,
	/// which is what the Settings gate reads.
	private(set) var upperPrints: [Faceprint] = []

	var progress: Double {
		Double(covered.filter { $0 }.count) / Double(Self.segmentCount)
	}

	var instruction: String {
		if case .failed(let message) = phase { return message }
		if phase != .complete {
			switch captureStatus {
			case .noFace: return "Bring your face back into the circle. Your progress is kept."
			case .multipleFaces: return "Only the person being added should be in view."
			case .tooSmall: return "Move a little closer to the camera."
			case .lowQuality: return "Face a light and hold still for a moment."
			case .invalidMeasurements: return "Look straight ahead for a moment."
			case .embeddingUnavailable: return "Gaze can see you but couldn’t save this angle. Hold still in even light."
			case .inconsistentFace: return "Look straight at the camera, then turn slowly."
			case .steady, .turning: break
			}
		}
		switch phase {
		case .positioning:
			return "Position your face in the circle"
		case .capturing:
			if needsWiderTurn { return "Turn your head a little further to each side." }
			if stalledForGuidance, targetSegment != nil { return "Tilt your head a little toward the gap" }
			if captureStatus == .steady { return "Gently turn your head to fill the circle." }
			return "Move your head slowly to fill the circle"
		case .complete:
			return "Confirm with Touch ID or your password to save this face."
		case .failed(let message):
			return message
		}
	}

	private let embedder: FaceEmbedder
	private var pass = 1
	private var framesWithFace = 0

	init(embedder: FaceEmbedder) {
		self.embedder = embedder
	}

	/// Feed every camera frame here. Nil means no single usable face was found.
	func consume(_ sample: FaceSample?, multipleFaces: Bool = false) {
		switch phase {
		case .complete, .failed: return
		default: break
		}

		// Stalled with the minimums already in hand: finish rather than sit on a
		// nearly full ring waiting for a pitch angle Vision reports poorly.
		if case .capturing = phase,
			now().timeIntervalSince(lastCoverageAdvance) >= Self.stallCompletionAfter,
			pass == 2, progress >= Self.stallCompletionCoverage, hasAngleDiversity,
			prints.count >= Self.minimumPrints {
			phase = .complete
			// A finished scan reads as a full ring, even when the stall rule filled the last gap.
			covered = Array(repeating: true, count: Self.segmentCount)
			return
		}

		// A second face pauses capture without enrolling either one and without
		// discarding progress, like a dropped frame with its own message.
		if multipleFaces {
			captureStatus = .multipleFaces
			framesWithFace = 0
			isEngaged = false
			if case .capturing = phase { return }  // Don't reset mid-pass on a dropped frame.
			phase = .positioning
			return
		}

		let rejection: CaptureStatus? = {
			guard let sample else { return .noFace }
			guard sample.pose.yaw.isFinite, sample.pose.pitch.isFinite,
				sample.pose.yawSource != .unavailable, sample.pose.pitchSource != .unavailable
			else { return .invalidMeasurements }
			switch FrameQuality.rejection(sample) {
			case .invalidMeasurements: return .invalidMeasurements
			case .tooSmall: return .tooSmall
			case .tooBlurred: return .lowQuality
			case nil: return sample.hasQualityMeasurement && sample.quality < Self.minimumQuality ? .lowQuality : nil
			}
		}()
		guard let sample, rejection == nil else {
			captureStatus = rejection ?? .noFace
			framesWithFace = 0
			isEngaged = false
			if case .capturing = phase { return }  // Don't reset mid-pass on a dropped frame.
			phase = .positioning
			return
		}
		captureStatus = .steady

		// A short run of good frames before starting, so the ring doesn't begin filling
		// from a single lucky detection as the user is still sitting down.
		framesWithFace += 1
		if case .positioning = phase {
			// Forgiving on purpose: a wide window, an axis the camera cannot measure counts as
			// straight, and one stray frame steps the count back instead of starting over.
			let yaw = sample.pose.yaw.isFinite ? sample.pose.yaw : 0
			let pitch = sample.pose.pitch.isFinite ? sample.pose.pitch : 0
			guard hypot(yaw, pitch) < Self.centredTolerance else {
				framesWithFace = max(0, framesWithFace - 3)
				return
			}
			guard framesWithFace > 5 else { return }
			// Capture one straight-ahead print before the turning begins.
			//
			// Every other print in the set is taken mid-turn — `capture` only runs once the
			// head is off-centre (`isEngaged`) — so without this the frontal pose is the one
			// angle never enrolled. And the frontal pose is the common one: at the lock screen
			// people look straight at the Mac, then get matched against a set of turned prints.
			// This lands the most-used direction in the set on the first pass. Only pass 1, so
			// it isn't duplicated.
			if pass == 1 {
				guard let frontal = validatedPrint(sample) else { return }
				prints.append(frontal)
				captureUpperPrint(sample)
				hasFrontalPrint = true
			}
			lastCoverageAdvance = now()
			phase = .capturing(pass: pass)
		}

		// An unavailable pose axis is NaN, and `min(1, NaN)` in `offCentre` reads as fully
		// turned, so without this a frame with no angle counted as a turn and then crashed
		// converting its NaN ring angle to a segment. No angle, no ring progress.
		guard sample.pose.yaw.isFinite, sample.pose.pitch.isFinite, sample.pose.roll.isFinite else {
			isEngaged = false
			return
		}
		currentAngle = sample.pose.ringAngle
		// Pitch-led directions (top and bottom of the ring) read poorly: Vision drops
		// the pitch axis at large chin-up/chin-down angles, so those segments stall
		// while yaw-led ones fill. Halve the bar there; a moderate tilt counts.
		isEngaged = sample.pose.offCentre >= Self.engagementThreshold(for: currentAngle)

		guard isEngaged else { return }
		captureStatus = .turning
		capture(sample)
	}

	private func capture(_ sample: FaceSample) {
		let index = segmentIndex(for: currentAngle)

		// Widen slightly either side. Head movement is continuous but frames are not, so
		// exact-segment filling leaves gaps the user cannot deliberately aim at.
		let neighbours = [index, (index + 1) % Self.segmentCount,
			(index + Self.segmentCount - 1) % Self.segmentCount]

		let isNewDirection = neighbours.contains { !covered[$0] }

		// One print per newly covered direction, rather than per frame, or the enrolment
		// set fills with near-identical frontal prints and matching gets slower for
		// nothing.
		if isNewDirection {
			guard let faceprint = validatedPrint(sample) else { return }
			prints.append(faceprint)
			captureUpperPrint(sample)
			if sample.pose.yaw >= Self.clearTurnYaw { hasLeftPrint = true }
			if sample.pose.yaw <= -Self.clearTurnYaw { hasRightPrint = true }
		}
		let filledBefore = covered.filter { $0 }.count
		for index in neighbours { covered[index] = true }
		if covered.filter({ $0 }).count > filledBefore { lastCoverageAdvance = now() }
		if heldTarget == nil || covered[heldTarget!] { heldTarget = targetSegment }

		// Three quarters of the ring with a frontal print and a clear turn each way
		// matches as well as the full circle: the missing ticks are the extreme
		// pitch angles users never present at the lock screen.
		// Always two passes, like Face ID: the early finish only applies on the second.
		if pass == 2, progress >= Self.earlyCompletionCoverage, hasAngleDiversity,
			prints.count >= Self.minimumPrints {
			phase = .complete
			// A finished scan reads as a full ring, even when the stall rule filled the last gap.
			covered = Array(repeating: true, count: Self.segmentCount)
			return
		}
		// One pass only. A full ring still missing a clear turn asks for it rather than
		// starting a second lap, which read as the scan restarting on some Macs.
		guard progress >= 1 else { return }
		if pass == 1 {
			advancePass()
			return
		}
		if ringFilledAt == nil { ringFilledAt = now() }
		if let filled = ringFilledAt, now().timeIntervalSince(filled) >= Self.widerTurnGrace,
			hasFrontalPrint, prints.count >= Self.minimumPrints {
			phase = .complete
		}
	}

	/// The ring is full but a clear turn to one side is still missing.
	private var needsWiderTurn: Bool { pass == 2 && progress >= 1 && !hasAngleDiversity }

	private func validatedPrint(_ sample: FaceSample) -> Faceprint? {
		guard let candidate = embedder.embed(sample), candidate.source == embedder.identifier,
			(1...4096).contains(candidate.values.count),
			prints.first.map({ $0.values.count == candidate.values.count }) ?? true,
			Faceprint.normalized(candidate.values, source: candidate.source) != nil else {
			captureStatus = .embeddingUnavailable
			return nil
		}
		// Anchor every learned print to the frontal capture, rather than only to the
		// previous frame: a chain of locally similar faces must not drift to another person.
		if embedder.usesCosineSimilarity, let anchor = prints.first {
			let score = embedder.similarity(anchor, candidate)
			guard score.isFinite, score >= embedder.matchThreshold else {
				captureStatus = .inconsistentFace
				return nil
			}
		}
		return candidate
	}

	/// The upper-face twin of a captured print, where the embedder can produce one.
	/// Best-effort by design: a scan that never lands one simply enrols a face
	/// without mask support, which the Settings gate says plainly.
	private func captureUpperPrint(_ sample: FaceSample) {
		if let upper = embedder.embedUpperFace(sample) {
			upperPrints.append(upper)
		}
	}

	/// Frontal print plus a clear turn each way. Positive yaw faces screen left in
	/// the mirrored preview.
	private var hasAngleDiversity: Bool { hasFrontalPrint && hasLeftPrint && hasRightPrint }

	/// Past three seconds without a new segment, the highlight is already the
	/// nearest gap (`targetSegment`), so guidance just names it.
	private var stalledForGuidance: Bool {
		guard case .capturing = phase else { return false }
		return now().timeIntervalSince(lastCoverageAdvance) >= Self.stallGuidanceAfter
	}

	/// Engagement bar for a ring angle. Halved where pitch leads (near the top and
	/// bottom of the ring) so a moderate nod covers what used to need a full tilt.
	private static func engagementThreshold(for angle: Double) -> Double {
		abs(sin(angle)) < 0.7071 ? engagementThreshold / 2 : engagementThreshold
	}

	private func advancePass() {
		if pass == 1 {
			pass = 2
			covered = [Bool](repeating: false, count: Self.segmentCount)
			heldTarget = nil
			lastCoverageAdvance = now()
			phase = .capturing(pass: 2)
		} else {
			phase = prints.count >= Self.minimumPrints
				? .complete
				: .failed("Not enough of your face was captured. Choose Try Again and use brighter, even light.")
		}
	}

	private func segmentIndex(for angle: Double) -> Int {
		let turns = (angle / (2 * .pi)).truncatingRemainder(dividingBy: 1)
		let normalised = turns < 0 ? turns + 1 : turns
		return min(Self.segmentCount - 1, Int(normalised * Double(Self.segmentCount)))
	}

	func reset() {
		phase = .positioning
		covered = [Bool](repeating: false, count: Self.segmentCount)
		prints = []
		upperPrints = []
		pass = 1
		heldTarget = nil
		hasFrontalPrint = false
		hasLeftPrint = false
		hasRightPrint = false
		ringFilledAt = nil
		lastCoverageAdvance = now()
		framesWithFace = 0
		isEngaged = false
		currentAngle = 0
		captureStatus = .noFace
	}
}
