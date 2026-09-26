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
		case noFace, tooSmall, lowQuality, invalidMeasurements, embeddingUnavailable, multipleFaces, steady, turning
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

	private func nearestUncovered(to index: Int) -> Int? {
		let count = Self.segmentCount
		for distance in 0...(count / 2) {
			for candidate in [(index + distance) % count, (index - distance + count) % count] where !covered[candidate] {
				return candidate
			}
		}
		return nil
	}

	/// Both passes as one figure: the first fills 0–50%, the second 50–100%. Shown per
	/// pass, the number fell from the high 90s back to zero with no explanation.
	var overallProgress: Double {
		if phase == .complete { return 1 }
		return (Double(pass - 1) + progress) / 2
	}

	var captureTitle: String {
		switch captureStatus {
		case .noFace: return "Bring your face back into view"
		case .multipleFaces: return "Only one face in view, please"
		case .tooSmall: return "Move a little closer"
		case .lowQuality: return "Pause in brighter light"
		case .invalidMeasurements, .embeddingUnavailable: return "Hold your face toward the camera"
		case .steady, .turning:
			if case .positioning = phase { return "Center your face" }
			return targetSegment == nil ? "Move your head slowly" : "Follow the highlighted gap"
		}
	}

	private(set) var prints: [Faceprint] = []

	var progress: Double {
		Double(covered.filter { $0 }.count) / Double(Self.segmentCount)
	}

	var instruction: String {
		if case .failed(let message) = phase { return message }
		if phase != .complete {
			switch captureStatus {
			case .noFace: return "No usable face is coming through. Your captured progress is kept."
			case .multipleFaces: return "More than one face is in view. Only the person being enrolled should be in frame. Your captured progress is kept."
			case .tooSmall: return "Your face is visible, but needs to fill more of the camera view."
			case .lowQuality: return "Your face is visible, but this frame isn’t clear enough to save. Face a light and pause briefly."
			case .invalidMeasurements: return "Your face measurements aren’t usable yet. Look straight ahead for a moment."
			case .embeddingUnavailable: return "Gaze sees your face but couldn’t create a faceprint. No new progress was saved."
			case .steady, .turning: break
			}
		}
		switch phase {
		case .positioning:
			return "Position your face in the circle"
		case .capturing(let pass):
			if let targetSegment {
				let directions = ["up", "up and right", "right", "down and right", "down", "down and left", "left", "up and left"]
				let direction = directions[((targetSegment + 3) / 6) % 8]
				return "Slowly point your face \(direction), toward the bright tick. Keep your eyes visible to the camera."
			}
			if captureStatus == .steady { return "Your face is detected. Gently turn your head to capture the unfilled angles." }
			return pass == 1 ? "Move your head slowly to complete the circle" : "Almost done — turn your head slowly once more to finish the circle"
		case .complete:
			return "Gaze is set up"
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
			switch FrameQuality.rejection(sample) {
			case .invalidMeasurements: return .invalidMeasurements
			case .tooSmall: return .tooSmall
			case .tooBlurred: return .lowQuality
			case nil: return sample.quality < Self.minimumQuality ? .lowQuality : nil
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
			guard framesWithFace > 8 else { return }
			// Capture one straight-ahead print before the turning begins.
			//
			// Every other print in the set is taken mid-turn — `capture` only runs once the
			// head is off-centre (`isEngaged`) — so without this the frontal pose is the one
			// angle never enrolled. And the frontal pose is the common one: at the lock screen
			// people look straight at the Mac, then get matched against a set of turned prints.
			// This lands the most-used direction in the set on the first pass. Only pass 1, so
			// it isn't duplicated.
			if pass == 1 {
				guard let frontal = embedder.embed(sample) else { captureStatus = .embeddingUnavailable; return }
				prints.append(frontal)
			}
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
		isEngaged = sample.pose.offCentre >= Self.engagementThreshold

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
			guard let faceprint = embedder.embed(sample) else { captureStatus = .embeddingUnavailable; return }
			prints.append(faceprint)
		}
		for index in neighbours { covered[index] = true }
		if heldTarget == nil || covered[heldTarget!] { heldTarget = targetSegment }

		guard progress >= 1 else { return }
		advancePass()
	}

	private func advancePass() {
		if pass == 1 {
			pass = 2
			covered = [Bool](repeating: false, count: Self.segmentCount)
			heldTarget = nil
			phase = .capturing(pass: 2)
		} else {
			phase = prints.count >= 8
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
		pass = 1
		heldTarget = nil
		framesWithFace = 0
		isEngaged = false
		currentAngle = 0
		captureStatus = .noFace
	}
}
