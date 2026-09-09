import Foundation
import Observation
import Vision

/// Active challenge–response liveness.
///
/// The camera names a specific, randomly chosen action — turn left, turn right, nod, blink,
/// open your mouth — and passes only when it sees that action actually performed. This is the
/// liveness a webcam can do well: it asks for *motion*, which a flat photo can't produce, and
/// because the ask is random a pre-recorded clip of you doing one thing won't answer a demand
/// for another. It's the piece the passive texture model could never be — that one called a
/// real face a spoof; this one asks the real face to prove itself and a photo simply can't.
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
			case .turnLeft: return "Turn your head left"
			case .turnRight: return "Turn your head right"
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

	// How far counts. Radians for pose; landmark ratios for eyes and mouth.
	private static let turnDelta = 0.30      // head clearly turned from where it started
	private static let nodDelta = 0.18       // chin dropped from where it started
	private static let eyeOpen: Float = 0.22
	private static let eyeShut: Float = 0.14
	private static let mouthClosed: Float = 0.16
	private static let mouthOpen: Float = 0.32

	init() {
		action = Action.allCases.randomElement() ?? .blink
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
	}

	/// Feed each frame. Sets `isComplete` once the current action has been seen.
	func consume(_ sample: FaceSample) {
		guard !isComplete else { return }
		switch action {
		// Raw `yaw`, and measured rather than reasoned about.
		//
		// This briefly used a `mirroredYaw` helper, on the argument that the prompts are
		// phrased in the user's own left and right while `yaw` is measured in the camera's
		// frame. The argument sounds right and is not: tested against a real head, "Turn your
		// head left" then completed only when the head turned *right*.
		//
		// What is actually true, from that test: turning right raises Vision's yaw, so
		// turning left lowers it. That measurement is now the single stated convention on
		// `FacePose.yaw`, and the helper that contradicted it has been deleted — `ringAngle`
		// reads the same raw value this does. The live yaw figure is in Test Recognition's
		// Details, so the next person to doubt any of this can watch it rather than argue.
		case .turnLeft:
			let base = baseYaw ?? sample.pose.yaw; baseYaw = base
			if sample.pose.yaw - base <= -Self.turnDelta { isComplete = true }
		case .turnRight:
			let base = baseYaw ?? sample.pose.yaw; baseYaw = base
			if sample.pose.yaw - base >= Self.turnDelta { isComplete = true }
		case .nod:
			let base = basePitch ?? sample.pose.pitch; basePitch = base
			// Chin down is a *rise* in pitch — Vision's positive pitch is chin down. This
			// read `<= -nodDelta`, so "Nod your head" was satisfied by lifting your chin.
			if sample.pose.pitch - base >= Self.nodDelta { isComplete = true }
		case .blink:
			guard let o = Self.eyeOpenness(sample.landmarks) else { return }
			if o > Self.eyeOpen { eyesWereOpen = true }
			if eyesWereOpen && o < Self.eyeShut { isComplete = true }
		case .openMouth:
			guard let m = Self.mouthOpenness(sample.landmarks) else { return }
			if m < Self.mouthClosed { mouthWasClosed = true }
			if mouthWasClosed && m > Self.mouthOpen { isComplete = true }
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
		let vals = [openness(lm.leftEye), openness(lm.rightEye)].compactMap { $0 }
		guard !vals.isEmpty else { return nil }
		return vals.reduce(0, +) / Float(vals.count)
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
