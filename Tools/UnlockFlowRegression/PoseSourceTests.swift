import Foundation
import Vision

// Focused pose-source regression: production FacePose provenance (Vision /
// landmarkEstimate / unavailable, selected per axis) against the production
// LivenessChallenge. Synthetic scalar sequences only — no camera, enrollment,
// credentials, or lock-screen replay.
//
// Production FaceSample (the AVFoundation stack in Sources/Camera) is not compiled
// into this focused binary, so this stub exists only because LivenessChallenge's
// FaceSample overloads need the type to resolve. Every assertion below drives the
// scalar source-aware overloads and FacePose.resolved, which is exactly what
// CameraController feeds those overloads in production.

struct FaceSample {
	let pose: FacePose
	let landmarks: VNFaceLandmarks2D
}

@main @MainActor
enum PoseSourceTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func prepare(_ challenge: LivenessChallenge, yaw: Double = 0, pitch: Double = 0,
		yawSource: FacePose.AxisSource = .vision, pitchSource: FacePose.AxisSource = .vision,
		eyes: Float? = 0.3, mouth: Float? = 0.1) {
		challenge.prepareBaseline(yaw: yaw, pitch: pitch, yawSource: yawSource,
			pitchSource: pitchSource, eyes: eyes, mouth: mouth)
	}

	@discardableResult
	static func feed(_ challenge: LivenessChallenge, yaw: Double = 0, pitch: Double = 0,
		yawSource: FacePose.AxisSource = .vision, pitchSource: FacePose.AxisSource = .vision,
		eyes: Float? = 0.3, mouth: Float? = 0.1) -> LivenessChallenge.ConsumeResult {
		challenge.consume(yaw: yaw, pitch: pitch, yawSource: yawSource,
			pitchSource: pitchSource, eyes: eyes, mouth: mouth)
	}

	static func main() {
		check(UnlockChallengeGate.requiredActions == 2, "two prompted movements stay required")
		resolvedSelection()
		missingLandmarkMeasurements()
		unchangedSourceSuccess()
		sourceTransitionInvalidates()
		unavailableData()
		unrelatedAxisNoReset()
		blinkAndMouthPoseIndependent()
		nonfiniteInput()
		resetReacquisition()
		diagnosticsRespectSource()
		directionMapping()
		print("PASS: \(checks) pose-source checks; synthetic scalar sequences only, no camera, enrollment, credentials or observed lock-screen replay.")
	}

	static func missingLandmarkMeasurements() {
		let left = CGPoint(x: 0.3, y: 0.7)
		let right = CGPoint(x: 0.7, y: 0.7)
		let nose = [CGPoint(x: 0.5, y: 0.48)]
		for (l, r) in [(nil, nil), (left, nil), (nil, right), (left, left),
			(CGPoint(x: .nan, y: 0.7), right)] as [(CGPoint?, CGPoint?)] {
			let pose = FacePose.estimate(leftPupil: l, rightPupil: r, nose: nose)
			check(pose.yawSource == .unavailable && pose.pitchSource == .unavailable && pose.rollSource == .unavailable,
				"missing or degenerate eye geometry cannot become a measured axis")
			check(pose.yaw.isNaN && pose.pitch.isNaN && pose.roll.isNaN,
				"unmeasurable eye geometry never masquerades as a frontal pose")
		}
		for missingNose in [nil, []] as [[CGPoint]?] {
			let pose = FacePose.estimate(leftPupil: left, rightPupil: right, nose: missingNose)
			check(pose.yaw.isNaN && pose.pitch.isNaN && pose.roll == 0,
				"missing nose preserves only the measured eye-line roll")
			check(pose.yawSource == .unavailable && pose.pitchSource == .unavailable && pose.rollSource == .landmarkEstimate,
				"missing nose is reported per axis")
		}
		let measured = FacePose.estimate(leftPupil: left, rightPupil: right, nose: nose)
		check(measured.yawSource == .landmarkEstimate && measured.pitchSource == .landmarkEstimate,
			"valid landmark geometry retains estimator provenance")
		check(abs(measured.yaw) < 0.000001 && abs(measured.pitch) < 0.000001,
			"the pitch offset cancels normal nose displacement; it is not a fixed frontal pitch of 0.88")
	}

	// FacePose.resolved picks per axis: Vision where present, the landmark estimate
	// where that axis was actually estimated, NaN/unavailable otherwise — never a
	// stand-in zero, and never one estimator substituted for a failed other one.
	static func resolvedSelection() {
		let estimate = FacePose(yaw: 0.22, pitch: 0.10, roll: 0.01,
			yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate, rollSource: .landmarkEstimate)
		let both = FacePose.resolved(visionYaw: 0.05, visionPitch: -0.02, visionRoll: 0.0, estimate: estimate)
		check(both.yaw == 0.05 && both.yawSource == .vision, "vision yaw wins where present")
		check(both.pitch == -0.02 && both.pitchSource == .vision, "vision pitch wins where present")
		check(both.roll == 0.0 && both.rollSource == .vision, "vision roll wins where present")
		let mixed = FacePose.resolved(visionYaw: 0.05, visionPitch: nil, visionRoll: nil, estimate: estimate)
		check(mixed.yaw == 0.05 && mixed.yawSource == .vision, "measured yaw survives a missing pitch")
		check(mixed.pitch == 0.10 && mixed.pitchSource == .landmarkEstimate, "pitch falls back alone")
		check(mixed.roll == 0.01 && mixed.rollSource == .landmarkEstimate, "roll falls back alone")
		let missing = FacePose.resolved(visionYaw: nil, visionPitch: 0.03, visionRoll: nil,
			estimate: FacePose(yaw: 0, pitch: 0, roll: 0,
				yawSource: .unavailable, pitchSource: .unavailable, rollSource: .unavailable))
		check(!missing.yaw.isFinite && missing.yawSource == .unavailable, "missing yaw is unavailable")
		check(missing.yaw != 0, "missing yaw never masquerades as a frontal zero")
		check(missing.pitch == 0.03 && missing.pitchSource == .vision, "measured pitch survives a missing yaw")
		check(!missing.roll.isFinite && missing.rollSource == .unavailable, "missing roll is unavailable")
		let badVision = FacePose.resolved(visionYaw: .nan, visionPitch: nil, visionRoll: nil, estimate: estimate)
		check(!badVision.yaw.isFinite && badVision.yawSource == .vision,
			"nonfinite vision yaw stays vision, not a silent fallback")
		check(badVision.pitchSource == .landmarkEstimate, "landmark pitch still selected alongside")
	}

	// One estimator end to end still does exactly what it always did: baseline of
	// three, two excursion samples, return inside threshold/3. Thresholds, direction
	// mapping and return wording are unchanged.
	static func unchangedSourceSuccess() {
		let left = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(left, yaw: 0.0) }
		check(left.isBaselineReady, "vision turn baseline prepares")
		for _ in 0..<2 { feed(left, yaw: 0.35) }
		check(left.isReturningToRest && !left.isComplete, "vision excursion observes without completing")
		check(left.guidancePrompt == "Return to your starting position", "return wording preserved")
		check(abs(left.poseMeasurement(yaw: 0.35, pitch: 0, yawSource: .vision, pitchSource: .vision)!.returnTolerance - 0.10) < 0.000001,
			"turn return window stays 0.10 rad")
		let done = feed(left, yaw: 0.0)
		check(left.isComplete && !done.poseSourceInvalidated, "unchanged-source return completes with no invalidation")
		let right = LivenessChallenge(action: .turnRight)
		for _ in 0..<3 { prepare(right, yaw: 0.0, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate) }
		for _ in 0..<2 { feed(right, yaw: -0.35, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate) }
		check(right.isReturningToRest, "single-source landmark excursion observes")
		let rightDone = feed(right, yaw: 0.0, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate)
		check(right.isComplete && !rightDone.poseSourceInvalidated, "single-source landmark turn completes")
		let nod = LivenessChallenge(action: .nod)
		for _ in 0..<3 { prepare(nod, yaw: 0, pitch: 0.0) }
		for _ in 0..<2 { feed(nod, yaw: 0, pitch: 0.22) }
		check(nod.isReturningToRest, "nod excursion observes")
		check(abs(nod.poseMeasurement(yaw: 0, pitch: 0.22, yawSource: .vision, pitchSource: .vision)!.returnTolerance - 0.06) < 0.000001,
			"nod return window stays 0.06 rad")
		feed(nod, yaw: 0, pitch: 0.0)
		check(nod.isComplete, "nod return completes")
	}

	// Switching estimators mid-action discards the baseline and partial movement and
	// says so. No baseline, excursion or return is ever mixed across sources.
	static func sourceTransitionInvalidates() {
		let challenge = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
		check(challenge.isBaselineReady, "vision baseline ready before the switch")
		let first = feed(challenge, yaw: 0.35)
		check(!first.poseSourceInvalidated && !challenge.isReturningToRest, "one excursion sample is not yet movement")
		let switched = feed(challenge, yaw: 0.35, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate)
		check(switched.poseSourceInvalidated, "source switch reports invalidation")
		check(!challenge.isBaselineReady && !challenge.isReturningToRest && !challenge.isComplete,
			"switch discards baseline and partial movement")
		check(challenge.poseMeasurement(yaw: 0.35, pitch: 0, yawSource: .vision, pitchSource: .vision) == nil,
			"old-source diagnostics no longer resolve")
		let flapped = feed(challenge, yaw: 0.0)
		check(flapped.poseSourceInvalidated && !challenge.isBaselineReady, "flapping back invalidates again")
		for _ in 0..<2 { feed(challenge, yaw: 0.0) }
		check(challenge.isBaselineReady, "stable source reacquires a baseline")
		for _ in 0..<2 { feed(challenge, yaw: 0.35) }
		check(challenge.isReturningToRest, "movement on the reacquired source observes")
		feed(challenge, yaw: 0.0)
		check(challenge.isComplete, "reacquired baseline plus excursion plus return completes")
		let returning = LivenessChallenge(action: .turnRight)
		for _ in 0..<3 { prepare(returning, yaw: 0.0) }
		for _ in 0..<2 { feed(returning, yaw: -0.35) }
		check(returning.isReturningToRest, "right excursion observes before the switch")
		let cut = feed(returning, yaw: -0.35, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate)
		check(cut.poseSourceInvalidated && !returning.isReturningToRest && !returning.isComplete,
			"source switch during return-to-start withdraws the observed movement")
	}

	// An unavailable action axis invalidates like a switch; an unavailable unrelated
	// axis is ignored, including NaN values riding on it.
	static func unavailableData() {
		let challenge = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
		for _ in 0..<2 { feed(challenge, yaw: 0.35) }
		check(challenge.isReturningToRest, "excursion observed before the dropout")
		let dropped = feed(challenge, yaw: 0.35, yawSource: .unavailable, pitchSource: .vision)
		check(dropped.poseSourceInvalidated, "unavailable action axis reports invalidation")
		check(!challenge.isBaselineReady && !challenge.isReturningToRest,
			"unavailable action axis discards baseline and observed movement")
		let steady = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(steady, yaw: 0.0) }
		let pitchGone = feed(steady, yaw: 0.0, pitch: .nan, pitchSource: .unavailable)
		check(!pitchGone.poseSourceInvalidated && steady.isBaselineReady,
			"unavailable pitch does not disturb a turn baseline")
		for _ in 0..<2 { feed(steady, yaw: 0.35, pitch: .nan, pitchSource: .unavailable) }
		check(steady.isReturningToRest, "turn observes while pitch is unavailable")
		feed(steady, yaw: 0.0, pitch: .nan, pitchSource: .unavailable)
		check(steady.isComplete, "turn completes while pitch is unavailable")
		let nod = LivenessChallenge(action: .nod)
		for _ in 0..<3 { prepare(nod, yaw: 0, pitch: 0.0) }
		let nodDropped = feed(nod, yaw: 0, pitch: 0.22, pitchSource: .unavailable)
		check(nodDropped.poseSourceInvalidated && !nod.isBaselineReady,
			"unavailable pitch invalidates a nod baseline")
	}

	// Pitch provenance flapping never resets a turn; yaw flapping never resets a nod.
	static func unrelatedAxisNoReset() {
		let turn = LivenessChallenge(action: .turnLeft)
		prepare(turn, yaw: 0.0, pitch: 0.0, pitchSource: .vision)
		prepare(turn, yaw: 0.0, pitch: 0.05, pitchSource: .landmarkEstimate)
		prepare(turn, yaw: 0.0, pitch: .nan, pitchSource: .unavailable)
		check(turn.isBaselineReady, "pitch provenance flapping does not reset a turn baseline")
		let moved = feed(turn, yaw: 0.35, pitch: 0.2, pitchSource: .landmarkEstimate)
		check(!moved.poseSourceInvalidated, "pitch switch alongside a real excursion is not an invalidation")
		feed(turn, yaw: 0.35, pitch: .nan, pitchSource: .unavailable)
		check(turn.isReturningToRest, "turn observes despite pitch flapping")
		feed(turn, yaw: 0.0)
		check(turn.isComplete, "turn completes despite pitch flapping")
		let nod = LivenessChallenge(action: .nod)
		prepare(nod, yaw: 0.0, pitch: 0.0)
		prepare(nod, yaw: 0.4, pitch: 0.0, yawSource: .landmarkEstimate)
		prepare(nod, yaw: .nan, pitch: 0.0, yawSource: .unavailable)
		check(nod.isBaselineReady, "yaw flapping does not reset a nod baseline")
		for _ in 0..<2 { feed(nod, yaw: 0.3, pitch: 0.22, yawSource: .landmarkEstimate) }
		check(nod.isReturningToRest, "nod observes despite yaw flapping")
		feed(nod, yaw: .nan, pitch: 0.0, yawSource: .unavailable)
		check(nod.isComplete, "nod completes despite yaw flapping")
	}

	// Blink and open-mouth depend on eyes/mouth only: pose garbage, flapping and
	// unavailability never touch them, and they never report source invalidation.
	static func blinkAndMouthPoseIndependent() {
		let blink = LivenessChallenge(action: .blink)
		for _ in 0..<3 {
			prepare(blink, yaw: .nan, pitch: .nan,
				yawSource: .unavailable, pitchSource: .unavailable, eyes: 0.3)
		}
		check(blink.isBaselineReady, "blink baseline needs open eyes, not pose")
		let shut = feed(blink, yaw: 0.5, pitch: -0.4,
			yawSource: .landmarkEstimate, pitchSource: .vision, eyes: 0.10)
		check(!shut.poseSourceInvalidated && blink.isReturningToRest, "shut eyes observe despite pose change")
		feed(blink, yaw: .nan, pitch: .nan,
			yawSource: .unavailable, pitchSource: .unavailable, eyes: 0.10)
		check(blink.isReturningToRest, "continued shut eyes hold despite pose garbage")
		let opened = feed(blink, yaw: 0.9, pitch: 0.9, yawSource: .landmarkEstimate, eyes: 0.3)
		check(blink.isComplete && !opened.poseSourceInvalidated, "blink completes with no pose dependency")
		let mouth = LivenessChallenge(action: .openMouth)
		for _ in 0..<3 {
			prepare(mouth, yaw: .nan, pitch: .nan,
				yawSource: .unavailable, pitchSource: .unavailable, mouth: 0.1)
		}
		check(mouth.isBaselineReady, "mouth baseline needs a closed mouth, not pose")
		feed(mouth, yaw: 0.5, pitch: 0.5, yawSource: .landmarkEstimate, mouth: 0.4)
		feed(mouth, yaw: .nan, pitch: .nan, yawSource: .unavailable, pitchSource: .unavailable, mouth: 0.4)
		check(mouth.isReturningToRest, "open mouth observes despite pose garbage")
		let relaxed = feed(mouth, yaw: -0.7, pitch: 0.2, yawSource: .landmarkEstimate, mouth: 0.1)
		check(mouth.isComplete && !relaxed.poseSourceInvalidated, "mouth completes with no pose dependency")
		let missing = LivenessChallenge(action: .blink)
		for _ in 0..<3 { prepare(missing, eyes: 0.3) }
		check(missing.isBaselineReady, "blink baseline prepares")
		feed(missing, eyes: nil)
		check(!missing.isBaselineReady, "missing eye landmarks still clear a blink baseline")
	}

	// Nonfinite values on the action's axis invalidate; on any other axis they are
	// ignored. Legacy scalar overloads keep behaving as one consistent source.
	static func nonfiniteInput() {
		let turn = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(turn, yaw: 0.0) }
		let bad = feed(turn, yaw: .nan)
		check(bad.poseSourceInvalidated && !turn.isBaselineReady, "NaN yaw invalidates a turn baseline")
		feed(turn, yaw: .infinity)
		check(!turn.isBaselineReady, "infinite yaw cannot build a baseline")
		for _ in 0..<3 { prepare(turn, yaw: .nan) }
		check(!turn.isBaselineReady, "NaN baselines never prepare")
		let steady = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(steady, yaw: 0.0, pitch: .nan) }
		check(steady.isBaselineReady, "NaN pitch does not block a turn baseline")
		let legacy = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { legacy.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1) }
		legacy.consume(yaw: 0.35, pitch: 0, eyes: 0.3, mouth: 0.1)
		legacy.consume(yaw: 0.35, pitch: 0, eyes: 0.3, mouth: 0.1)
		check(legacy.isReturningToRest, "legacy overloads keep working as one consistent source")
	}

	// After any invalidation, reset clears the source-tracked evidence and a new
	// source can reacquire from scratch; next() carries no proof to the new action.
	static func resetReacquisition() {
		let challenge = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
		feed(challenge, yaw: 0.35, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate)
		check(!challenge.isBaselineReady, "switch clears the baseline")
		challenge.reset()
		check(!challenge.isBaselineReady && !challenge.isReturningToRest && !challenge.isComplete,
			"reset clears source-tracked evidence")
		check(challenge.poseMeasurement(yaw: 0, pitch: 0, yawSource: .vision, pitchSource: .vision) == nil,
			"reset clears the diagnostic baseline and its source")
		for _ in 0..<3 { prepare(challenge, yaw: -0.1, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate) }
		check(challenge.isBaselineReady, "baseline reacquires on the new source after reset")
		for _ in 0..<2 { feed(challenge, yaw: 0.25, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate) }
		check(challenge.isReturningToRest, "movement reacquires on the new source")
		feed(challenge, yaw: -0.1, yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate)
		check(challenge.isComplete, "return on the reacquired source completes")
		let previous = challenge.action
		challenge.next()
		check(challenge.action != previous && !challenge.isComplete && !challenge.isBaselineReady,
			"next action differs and carries no pose proof")
	}

	// Diagnostics never report across estimators, and reading them never admits proof.
	static func diagnosticsRespectSource() {
		let challenge = LivenessChallenge(action: .turnLeft)
		check(challenge.poseMeasurement(yaw: 0.2, pitch: 0, yawSource: .vision, pitchSource: .vision) == nil,
			"unprepared pose is not a zero offset")
		for _ in 0..<3 { prepare(challenge, yaw: 0.2) }
		let same = challenge.poseMeasurement(yaw: 0.55, pitch: 0, yawSource: .vision, pitchSource: .vision)!
		check(abs(same.offset - 0.35) < 0.000001, "same-source diagnostics stay relative to the baseline")
		check(challenge.poseMeasurement(yaw: 0.55, pitch: 0,
			yawSource: .landmarkEstimate, pitchSource: .landmarkEstimate) == nil,
			"cross-source excursion is not reported as movement")
		check(challenge.poseMeasurement(yaw: 0.55, pitch: 0,
			yawSource: .unavailable, pitchSource: .vision) == nil,
			"unavailable axis is not reported as movement")
		check(!challenge.isReturningToRest, "diagnostic reads admit no evidence")
		let blink = LivenessChallenge(action: .blink)
		for _ in 0..<3 { prepare(blink, eyes: 0.3) }
		check(blink.poseMeasurement(yaw: 0, pitch: 0, yawSource: .vision, pitchSource: .vision) == nil,
			"blink has no pose diagnostics")
	}

	// Mirrored-preview direction mapping is unchanged: left needs positive yaw
	// excursion, right needs negative.
	static func directionMapping() {
		for (action, bad, good) in [
			(LivenessChallenge.Action.turnLeft, -0.4, 0.4),
			(LivenessChallenge.Action.turnRight, 0.4, -0.4)
		] as [(LivenessChallenge.Action, Double, Double)] {
			let challenge = LivenessChallenge(action: action)
			for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
			for _ in 0..<2 { feed(challenge, yaw: bad) }
			check(!challenge.isReturningToRest && !challenge.isComplete,
				"wrong direction never observes \(action)")
			for _ in 0..<2 { feed(challenge, yaw: good) }
			check(challenge.isReturningToRest, "mirrored-preview direction observes \(action)")
			feed(challenge, yaw: 0.0)
			check(challenge.isComplete, "return completes \(action)")
		}
	}
}
