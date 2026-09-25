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
		case noFace, tooSmall, lowQuality, invalidMeasurements, embeddingUnavailable, inconsistentFace, steady, turning
	}

	var targetSegment: Int? {
		guard case .capturing = phase, progress > 0.25 else { return nil }
		return covered.firstIndex(of: false)
	}

	var captureTitle: String {
		switch captureStatus {
		case .noFace: return "Bring your face back into view"
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

	var progress: Double {
		Double(covered.filter { $0 }.count) / Double(Self.segmentCount)
	}

	var instruction: String {
		if case .failed(let message) = phase { return message }
		if phase != .complete {
			switch captureStatus {
			case .noFace: return "No usable face is coming through. Your captured progress is kept."
			case .tooSmall: return "Your face is visible, but needs to fill more of the camera view."
			case .lowQuality: return "Your face is visible, but this frame isn’t clear enough to save. Face a light and pause briefly."
			case .invalidMeasurements: return "Your face measurements aren’t usable yet. Look straight ahead for a moment."
			case .embeddingUnavailable: return "Gaze sees your face but couldn’t create a faceprint. No new progress was saved."
			case .inconsistentFace: return "This capture doesn’t agree with your starting face. Look toward the camera in steady light, then turn slowly."
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
	func consume(_ sample: FaceSample?) {
		switch phase {
		case .complete, .failed: return
		default: break
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
			guard sample.pose.offCentre < Self.engagementThreshold else {
				framesWithFace = 0
				return
			}
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
				guard let frontal = validatedPrint(sample) else { return }
				prints.append(frontal)
			}
			phase = .capturing(pass: pass)
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
			guard let faceprint = validatedPrint(sample) else { return }
			prints.append(faceprint)
		}
		for index in neighbours { covered[index] = true }

		guard progress >= 1 else { return }
		advancePass()
	}

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

	private func advancePass() {
		if pass == 1 {
			pass = 2
			covered = [Bool](repeating: false, count: Self.segmentCount)
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
		framesWithFace = 0
		isEngaged = false
		currentAngle = 0
		captureStatus = .noFace
	}
}
