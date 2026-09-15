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
	/// Which estimator each directional baseline came from. A baseline measured with one
	/// source is never compared against movement measured with another.
	private var baseYawSource: FacePose.AxisSource?
	private var basePitchSource: FacePose.AxisSource?
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
		case .turnLeft, .turnRight, .nod: return "Return to your starting position"
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
		case .blink, .openMouth:
			return nil
		}
		guard let baseline, let baselineSource,
			baselineSource != .unavailable, valueSource != .unavailable,
			baselineSource == valueSource else { return nil }
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
		baseYawSource = nil
		basePitchSource = nil
		eyesWereOpen = false
		mouthWasClosed = false
		baselineSamples = 0
		movementSamples = 0
		observedMovement = false
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
		case .turnLeft, .turnRight:
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
	}

	func prepareBaseline(_ sample: FaceSample) {
		prepareBaseline(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			yawSource: sample.pose.yawSource, pitchSource: sample.pose.pitchSource,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks))
	}

	func prepareBaseline(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?) {
		prepareBaseline(yaw: yaw, pitch: pitch, yawSource: .vision, pitchSource: .vision,
			eyes: eyes, mouth: mouth)
	}

	/// Source-aware baseline. Only the current action's axis can build or break its
	/// baseline: pitch provenance never disturbs a turn, and blink/open-mouth ignore
	/// pose altogether.
	func prepareBaseline(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?) {
		guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
			mouth.map({ $0.isFinite && $0 >= 0 }) ?? true else { reset(); return }
		isComplete = false
		movementSamples = 0
		observedMovement = false
		switch action {
		case .turnLeft, .turnRight:
			guard yaw.isFinite, yawSource != .unavailable else { invalidatePoseEvidence(); return }
			preparePoseBaseline(yaw, source: yawSource, axis: .yaw)
		case .nod:
			guard pitch.isFinite, pitchSource != .unavailable else { invalidatePoseEvidence(); return }
			preparePoseBaseline(pitch, source: pitchSource, axis: .pitch)
		case .blink:
			baselineSamples = eyes.map { $0 > Self.eyeOpen } == true ? min(3, baselineSamples + 1) : 0
			eyesWereOpen = isBaselineReady
		case .openMouth:
			baselineSamples = mouth.map { $0 < Self.mouthClosed } == true ? min(3, baselineSamples + 1) : 0
			mouthWasClosed = isBaselineReady
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
		consume(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
			yawSource: sample.pose.yawSource, pitchSource: sample.pose.pitchSource,
			eyes: Self.eyeOpenness(sample.landmarks), mouth: Self.mouthOpenness(sample.landmarks))
	}

	@discardableResult
	func consume(yaw: Double, pitch: Double, eyes: Float?, mouth: Float?) -> ConsumeResult {
		consume(yaw: yaw, pitch: pitch, yawSource: .vision, pitchSource: .vision,
			eyes: eyes, mouth: mouth)
	}

	/// Source-aware consumption. A sample from a different estimator than the baseline —
	/// or with the action's axis unavailable or nonfinite — discards the baseline and
	/// partial movement and reports `poseSourceInvalidated`, so the unlock loop can drop
	/// its wider proof instead of completing across estimators. The sample itself starts
	/// the fresh baseline where possible. Unrelated axes — and, for blink/open-mouth,
	/// all pose input — never invalidate.
	@discardableResult
	func consume(yaw: Double, pitch: Double, yawSource: FacePose.AxisSource, pitchSource: FacePose.AxisSource, eyes: Float?, mouth: Float?) -> ConsumeResult {
		guard !isComplete else { return ConsumeResult() }
		switch action {
		// In the mirrored camera preview, leftward turns increase Vision yaw.
		// Verified against the September 15 recording; see CHALLENGE-INVESTIGATION.md.
		case .turnLeft:
			return consumeDirectional(yaw, source: yawSource, axis: .yaw,
				threshold: Self.turnDelta, direction: 1, eyes: eyes, mouth: mouth)
		case .turnRight:
			return consumeDirectional(yaw, source: yawSource, axis: .yaw,
				threshold: Self.turnDelta, direction: -1, eyes: eyes, mouth: mouth)
		case .nod:
			return consumeDirectional(pitch, source: pitchSource, axis: .pitch,
				threshold: Self.nodDelta, direction: 1, eyes: eyes, mouth: mouth)
		case .blink:
			guard eyes.map({ $0.isFinite && $0 >= 0 }) ?? true,
				mouth.map({ $0.isFinite && $0 >= 0 }) ?? true,
				let eyes else { reset(); return ConsumeResult() }
			if !eyesWereOpen {
				baselineSamples = eyes > Self.eyeOpen ? baselineSamples + 1 : 0
				eyesWereOpen = baselineSamples >= 3
			} else if eyes < Self.eyeShut {
				observedMovement = true
			} else if observedMovement && eyes > Self.eyeOpen {
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
