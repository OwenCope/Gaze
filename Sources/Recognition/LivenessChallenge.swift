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
///
/// Each directional action additionally pins *which estimator* its baseline came from
/// (Vision or the landmark fallback, tracked per axis). The two disagree on the zero point
/// and the fallback's scale is uncalibrated, so a source change on the action's axis discards
/// that action's baseline and partial movement instead of reading as a turn. The other axis
/// never matters: pitch estimates come and go during a turn without disturbing it, and
/// blink/open-mouth ignore pose entirely.
@MainActor
@Observable
final class LivenessChallenge {

	enum Action: CaseIterable {
		case turnLeft, turnRight, nod, blink, openMouth, lookLeft, lookRight

		/// True for the eye-only actions, which track pupil shift instead of head pose
		/// and are excluded from the untracked-gaze fallback pick.
		var isLook: Bool { self == .lookLeft || self == .lookRight }

		var prompt: String {
			switch self {
			case .turnLeft: return "Turn slightly left"
			case .turnRight: return "Turn slightly right"
			case .nod: return "Nod your head"
			case .blink: return "Blink"
			case .openMouth: return "Open your mouth"
			case .lookLeft, .lookRight: return "Follow the light"
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
			case .lookLeft: return (-1, 0, true)
			case .lookRight: return (1, 0, true)
			}
		}

		var symbol: String {
			switch self {
			case .turnLeft: return "arrowshape.left.fill"
			case .turnRight: return "arrowshape.right.fill"
			case .nod: return "arrowshape.down.fill"
			case .blink: return "eye.fill"
			case .openMouth: return "mouth.fill"
			case .lookLeft, .lookRight: return "eye.fill"
			}
		}
	}

	private(set) var action: Action = .blink
	private(set) var isComplete = false

	/// The head pose at the moment the challenge began, for the directional actions. Movement
	/// is measured from here, so absolute pose and per-camera zero offsets don't matter.
	private var baseYaw: Double?
	private var basePitch: Double?
	/// Which estimator each directional baseline came from. A baseline measured with one
	/// source is never compared against movement measured with another.
	private var baseYawSource: FacePose.AxisSource?
	private var basePitchSource: FacePose.AxisSource?
	/// Eyes/mouth need a "returned to rest" beat before the action counts, so the user has to
	/// move *into* it rather than already being there.
	private var eyesWereOpen = false
	/// The person's own resting eye openness, the max of the baseline frames, so
	/// blink thresholds scale to narrow eyes instead of assuming a wide-open rest.
	private var baselineEyeOpenness: Float = 0
	private var mouthWasClosed = false
	private var baselineSamples = 0
	private var movementSamples = 0
	private var observedMovement = false
	/// Pupil shift at the moment the look action started, for the eye-only actions.
	/// Movement is measured from here, the same relative rule as the head-pose baselines.
	private var baselineGaze: Double?
	/// Consecutive look-action frames with no measurable gaze, for the untracked fallback.
	private var nilGazeSamples = 0

	// How far counts. Radians for pose; landmark ratios for eyes and mouth.
	private static let turnDelta = 0.30      // head clearly turned from where it started
	private static let nodDelta = 0.18       // chin dropped from where it started
	private static let headStillLimit = 8 * Double.pi / 180  // head may not wander during a look
	private static let nilGazeLimit = 15     // unmeasurable frames before offering a non-look action

	// Follow the light. The light rests at the centre, glides to the prompted edge,
	// holds, and glides back, over and over; each pass is scored on its own. A laptop
	// screen is small enough to see the edge without moving your eyes, so one glance
	// proves little. Eyes that track a moving light, in time with it, for a whole
	// pass are hard to fake and forgiving of a few noisy frames.
	static let lookPeriod = 1.3
	private static let lookMinSamples = 7
	private static let lookMinCorrelation = 0.45
	private static let lookMinRange = 0.03
	private static let lookFailureLimit = 3
	/// Total passes before giving up, so short-sample passes that never count as
	/// failures still can't loop forever.
	private static let lookPassLimit = 6

	/// When the light started its path, set by the lock-screen overlay so the light
	/// and the scoring share one clock. Nil elsewhere (Test Recognition, tests): the
	/// challenge then starts its own clock at the first steady frame.
	static var lookOrigin: TimeInterval?
	/// True while the lock-screen light is up and waiting for the challenge to start it.
	static var lookOverlayWaiting = false

	/// Where the light is, 0 at the centre to 1 at the edge, `elapsed` seconds into
	/// the repeating path: rest 0.1 s, glide out 0.45 s, hold 0.2 s, glide back
	/// 0.45 s, rest 0.1 s. A 0.85 s pass was tried and failed every time on the lock
	/// screen: frames arrive about ten a second there, too few to score a pass that short.
	static func lookTargetPosition(elapsed: Double) -> Double {
		guard elapsed.isFinite, elapsed >= 0 else { return 0 }
		let t = elapsed.truncatingRemainder(dividingBy: lookPeriod)
		func ease(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * (3 - 2 * u) }
		switch t {
		case ..<0.1: return 0
		case ..<0.55: return ease((t - 0.1) / 0.45)
		case ..<0.75: return 1
		case ..<1.2: return 1 - ease((t - 0.75) / 0.45)
		default: return 0
		}
	}

	/// Seeds the light's direction for each pass, set by the overlay with `lookOrigin` so
	/// the light and the scoring agree. Every pass starts from the centre and heads off in
	/// a fresh random direction.
	static var lookSeed: UInt64?

	/// The direction of pass `cycle`, in radians: 0 is screen right, counter-clockwise.
	static func lookAngle(cycle: Int, seed: UInt64) -> Double {
		var z = seed &+ UInt64(truncatingIfNeeded: cycle) &* 0x9E37_79B9_7F4A_7C15
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		z ^= z >> 31
		// Left or right, tilted at most 20 degrees. With the lid opened wide the camera
		// looks down at the face, the upper lids cover the irises, and up-and-down eye
		// movement all but disappears; side to side stays readable at any angle.
		let u = Double(z >> 11) / Double(1 << 53)
		let side = u < 0.5 ? 0.0 : Double.pi
		let tilt = (u.truncatingRemainder(dividingBy: 0.5) * 2 - 1) * (20 * Double.pi / 180)
		return side + tilt
	}

	/// Eyes move less up and down than side to side for the same distance on screen,
	/// and the light travels less far vertically. The expected vertical pupil shift per
	/// unit of horizontal one; tune from Check eyes.
	static let lookVerticalGain = 0.5
	private static let lookMaxCrossTalk = 1.0  // The light is side to side now; up-down noise shouldn't fail a pass

	/// Test hook; the lock screen uses the real clock.
	var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	private var ownLookOrigin: TimeInterval?
	private var lookCycle: Int?
	private var lookCycleValid = true
	private var lookSamples: [(x: Double, y: Double?, target: Double, elapsed: Double)] = []
	/// This frame's vertical gaze, set by the consume entry points; nil when unmeasured.
	private var frameGazeY: Double?
	private var baselineGazeY: Double?
	private var ownLookSeed: UInt64?
	/// Fixes every pass's direction, for tests. Radians, 0 = screen right, counter-clockwise.
	var lookAngleOverride: Double?
	private var lookFailures = 0
	/// One compact line per finished look pass ("n=12 r=0.61 range=0.07 cross=0.2
	/// spoilt=false passed=true"), so real-hardware misses can be diagnosed from the log.
	/// Kept for the whole attempt, across passes and movement switches, for the attempt log.
	private(set) var lookPassLog: [String] = []
	private var lookPassCount = 0
	private static let blinkShutFraction: Float = 0.55
	private static let blinkOpenFraction: Float = 0.8
	private static let blinkDropFloor: Float = 0.03
	private static let mouthClosed: Float = 0.16
	private static let mouthOpen: Float = 0.32
	var isBaselineReady: Bool { baselineSamples >= 3 }
	var isReturningToRest: Bool { observedMovement && !isComplete }
	var guidancePrompt: String {
		guard isReturningToRest else { return action.prompt }
		switch action {
		case .turnLeft, .turnRight, .nod: return "Return to your starting position"
		case .blink: return "Open your eyes"
		case .openMouth: return "Relax your mouth"
		case .lookLeft, .lookRight: return "Look back at the middle"
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

	/// What one consumed sample did to pose-source tracking. Discardable: callers that
	/// ignore it keep the safe internal behaviour (the baseline is still invalidated);
	/// the unlock loop uses it to drop its wider proof as well.
	struct ConsumeResult: Sendable, Equatable {
		/// True when this sample discarded a held baseline or partial movement because
		/// the current action's axis changed estimator, went unavailable, or arrived
		/// nonfinite.
		var poseSourceInvalidated = false
	}

	func poseMeasurement(yaw: Double, pitch: Double) -> PoseMeasurement? {
		poseMeasurement(yaw: yaw, pitch: pitch, yawSource: .vision, pitchSource: .vision)
	}

	/// Source-aware diagnostics. Returns nil across estimators: an offset from a Vision
	/// baseline to a landmark excursion (or involving an unavailable axis) is not a
	/// movement reading.
	func poseMeasurement(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource) -> PoseMeasurement? {
		guard isBaselineReady, yaw.isFinite, pitch.isFinite else { return nil }
		let baseline: Double?
		let baselineSource: FacePose.AxisSource?
		let valueSource: FacePose.AxisSource
		let value: Double
		let target: Double
		switch action {
		case .turnLeft, .turnRight:
			baseline = baseYaw
			baselineSource = baseYawSource
			value = yaw
			valueSource = yawSource
			target = action == .turnLeft ? Self.turnDelta : -Self.turnDelta
		case .nod:
			baseline = basePitch
			baselineSource = basePitchSource
			value = pitch
			valueSource = pitchSource
			target = Self.nodDelta
		case .blink, .openMouth, .lookLeft, .lookRight:
			return nil
		}
		guard let baseline, let baselineSource,
			baselineSource != .unavailable, valueSource != .unavailable,
			baselineSource == valueSource else { return nil }
		return PoseMeasurement(offset: value - baseline, target: target,
			returnTolerance: abs(target) / 3)
	}

	/// The movements people can choose between in Settings. Turn covers both
	/// directions and Follow the light both sides, so the side stays random.
	enum Movement: String, CaseIterable {
		case turn, nod, blink, openMouth, followLight

		var actions: [Action] {
			switch self {
			case .turn: return [.turnLeft, .turnRight]
			case .nod: return [.nod]
			case .blink: return [.blink]
			case .openMouth: return [.openMouth]
			case .followLight: return [.lookLeft, .lookRight]
			}
		}
	}

	/// Settings key for the movements turned off, as `Movement` raw values.
	static let disabledMovementsKey = "disabledMovements"

	/// The movements Gaze may ask for, read straight from defaults so this file needs
	/// no Preferences. Never empty: with everything off, all of them are offered.
	static var offeredActions: [Action] {
		let defaults = UserDefaults.standard
		var off = Set(defaults.stringArray(forKey: disabledMovementsKey) ?? [])
		// The single switch this replaced.
		if defaults.object(forKey: disabledMovementsKey) == nil,
			defaults.object(forKey: "lookMovement") as? Bool == false {
			off.insert(Movement.followLight.rawValue)
		}
		let actions = Movement.allCases.filter { !off.contains($0.rawValue) }.flatMap(\.actions)
		return actions.isEmpty ? Action.allCases : actions
	}

	/// A different offered movement that needs no eye tracking, for when the eyes
	/// cannot be followed.
	private func fallbackAction() -> Action {
		let offered = Self.offeredActions.filter { $0 != action && !$0.isLook }
		return offered.randomElement()
			?? Action.allCases.filter { $0 != action && !$0.isLook }.randomElement() ?? .blink
	}

	init(action: Action? = nil) {
		self.action = action ?? Self.offeredActions.randomElement() ?? .blink
	}

	/// Pick a fresh random action, different from the current one, and start over.
	func next() {
		action = Self.offeredActions.filter { $0 != action }.randomElement() ?? action
		reset()
	}

	func reset() {
		isComplete = false
		lookPassCount = 0
		baseYaw = nil
		basePitch = nil
		baseYawSource = nil
		basePitchSource = nil
		eyesWereOpen = false
		baselineEyeOpenness = 0
		mouthWasClosed = false
		baselineSamples = 0
		movementSamples = 0
		observedMovement = false
		baselineGaze = nil
		nilGazeSamples = 0
		ownLookOrigin = nil
		ownLookSeed = nil
		baselineGazeY = nil
		lookCycle = nil
		lookCycleValid = true
		lookSamples = []
		lookFailures = 0
	}

	/// Which pose axis the current directional action measures. Passed instead of an
	/// inout baseline so source-invalidation helpers can touch the stored baseline
	/// without overlapping-access conflicts.
	private enum PoseAxis { case yaw, pitch }

	/// Drops the current action's pose baseline and any partial movement, keeping the
	/// selected action itself: the next samples reacquire from wherever the head is.
	/// Never called for blink/open-mouth, which have no pose baseline to drop.
	private func invalidatePoseEvidence() {
		switch action {
		case .turnLeft, .turnRight, .lookLeft, .lookRight:
			baseYaw = nil
			baseYawSource = nil
		case .nod:
			basePitch = nil
			basePitchSource = nil
		case .blink, .openMouth:
			return
		}
		baselineSamples = 0
		movementSamples = 0
		observedMovement = false
		baselineGaze = nil
		nilGazeSamples = 0
	}

	/// Eyes narrower than this, in camera pixels, are too far away for the iris model to
	/// follow reliably (measured on Owen's MacBook Air: fine near, failing a little further).
	static let lookMinEyeWidth: Double = 32

	/// Swaps Follow the light for another movement when the face is too far for it.
	/// Checked before the prompt shows, so a far-away person never sees it at all.
	private func avoidLookWhenFar(_ sample: FaceSample) {
		guard action.isLook, let eyeWidth = PupilLocator.eyeWidthPixels(sample),
			eyeWidth < Self.lookMinEyeWidth else { return }
		lookPassLog.append("too far for Follow the light (eyes \(Int(eyeWidth)) px); switched movement")
		action = fallbackAction()
		reset()
	}

	func prepareBaseline(_ sample: FaceSample) {
		avoidLookWhenFar(sample)
		let eyes2D = action.isLook ? PupilLocator.gaze(sample) : nil
		frameGazeY = eyes2D?.y
		prepareBaseline(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			yawSource: sample.pose.yawSource, pitchSource: sample.pose.pitchSource,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks),
			gaze: action.isLook ? (eyes2D?.x ?? Self.gazeOffset(sample.landmarks)) : nil)
	}

	func prepareBaseline(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?, gaze: Double? = nil, gazeY: Double? = nil) {
		frameGazeY = gazeY
		prepareBaseline(yaw: yaw, pitch: pitch, yawSource: .vision, pitchSource: .vision,
			eyes: eyes, mouth: mouth, gaze: gaze)
	}

	/// Source-aware baseline. Only the current action's axis can build or break its
	/// baseline: pitch provenance never disturbs a turn, and blink/open-mouth ignore
	/// pose altogether.
	func prepareBaseline(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?, gaze: Double? = nil) {
		guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else { reset(); return }
		isComplete = false
		movementSamples = 0
		observedMovement = false
		switch action {
		case .turnLeft, .turnRight:
			guard yaw.isFinite, yawSource != .unavailable else { invalidatePoseEvidence(); return }
			preparePoseBaseline(yaw, source: yawSource, axis: .yaw)
		case .lookLeft, .lookRight:
			guard yaw.isFinite, yawSource != .unavailable else { invalidatePoseEvidence(); return }
			prepareLookBaseline(yaw: yaw, yawSource: yawSource, gaze: gaze)
		case .nod:
			guard pitch.isFinite, pitchSource != .unavailable else { invalidatePoseEvidence(); return }
			preparePoseBaseline(pitch, source: pitchSource, axis: .pitch)
		case .blink:
			if let e = eyes, e.isFinite, e >= 0, e > 0 {
				baselineEyeOpenness = baselineSamples == 0 ? e : max(baselineEyeOpenness, e)
				baselineSamples = min(3, baselineSamples + 1)
			} else {
				baselineSamples = 0
			}
			eyesWereOpen = isBaselineReady
		case .openMouth:
			baselineSamples = mouth.map { $0 < Self.mouthClosed } == true ? min(3, baselineSamples + 1) : 0
			mouthWasClosed = isBaselineReady
		}
	}

	/// Baseline anchor for the eye-only actions: the head-pose steadiness rule pins yaw,
	/// and the first steady frame's gaze becomes the pupil anchor. Frames with no
	/// measurable gaze neither build nor break the baseline here; the consume path
	/// switches to a non-look action after enough of them.
	private func prepareLookBaseline(yaw: Double, yawSource: FacePose.AxisSource, gaze: Double?) {
		guard let gaze, gaze.isFinite else { return }
		if let previous = baseYaw, let previousSource = baseYawSource,
			previousSource == yawSource, abs(yaw - previous) <= 0.05 {
			baselineSamples = min(3, baselineSamples + 1)
		} else {
			baseYaw = yaw
			baseYawSource = yawSource
			baselineGaze = gaze
			baselineGazeY = frameGazeY
			baselineSamples = 1
		}
	}

	private func preparePoseBaseline(_ value: Double, source: FacePose.AxisSource, axis: PoseAxis) {
		let previous: Double?
		let previousSource: FacePose.AxisSource?
		switch axis {
		case .yaw: previous = baseYaw; previousSource = baseYawSource
		case .pitch: previous = basePitch; previousSource = basePitchSource
		}
		if let previous, let previousSource,
			previousSource == source, abs(value - previous) <= 0.05 {
			baselineSamples = min(3, baselineSamples + 1)
		} else {
			switch axis {
			case .yaw: baseYaw = value; baseYawSource = source
			case .pitch: basePitch = value; basePitchSource = source
			}
			baselineSamples = 1
		}
	}

	/// Feed each frame. Sets `isComplete` once the current action has been seen.
	@discardableResult
	func consume(_ sample: FaceSample) -> ConsumeResult {
		avoidLookWhenFar(sample)
		let eyes2D = action.isLook ? PupilLocator.gaze(sample) : nil
		frameGazeY = eyes2D?.y
		return consumeFrame(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			yawSource: sample.pose.yawSource, pitchSource: sample.pose.pitchSource,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks),
			gaze: action.isLook ? (eyes2D?.x ?? Self.gazeOffset(sample.landmarks)) : nil)
	}

	@discardableResult
	func consume(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?, gaze: Double? = nil, gazeY: Double? = nil) -> ConsumeResult {
		frameGazeY = gazeY
		return consumeFrame(yaw: yaw, pitch: pitch, yawSource: .vision, pitchSource: .vision,
			eyes: eyes, mouth: mouth, gaze: gaze)
	}

	/// Source-aware consumption with an explicit vertical gaze, for tests.
	@discardableResult
	func consume(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?, gaze: Double? = nil, gazeY: Double?) -> ConsumeResult {
		frameGazeY = gazeY
		return consumeFrame(yaw: yaw, pitch: pitch, yawSource: yawSource, pitchSource: pitchSource,
			eyes: eyes, mouth: mouth, gaze: gaze)
	}

	/// Source-aware consumption. A sample from a different estimator than the baseline —
	/// or with the action's axis unavailable or nonfinite — discards the baseline and
	/// partial movement and reports `poseSourceInvalidated`, so the unlock loop can drop
	/// its wider proof instead of completing across estimators. The sample itself starts
	/// the fresh baseline where possible. Unrelated axes — and, for blink/open-mouth,
	/// all pose input — never invalidate.
	@discardableResult
	func consume(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?, gaze: Double? = nil) -> ConsumeResult {
		frameGazeY = nil
		return consumeFrame(yaw: yaw, pitch: pitch, yawSource: yawSource, pitchSource: pitchSource,
			eyes: eyes, mouth: mouth, gaze: gaze)
	}

	private func consumeFrame(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?, gaze: Double?) -> ConsumeResult {
		guard !isComplete else { return ConsumeResult() }
		switch action {
		// In the mirrored camera preview, leftward turns increase Vision yaw.
		// Verified against the September 15 recording; see docs/internal/CHALLENGE-INVESTIGATION.md.
		case .turnLeft:
			return consumeDirectional(yaw, source: yawSource, axis: .yaw,
				threshold: Self.turnDelta, direction: 1, eyes: eyes, mouth: mouth)
		case .turnRight:
			return consumeDirectional(yaw, source: yawSource, axis: .yaw,
				threshold: Self.turnDelta, direction: -1, eyes: eyes, mouth: mouth)
		// Same polarity as the turns: looking toward the person's own left shifts
		// the pupils toward +x in landmark space, matching +yaw.
		case .lookLeft:
			return consumeLook(yaw: yaw, yawSource: yawSource, direction: 1,
				eyes: eyes, mouth: mouth, gaze: gaze)
		case .lookRight:
			return consumeLook(yaw: yaw, yawSource: yawSource, direction: -1,
				eyes: eyes, mouth: mouth, gaze: gaze)
		case .nod:
			return consumeDirectional(pitch, source: pitchSource, axis: .pitch,
				threshold: Self.nodDelta, direction: 1, eyes: eyes, mouth: mouth)
		case .blink:
			guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
				mouth.map({ $0.isFinite && $0 >= 0 }) ?? true,
				let eyes else { reset(); return ConsumeResult() }
			if !eyesWereOpen {
				if eyes > 0 {
					baselineEyeOpenness = baselineSamples == 0 ? eyes : max(baselineEyeOpenness, eyes)
					baselineSamples += 1
				} else {
					baselineSamples = 0
				}
				eyesWereOpen = baselineSamples >= 3
			} else if !observedMovement, eyes > baselineEyeOpenness {
				baselineEyeOpenness = eyes
			} else if eyes < baselineEyeOpenness * Self.blinkShutFraction,
				baselineEyeOpenness - eyes >= Self.blinkDropFloor {
				observedMovement = true
			} else if observedMovement, eyes > baselineEyeOpenness * Self.blinkOpenFraction {
				isComplete = true
			}
			return ConsumeResult()
		case .openMouth:
			guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
				mouth.map({ $0.isFinite && $0 >= 0 }) ?? true,
				let mouth else { reset(); return ConsumeResult() }
			if !mouthWasClosed {
				baselineSamples = mouth < Self.mouthClosed ? baselineSamples + 1 : 0
				mouthWasClosed = baselineSamples >= 3
			} else if !observedMovement {
				movementSamples = mouth > Self.mouthOpen ? movementSamples + 1 : 0
				observedMovement = movementSamples >= 2
			} else if mouth < Self.mouthClosed {
				isComplete = true
			}
			return ConsumeResult()
		}
	}

	private func consumeDirectional(_ value: Double, source: FacePose.AxisSource, axis: PoseAxis, threshold: Double, direction: Double, eyes: Float?, mouth: Float?) -> ConsumeResult {
		switch axis {
		case .yaw:
			guard value.isFinite, source != .unavailable else {
				let hadEvidence = baseYaw != nil || baselineSamples > 0 || movementSamples > 0 || observedMovement
				invalidatePoseEvidence()
				return ConsumeResult(poseSourceInvalidated: hadEvidence)
			}
		case .pitch:
			guard value.isFinite, source != .unavailable else {
				let hadEvidence = basePitch != nil || baselineSamples > 0 || movementSamples > 0 || observedMovement
				invalidatePoseEvidence()
				return ConsumeResult(poseSourceInvalidated: hadEvidence)
			}
		}
		guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else {
			invalidatePoseEvidence()
			return ConsumeResult()
		}
		return consumePose(value, source: source, axis: axis,
			threshold: threshold, direction: direction)
	}

	/// Eye-only detection: the pupils must shift toward the prompted side while the head
	/// stays within 8 degrees of its baseline yaw. A head turn never counts, and any
	/// frame where the head wandered resets the observed progress without failing.
	/// Frames with no measurable gaze count toward the untracked fallback instead.
	private func consumeLook(yaw: Double, yawSource: FacePose.AxisSource, direction: Double, eyes: Float?, mouth: Float?, gaze: Double?) -> ConsumeResult {
		guard yaw.isFinite, yawSource != .unavailable else {
			let hadEvidence = baseYaw != nil || baselineSamples > 0 || movementSamples > 0 || observedMovement
			invalidatePoseEvidence()
			return ConsumeResult(poseSourceInvalidated: hadEvidence)
		}
		guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else {
			invalidatePoseEvidence()
			return ConsumeResult()
		}
		guard let gaze, gaze.isFinite else {
			nilGazeSamples += 1
			guard nilGazeSamples >= Self.nilGazeLimit else { return ConsumeResult() }
			lookPassLog.append("eyes unreadable for \(Self.nilGazeLimit) frames; switched movement")
			action = fallbackAction()
			reset()
			return ConsumeResult()
		}
		nilGazeSamples = 0
		if baselineSamples < 3 {
			if let previous = baseYaw, let previousSource = baseYawSource,
				previousSource == yawSource, abs(yaw - previous) <= 0.05 {
				baselineSamples += 1
			} else {
				let hadPartial = baseYaw != nil || baselineSamples > 0
				let sourceChanged = baseYawSource != nil && baseYawSource != yawSource
				baseYaw = yaw
				baseYawSource = yawSource
				baselineGaze = gaze
			baselineGazeY = frameGazeY
				baselineGazeY = frameGazeY
				baselineSamples = 1
				if hadPartial && sourceChanged { return ConsumeResult(poseSourceInvalidated: true) }
			}
			return ConsumeResult()
		}
		guard let anchor = baselineGaze, let base = baseYaw, let baseSource = baseYawSource,
			baseSource == yawSource else {
			baseYaw = yaw
			baseYawSource = yawSource
			baselineGaze = gaze
			baselineGazeY = frameGazeY
			baselineSamples = 1
			movementSamples = 0
			observedMovement = false
			return ConsumeResult(poseSourceInvalidated: true)
		}
		let now = clock()
		if Self.lookOrigin == nil, Self.lookOverlayWaiting {
			Self.lookOrigin = now
			Self.lookOverlayWaiting = false
		}
		let origin = Self.lookOrigin ?? {
			if ownLookOrigin == nil { ownLookOrigin = now }
			return ownLookOrigin!
		}()
		let elapsed = max(0, now - origin)
		let cycle = Int(elapsed / Self.lookPeriod)
		if let current = lookCycle, cycle != current {
			// A pass just finished: score it, log it, then start collecting the next.
			let spoilt = !lookCycleValid
			let score = scoreLookPass(angle: angle(forCycle: current))
			let passed = !spoilt && score.passed
			lookPassCount += 1
			lookPassLog.append("n=\(score.samples) r=\(String(format: "%.2f", score.correlation)) range=\(String(format: "%.2f", score.range)) cross=\(String(format: "%.2f", score.cross)) spoilt=\(spoilt) passed=\(passed)")
			if passed {
				observedMovement = true
				isComplete = true
				return ConsumeResult()
			}
			// A pass with too few samples is a camera/frame shortfall, not the
			// person failing: start the next pass without counting a failure.
			let shortfall = !spoilt && score.samples < Self.lookMinSamples
			// Every other non-passing pass counts, including ones spoilt by a
			// head turn, so it never loops forever: after a few, a different
			// movement is asked for.
			if !shortfall { lookFailures += 1 }
			if lookFailures >= Self.lookFailureLimit || lookPassCount >= Self.lookPassLimit {
				action = fallbackAction()
				reset()
				return ConsumeResult()
			}
			lookSamples = []
			lookCycleValid = true
		}
		lookCycle = cycle
		// Turning the head to follow spoils this pass; the next one starts clean.
		guard abs(yaw - base) <= Self.headStillLimit else {
			lookCycleValid = false
			lookSamples = []
			return ConsumeResult()
		}
		if lookCycleValid {
			let dy = frameGazeY.flatMap { y in baselineGazeY.map { y - $0 } }
			lookSamples.append((gaze - anchor, dy, Self.lookTargetPosition(elapsed: elapsed), elapsed))
		}
		return ConsumeResult()
	}

	private func angle(forCycle cycle: Int) -> Double {
		if let lookAngleOverride { return lookAngleOverride }
		let seed = Self.lookSeed ?? {
			if ownLookSeed == nil { ownLookSeed = UInt64.random(in: .min ... .max) }
			return ownLookSeed!
		}()
		return Self.lookAngle(cycle: cycle, seed: seed)
	}

	/// One finished look pass's numbers and whether it passed. Same decision as
	/// before: fitted only when the samples allow, passing only on enough samples
	/// with a tight positive visible fit and little off-axis movement.
	private struct LookPassScore {
		var passed: Bool
		var samples: Int
		var correlation: Double
		var range: Double
		/// Off-axis movement relative to on-axis (|side slope| / slope).
		var cross: Double
	}

	/// Whether the eyes followed the light in the pass just collected.
	///
	/// The pupil movement is projected onto the light's direction and fitted against
	/// the light's distance from the centre. A pass needs the fit to be tight
	/// (correlation), the slope positive and visible (the eyes went the light's way,
	/// far enough), and little of the movement off to the side of that direction.
	private func scoreLookPass(angle: Double) -> LookPassScore {
		// Screen right is image -x for the pupils; up is +y.
		let ex = -cos(angle), ey = sin(angle) * Self.lookVerticalGain
		let norm = ex * ex + ey * ey
		guard norm > 0 else { return LookPassScore(passed: false, samples: 0, correlation: 0, range: 0, cross: 0) }
		let needsVertical = abs(sin(angle)) > 0.25
		var along: [Double] = [], across: [Double] = [], elapsed: [Double] = []
		for sample in lookSamples {
			guard let y = sample.y ?? (needsVertical ? nil : 0) else { continue }
			along.append((sample.x * ex + y * ey) / norm)
			across.append((-sample.x * ey + y * ex) / norm)
			elapsed.append(sample.elapsed)
		}
		// From further away each frame's pupil reading jitters by a few pixels, but the
		// light moves smoothly over half a second. A short centred average (5 frames, about
		// a fifth of a second) cancels the jitter and keeps the movement. A still or wrong
		// face gains nothing: its readings still don't follow the light.
		along = Self.smoothed(along, window: 5)
		across = Self.smoothed(across, window: 5)
		// Eyes trail a moving light by about a tenth to a quarter of a second, and more
		// so from further away. Score against the light as it was a moment earlier, at
		// whichever small lag fits best.
		let targets = [0.0, 0.08, 0.16, 0.24].map { lag in
			elapsed.map { Self.lookTargetPosition(elapsed: max(0, $0 - lag)) }
		}.max { a, b in
			(Self.fit(along, a)?.correlation ?? -1) < (Self.fit(along, b)?.correlation ?? -1)
		} ?? []
		var correlation = 0.0, range = 0.0, cross = 0.0
		var passed = false
		if let fit = Self.fit(along, targets), let side = Self.fit(across, targets) {
			let sorted = along.sorted()
			range = sorted[Int(Double(sorted.count - 1) * 0.9)] - sorted[Int(Double(sorted.count - 1) * 0.1)]
			correlation = fit.correlation
			cross = fit.slope != 0 ? abs(side.slope / fit.slope) : 0
			passed = along.count >= Self.lookMinSamples
				&& fit.correlation >= Self.lookMinCorrelation && fit.slope > 0 && range >= Self.lookMinRange
				&& abs(side.slope) <= Self.lookMaxCrossTalk * fit.slope
		}
		return LookPassScore(passed: passed, samples: along.count,
			correlation: correlation, range: range, cross: cross)
	}

	/// Centred moving average; the ends average over what is available.
	static func smoothed(_ values: [Double], window: Int) -> [Double] {
		guard values.count > 2, window > 1 else { return values }
		let half = window / 2
		return values.indices.map { i in
			let lo = max(0, i - half), hi = min(values.count - 1, i + half)
			return values[lo...hi].reduce(0, +) / Double(hi - lo + 1)
		}
	}

	/// Least-squares slope of `values` against `targets`, and their correlation.
	private static func fit(_ values: [Double], _ targets: [Double]) -> (slope: Double, correlation: Double)? {
		let n = Double(values.count)
		guard n > 1 else { return nil }
		let mv = values.reduce(0, +) / n, mt = targets.reduce(0, +) / n
		var cov = 0.0, vv = 0.0, vt = 0.0
		for (v, t) in zip(values, targets) {
			cov += (v - mv) * (t - mt); vv += (v - mv) * (v - mv); vt += (t - mt) * (t - mt)
		}
		guard vt > 0 else { return nil }
		return (cov / vt, vv > 0 ? cov / (vv.squareRoot() * vt.squareRoot()) : 0)
	}

	private func consumePose(_ value: Double, source: FacePose.AxisSource, axis: PoseAxis, threshold: Double, direction: Double) -> ConsumeResult {
		let previous: Double?
		let previousSource: FacePose.AxisSource?
		switch axis {
		case .yaw: previous = baseYaw; previousSource = baseYawSource
		case .pitch: previous = basePitch; previousSource = basePitchSource
		}
		if baselineSamples < 3 {
			if let previous, let previousSource,
				previousSource == source, abs(value - previous) <= 0.05 {
				baselineSamples += 1
			} else {
				let hadPartial = previous != nil || baselineSamples > 0
				let sourceChanged = previousSource != nil && previousSource != source
				switch axis {
				case .yaw: baseYaw = value; baseYawSource = source
				case .pitch: basePitch = value; basePitchSource = source
				}
				baselineSamples = 1
				if hadPartial && sourceChanged { return ConsumeResult(poseSourceInvalidated: true) }
			}
			return ConsumeResult()
		}
		guard let current = previous, let currentSource = previousSource else { return ConsumeResult() }
		guard currentSource == source else {
			switch axis {
			case .yaw: baseYaw = value; baseYawSource = source
			case .pitch: basePitch = value; basePitchSource = source
			}
			baselineSamples = 1
			movementSamples = 0
			observedMovement = false
			return ConsumeResult(poseSourceInvalidated: true)
		}
		let delta = value - current
		if !observedMovement {
			movementSamples = delta * direction >= threshold ? movementSamples + 1 : 0
			observedMovement = movementSamples >= 2
		} else if abs(delta) <= threshold / 3 {
			isComplete = true
		}
		return ConsumeResult()
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

	/// Pupil shift within the eye, as a fraction of eye width: (pupil.x - eyeCentre.x)
	/// / eyeWidth per eye, averaged across the usable eyes. Positive means the pupils
	/// sit toward +x in landmark space, which reads as the person's own left — the
	/// same polarity as yaw, where a leftward turn increases the angle.
	static func gazeOffset(_ landmarks: VNFaceLandmarks2D?) -> Double? {
		func shift(eye: VNFaceLandmarkRegion2D?, pupil: VNFaceLandmarkRegion2D?) -> Double? {
			guard let outline = eye?.normalizedPoints, outline.count >= 2,
				let dots = pupil?.normalizedPoints, !dots.isEmpty else { return nil }
			let xs = outline.map(\.x)
			guard let minX = xs.min(), let maxX = xs.max(), maxX - minX >= 1e-3 else { return nil }
			let pupilX = dots.map(\.x).reduce(0, +) / Double(dots.count)
			return (pupilX - (minX + maxX) / 2) / (maxX - minX)
		}
		let shifts = [shift(eye: landmarks?.leftEye, pupil: landmarks?.leftPupil),
			shift(eye: landmarks?.rightEye, pupil: landmarks?.rightPupil)].compactMap { $0 }
		guard !shifts.isEmpty else { return nil }
		return shifts.reduce(0, +) / Double(shifts.count)
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
