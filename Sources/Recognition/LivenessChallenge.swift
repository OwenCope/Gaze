import Foundation
import Observation
import Vision

/// Active challenge–response liveness.
///
/// The camera names a specific, randomly chosen action — turn left, turn right, nod, blink,
/// open your mouth — and passes only when it sees that action actually performed. This is the
/// movement check is supplementary evidence, not proof of a live person. A replay or a
/// manipulated presentation may reproduce motion; evaluate the complete pipeline against
/// those attacks before making any security claim.
///
/// Detection is deliberately *relative*: each directional action measures movement away from
/// where the head started, not an absolute angle. That way it doesn't matter what a person's
/// resting pose is, or whether Vision and the landmark fallback disagree on the zero point —
/// what counts is that the head moved the way it was told to.
@MainActor
@Observable
final class LivenessChallenge {

	enum Action: CaseIterable {
		case turnLeft, turnRight, nod, blink, openMouth

		var prompt: String {
			switch self {
			case .turnLeft: return "Turn slightly left"
			case .turnRight: return "Turn slightly right"
			case .nod: return "Nod your head"
			case .blink: return "Blink"
			case .openMouth: return "Open your mouth"
			}
		}

		/// Which way the mark should move to show what is being asked.
		///
		/// The panel demonstrates the action rather than only naming it: a face that leans
		/// left is a faster instruction than the words "turn your head left", and the words
		/// underneath are there for the case where it is not obvious. Blink and open-mouth
		/// have no direction, so they pulse in place instead.
		var hint: (x: CGFloat, y: CGFloat, pulses: Bool) {
			switch self {
			case .turnLeft: return (-1, 0, false)
			case .turnRight: return (1, 0, false)
			case .nod: return (0, 1, false)
			case .blink, .openMouth: return (0, 0, true)
			}
		}

		var symbol: String {
			switch self {
			case .turnLeft: return "arrowshape.left.fill"
			case .turnRight: return "arrowshape.right.fill"
			case .nod: return "arrowshape.down.fill"
			case .blink: return "eye.fill"
			case .openMouth: return "mouth.fill"
			}
		}
	}

	private(set) var action: Action = .blink
	private(set) var isComplete = false

	/// The head pose at the moment the challenge began, for the directional actions. Movement
	/// is measured from here, so absolute pose and per-camera zero offsets don't matter.
	private var baseYaw: Double?
	private var basePitch: Double?
	/// Eyes/mouth need a "returned to rest" beat before the action counts, so the user has to
	/// move *into* it rather than already being there.
	private var eyesWereOpen = false
	private var mouthWasClosed = false
	private var baselineSamples = 0
	private var movementSamples = 0
	private var observedMovement = false

	// How far counts. Radians for pose; landmark ratios for eyes and mouth.
	private static let turnDelta = 0.30      // head clearly turned from where it started
	private static let nodDelta = 0.18       // chin dropped from where it started
	private static let eyeOpen: Float = 0.22
	private static let eyeShut: Float = 0.14
	private static let mouthClosed: Float = 0.16
	private static let mouthOpen: Float = 0.32
	var isBaselineReady: Bool { baselineSamples >= 3 }
	var isReturningToRest: Bool { observedMovement && !isComplete }
	var guidancePrompt: String {
		guard isReturningToRest else { return action.prompt }
		switch action {
		case .turnLeft, .turnRight, .nod: return "Face the camera again"
		case .blink: return "Open your eyes"
		case .openMouth: return "Relax your mouth"
		}
	}
	var guidanceSymbol: String { isReturningToRest ? "viewfinder" : action.symbol }
	var guidanceHint: (x: CGFloat, y: CGFloat, pulses: Bool) {
		isReturningToRest ? (0, 0, false) : action.hint
	}

	struct PoseMeasurement: Sendable {
		let offset: Double
		let target: Double
		let returnTolerance: Double
	}

	func poseMeasurement(yaw: Double, pitch: Double) -> PoseMeasurement? {
		guard isBaselineReady, yaw.isFinite, pitch.isFinite else { return nil }
		let baseline: Double?
		let value: Double
		let target: Double
		switch action {
		case .turnLeft, .turnRight:
			baseline = baseYaw
			value = yaw
			target = action == .turnLeft ? Self.turnDelta : -Self.turnDelta
		case .nod:
			baseline = basePitch
			value = pitch
			target = Self.nodDelta
		case .blink, .openMouth:
			return nil
		}
		guard let baseline else { return nil }
		return PoseMeasurement(offset: value - baseline, target: target,
			returnTolerance: abs(target) / 3)
	}

	init(action: Action? = nil) {
		self.action = action ?? Action.allCases.randomElement() ?? .blink
	}

	/// Pick a fresh random action, different from the current one, and start over.
	func next() {
		action = Action.allCases.filter { $0 != action }.randomElement() ?? action
		reset()
	}

	func reset() {
		isComplete = false
		baseYaw = nil
		basePitch = nil
		eyesWereOpen = false
		mouthWasClosed = false
		baselineSamples = 0
		movementSamples = 0
		observedMovement = false
	}

	func prepareBaseline(_ sample: FaceSample) {
		prepareBaseline(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks))
	}

	func prepareBaseline(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?) {
		guard yaw.isFinite, pitch.isFinite,
			eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else { reset(); return }
		isComplete = false
		movementSamples = 0
		observedMovement = false
		switch action {
		case .turnLeft, .turnRight:
			preparePoseBaseline(yaw, baseline: &baseYaw)
		case .nod:
			preparePoseBaseline(pitch, baseline: &basePitch)
		case .blink:
			baselineSamples = eyes.map { $0 > Self.eyeOpen } == true ? min(3, baselineSamples + 1) : 0
			eyesWereOpen = isBaselineReady
		case .openMouth:
			baselineSamples = mouth.map { $0 < Self.mouthClosed } == true ? min(3, baselineSamples + 1) : 0
			mouthWasClosed = isBaselineReady
		}
	}

	private func preparePoseBaseline(_ value: Double, baseline: inout Double?) {
		if let previous = baseline, abs(value - previous) <= 0.05 {
			baselineSamples = min(3, baselineSamples + 1)
		} else {
			baseline = value
			baselineSamples = 1
		}
	}

	/// Feed each frame. Sets `isComplete` once the current action has been seen.
	func consume(_ sample: FaceSample) {
		consume(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks))
	}

	func consume(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?) {
		guard !isComplete else { return }
		guard yaw.isFinite, pitch.isFinite,
			eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else { reset(); return }
		switch action {
		// In the mirrored camera preview, leftward turns increase Vision yaw.
		// Verified against the September 15 recording; see CHALLENGE-INVESTIGATION.md.
		case .turnLeft:
			consumePose(yaw, baseline: &baseYaw, threshold: Self.turnDelta, direction: 1)
		case .turnRight:
			consumePose(yaw, baseline: &baseYaw, threshold: Self.turnDelta, direction: -1)
		case .nod:
			consumePose(pitch, baseline: &basePitch, threshold: Self.nodDelta, direction: 1)
		case .blink:
			guard let eyes else { reset(); return }
			if !eyesWereOpen {
				baselineSamples = eyes > Self.eyeOpen ? baselineSamples + 1 : 0
				eyesWereOpen = baselineSamples >= 3
			} else if eyes < Self.eyeShut {
				observedMovement = true
			} else if observedMovement && eyes > Self.eyeOpen {
				isComplete = true
			}
		case .openMouth:
			guard let mouth else { reset(); return }
			if !mouthWasClosed {
				baselineSamples = mouth < Self.mouthClosed ? baselineSamples + 1 : 0
				mouthWasClosed = baselineSamples >= 3
			} else if !observedMovement {
				movementSamples = mouth > Self.mouthOpen ? movementSamples + 1 : 0
				observedMovement = movementSamples >= 2
			} else if mouth < Self.mouthClosed {
				isComplete = true
			}
		}
	}

	private func consumePose(_ value: Double, baseline: inout Double?, threshold: Double, direction: Double) {
		if baselineSamples < 3 {
			if let previous = baseline, abs(value - previous) <= 0.05 {
				baselineSamples += 1
			} else {
				baseline = value
				baselineSamples = 1
			}
			return
		}
		guard let baseline else { return }
		let delta = value - baseline
		if !observedMovement {
			movementSamples = delta * direction >= threshold ? movementSamples + 1 : 0
			observedMovement = movementSamples >= 2
		} else if abs(delta) <= threshold / 3 {
			isComplete = true
		}
	}

	// MARK: - Landmark measurements

	/// Average eye openness — the eye landmark box's height over its width. ~0.30 open, dips
	/// below ~0.14 on a blink.
	static func eyeOpenness(_ lm: VNFaceLandmarks2D) -> Float? {
		func openness(_ region: VNFaceLandmarkRegion2D?) -> Float? {
			guard let p = region?.normalizedPoints, p.count >= 4 else { return nil }
			let xs = p.map(\.x), ys = p.map(\.y)
			guard let minX = xs.min(), let maxX = xs.max(),
				let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0.0001
			else { return nil }
			return Float((maxY - minY) / (maxX - minX))
		}
		guard let left = openness(lm.leftEye), let right = openness(lm.rightEye) else { return nil }
		return max(left, right)
	}

	/// Mouth openness — the inner-lip box's height over the mouth's width. Near 0 closed,
	/// well above 0.3 with the mouth open. Normalised by mouth width so it's scale-free.
	static func mouthOpenness(_ lm: VNFaceLandmarks2D) -> Float? {
		guard let p = lm.innerLips?.normalizedPoints, p.count >= 4 else { return nil }
		let xs = p.map(\.x), ys = p.map(\.y)
		guard let minX = xs.min(), let maxX = xs.max(),
			let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0.0001
		else { return nil }
		return Float((maxY - minY) / (maxX - minX))
	}
}
