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

	private(set) var prints: [Faceprint] = []

	var progress: Double {
		Double(covered.filter { $0 }.count) / Double(Self.segmentCount)
	}

	var instruction: String {
		switch phase {
		case .positioning:
			return "Position your face in the circle"
		case .capturing(let pass):
			if progress > 0.92 { return pass == 1 ? "Almost done" : "Nearly there" }
			return pass == 1 ? "Move your head slowly to complete the circle" : "One more time"
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
		guard phase != .complete else { return }

		guard let sample else {
			framesWithFace = 0
			isEngaged = false
			if case .capturing = phase { return }  // Don't reset mid-pass on a dropped frame.
			phase = .positioning
			return
		}

		// A short run of good frames before starting, so the ring doesn't begin filling
		// from a single lucky detection as the user is still sitting down.
		framesWithFace += 1
		if case .positioning = phase {
			guard framesWithFace > 8, sample.quality >= Self.minimumQuality else { return }
			// Capture one straight-ahead print before the turning begins.
			//
			// Every other print in the set is taken mid-turn — `capture` only runs once the
			// head is off-centre (`isEngaged`) — so without this the frontal pose is the one
			// angle never enrolled. And the frontal pose is the common one: at the lock screen
			// people look straight at the Mac, then get matched against a set of turned prints.
			// This lands the most-used direction in the set on the first pass. Only pass 1, so
			// it isn't duplicated.
			if pass == 1, let frontal = embedder.embed(sample) {
				prints.append(frontal)
			}
			phase = .capturing(pass: pass)
		}

		currentAngle = sample.pose.ringAngle
		isEngaged = sample.pose.offCentre >= Self.engagementThreshold

		guard isEngaged, sample.quality >= Self.minimumQuality else { return }
		capture(sample)
	}

	private func capture(_ sample: FaceSample) {
		let index = segmentIndex(for: currentAngle)

		// Widen slightly either side. Head movement is continuous but frames are not, so
		// exact-segment filling leaves gaps the user cannot deliberately aim at.
		let neighbours = [index, (index + 1) % Self.segmentCount,
			(index + Self.segmentCount - 1) % Self.segmentCount]

		let isNewDirection = neighbours.contains { !covered[$0] }
		for i in neighbours { covered[i] = true }

		// One print per newly covered direction, rather than per frame, or the enrolment
		// set fills with near-identical frontal prints and matching gets slower for
		// nothing.
		if isNewDirection, let print = embedder.embed(sample) {
			prints.append(print)
		}

		guard progress >= 1 else { return }
		advancePass()
	}

	private func advancePass() {
		if pass == 1 {
			pass = 2
			covered = [Bool](repeating: false, count: Self.segmentCount)
			phase = .capturing(pass: 2)
		} else {
			phase = prints.count >= 8
				? .complete
				: .failed("Not enough of your face was captured. Try again in better light.")
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
	}
}
