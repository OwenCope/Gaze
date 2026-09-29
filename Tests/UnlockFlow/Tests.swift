import Foundation
import Vision

struct FaceSample {
	let pose: FacePose
	let landmarks: VNFaceLandmarks2D
}

@main @MainActor
enum UnlockFlowTests {
	static var checks = 0
	static func check(_ passed: @autoclosure () -> Bool, _ name: String) {
		precondition(passed(), name)
		checks += 1
	}

	static func main() {
		let now = ContinuousClock.now
		var gate = UnlockChallengeGate()
		check(!gate.reset(), "idle reset does not change displayed scanning state")
		gate.present(at: now, frameID: 1)
		check(gate.reset(), "losing a presented challenge withdraws movement guidance")
		check(!gate.isPresented && !gate.isVerified, "guidance reset clears presentation and approval")
		check(!gate.reset(), "repeated invalid frames do not retrigger guidance transitions")
		gate.completeAction()
		check(!gate.isVerified && gate.completedActions == 0, "unprompted completion denied")
		check(!gate.admits(frameID: 1, capturedAt: now, now: now), "unprompted sample denied")
		gate.present(at: now, frameID: 1)
		for milliseconds in [-10, 0, 100, 349] {
			let time = now.advanced(by: .milliseconds(milliseconds))
			check(!gate.admits(frameID: 2, capturedAt: time, now: time), "pre-prompt and presentation frames denied")
		}
		let response = now.advanced(by: .milliseconds(400))
		check(!gate.admits(frameID: 1, capturedAt: response, now: response), "presentation frame cannot be reused")
		check(!gate.admits(frameID: 2, capturedAt: response, now: now), "future capture denied")
		check(!gate.admits(frameID: 2, capturedAt: response, now: response.advanced(by: .seconds(1))), "stale capture denied")
		check(gate.admits(frameID: 2, capturedAt: response, now: response), "fresh post-prompt capture accepted")
		check(!gate.admits(frameID: 2, capturedAt: response, now: response), "reused evidence denied")
		check(!gate.admits(frameID: 3, capturedAt: response, now: response), "duplicate timestamp denied")
		gate.completeAction()
		check(gate.completedActions == 1 && !gate.isVerified, "one movement cannot authorize submission")
		var interrupted = gate
		check(interrupted.reset(), "loss between movements withdraws the previous animation")
		check(interrupted.completedActions == 0 && !interrupted.isPresented,
			"interrupted sequence requires two new prompted movements")
		check(!interrupted.admits(frameID: 3, capturedAt: response, now: response),
			"withdrawn guidance cannot accept the old response")
		gate.completeAction()
		check(gate.completedActions == 1, "completed movement cannot count twice")
		gate.present(at: response, frameID: 3)
		let second = response.advanced(by: .milliseconds(500))
		check(gate.admits(frameID: 4, capturedAt: second, now: second), "second prompt needs new evidence")
		gate.completeAction()
		check(gate.isVerified, "two distinct prompted responses complete")
		check(gate.reset(), "reset after verification withdraws completed guidance")
		check(!gate.isVerified && gate.completedActions == 0, "identity loss clears all evidence")
		gate.present(at: now, frameID: 1)
		check(gate.expired(at: now.advanced(by: .seconds(8))), "challenge timeout uses monotonic time")
		check(gate.expired(at: now.advanced(by: .seconds(-1))), "clock reversal fails closed")
		let late = now.advanced(by: .seconds(8))
		check(!gate.admits(frameID: 5, capturedAt: late, now: late), "expired challenge cannot accept response")
		gate.completeAction()
		check(!gate.isVerified, "expired challenge cannot authorize")

		let baseline = LockScreenInputSnapshot(keys: 100, leftClicks: 3, rightClicks: 4)
		for changed in [LockScreenInputSnapshot(keys: 101, leftClicks: 3, rightClicks: 4),
			LockScreenInputSnapshot(keys: 100, leftClicks: 4, rightClicks: 4),
			LockScreenInputSnapshot(keys: 100, leftClicks: 3, rightClicks: 5),
			LockScreenInputSnapshot(keys: 0, leftClicks: 3, rightClicks: 4)] {
			var input = LockScreenInputGuard(initial: baseline)
			check(input.permits(baseline), "unchanged counters permit evaluation")
			check(!input.permits(changed), "keyboard, click, or counter reset cancels")
			check(!input.permits(baseline), "input cancellation is irreversible")
		}
		for action in LivenessChallenge.Action.allCases where !action.isLook {
			let challenge = LivenessChallenge(action: action)
			let gazeRest: Double? = action.isLook ? 0.0 : nil
			let gazeOut: Double? = action == .lookLeft ? 0.2 : action == .lookRight ? -0.2 : nil
			for _ in 0..<10 { sample(challenge, gaze: gazeRest) }
			check(!challenge.isComplete, "still face never completes \(action)")
			check(!challenge.isReturningToRest && challenge.guidancePrompt == action.prompt,
				"still face shows requested action, not return guidance")
			let yaw: Double = action == .turnLeft ? 0.35 : action == .turnRight ? -0.35 : 0
			let pitch: Double = action == .nod ? 0.22 : 0
			for _ in 0..<(action.isLook ? 3 : 2) {
				sample(challenge, yaw: yaw, pitch: pitch,
					eyes: action == .blink ? 0.10 : 0.3, mouth: action == .openMouth ? 0.4 : 0.1,
					gaze: gazeOut)
			}
			check(!challenge.isComplete, "excursion alone is not a completed \(action)")
			check(challenge.isReturningToRest && challenge.guidanceSymbol == "viewfinder",
				"observed movement asks for return without authorizing")
			check(challenge.guidanceHint.x == 0
				&& challenge.guidanceHint.y == 0 && !challenge.guidanceHint.pulses,
				"return guidance stops requesting further movement")
			sample(challenge, gaze: gazeRest)
			check(challenge.isComplete, "baseline, movement, return completes \(action)")
			check(!challenge.isReturningToRest, "completion ends return guidance")
			challenge.reset()
			check(!challenge.isComplete, "reset removes completed \(action)")
			check(!challenge.isReturningToRest && challenge.guidancePrompt == action.prompt,
				"reset restores original guidance")
			for _ in 0..<5 { sample(challenge, gaze: gazeRest) }
			challenge.consume(yaw: action == .turnLeft || action == .turnRight || action.isLook ? .nan : 0,
				pitch: action == .nod ? .nan : 0,
				eyes: action == .blink ? .nan : 0.3, mouth: action == .openMouth ? .nan : 0.1,
				gaze: action.isLook ? .nan : nil)
			for _ in 0..<2 { sample(challenge, yaw: yaw, pitch: pitch, eyes: 0.10, mouth: 0.4, gaze: gazeOut) }
			sample(challenge, gaze: gazeRest)
			check(!challenge.isComplete, "invalid numeric evidence clears baseline")
			let previous = challenge.action
			challenge.next()
			check(challenge.action != previous && !challenge.isComplete, "next action differs and clears evidence")
		}
		for action in [LivenessChallenge.Action.turnLeft, .turnRight, .nod] {
			let challenge = LivenessChallenge(action: action)
			for _ in 0..<4 { sample(challenge) }
			for _ in 0..<4 {
				sample(challenge, yaw: action == .turnLeft ? -0.4 : 0.4, pitch: -0.3)
			}
			sample(challenge)
			check(!challenge.isComplete, "wrong direction denied")
			check(!challenge.isReturningToRest, "wrong direction never shows return guidance")
		}
		for action in LivenessChallenge.Action.allCases where !action.isLook {
			let challenge = LivenessChallenge(action: action)
			let gazeRest: Double? = action.isLook ? 0.0 : nil
			let gazeOut: Double? = action == .lookLeft ? 0.2 : action == .lookRight ? -0.2 : nil
			for _ in 0..<2 { challenge.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1, gaze: gazeRest) }
			check(!challenge.isBaselineReady, "two baseline frames cannot start \(action)")
			challenge.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1, gaze: gazeRest)
			check(challenge.isBaselineReady && !challenge.isComplete, "baseline prepares but never completes \(action)")
			var prompt = UnlockChallengeGate()
			prompt.present(at: now, frameID: 100)
			check(!prompt.admits(frameID: 101, capturedAt: now.advanced(by: .milliseconds(100)),
				now: now.advanced(by: .milliseconds(100))), "prepared baseline does not bypass presentation delay")
			let yaw: Double = action == .turnLeft ? 0.35 : action == .turnRight ? -0.35 : 0
			let pitch: Double = action == .nod ? 0.22 : 0
			for index in 0..<(action.isLook ? 3 : 2) {
				let captured = now.advanced(by: .milliseconds(400 + 100 * index))
				check(prompt.admits(frameID: UInt64(102 + index), capturedAt: captured, now: captured),
					"fresh movement admitted after prepared baseline")
				sample(challenge, yaw: yaw, pitch: pitch,
					eyes: action == .blink ? 0.1 : 0.3, mouth: action == .openMouth ? 0.4 : 0.1,
					gaze: gazeOut)
			}
			check(!challenge.isComplete, "movement still requires return for \(action)")
			sample(challenge, gaze: gazeRest)
			check(challenge.isComplete, "first prompted excursion uses pre-prompt neutral baseline for \(action)")
			prompt.completeAction()
			check(!prompt.isVerified && prompt.completedActions == 1, "prepared baseline does not remove second action")
			challenge.reset()
			check(!challenge.isBaselineReady && !challenge.isComplete, "identity loss removes prepared baseline")
			for _ in 0..<3 { challenge.prepareBaseline(yaw: yaw, pitch: pitch, eyes: 0.1, mouth: 0.4) }
			for _ in 0..<3 { challenge.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1, gaze: gazeRest) }
			check(!challenge.isComplete, "pre-prompt movement cannot complete \(action)")
			challenge.prepareBaseline(yaw: action == .turnLeft || action == .turnRight || action.isLook ? .nan : 0,
				pitch: action == .nod ? .nan : 0,
				eyes: action == .blink ? .nan : 0.3, mouth: action == .openMouth ? .nan : 0.1,
				gaze: action.isLook ? .nan : nil)
			check(!challenge.isBaselineReady, "invalid preparatory evidence clears baseline")
		}
		// Follow the light: eyes scored against the light's path, one 1.3 s pass at a time.
		check(LivenessChallenge.lookTargetPosition(elapsed: 0) == 0, "light starts at the centre")
		check(LivenessChallenge.lookTargetPosition(elapsed: 0.65) == 1, "light holds at the edge mid-pass")
		check(LivenessChallenge.lookTargetPosition(elapsed: 1.25) == 0, "light is back at the centre")
		func pursue(_ action: LivenessChallenge.Action, seconds: Double = 2.1, angle: Double? = nil,
			gaze: (Double) -> Double?, gazeY: (Double) -> Double? = { _ in nil },
			yaw: (Double) -> Double = { _ in 0 }) -> LivenessChallenge {
			let challenge = LivenessChallenge(action: action)
			var now = 100.0
			challenge.clock = { now }
			// lookRight heads for screen right (0), lookLeft for screen left (pi), unless told.
			challenge.lookAngleOverride = angle ?? (action == .lookRight ? 0 : .pi)
			for _ in 0..<3 { challenge.consume(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1, gaze: 0.0, gazeY: 0.0) }
			let start = now
			while now - start < seconds, !challenge.isComplete {
				now += 1.0 / 30
				let t = now - start
				challenge.consume(yaw: yaw(t), pitch: 0, eyes: 0.3, mouth: 0.1, gaze: gaze(t), gazeY: gazeY(t))
			}
			return challenge
		}
		// lookRight moves the pupils toward image -x, lookLeft toward +x.
		let followed = pursue(.lookRight) { t in -0.1 * LivenessChallenge.lookTargetPosition(elapsed: t) + 0.005 * sin(t * 40) }
		check(followed.guidancePrompt == "Follow the light" || followed.isComplete, "look action prompts to follow the light")
		check(followed.isComplete, "eyes following the light for a pass complete lookRight")
		let followedLeft = pursue(.lookLeft) { t in 0.1 * LivenessChallenge.lookTargetPosition(elapsed: t) }
		check(followedLeft.isComplete, "eyes following the light complete lookLeft")
		let still = pursue(.lookRight) { _ in 0 }
		check(!still.isComplete, "eyes that never move do not pass")
		let wrongWay = pursue(.lookRight) { t in 0.1 * LivenessChallenge.lookTargetPosition(elapsed: t) }
		check(!wrongWay.isComplete, "eyes moving the opposite way do not pass")
		let turned = pursue(.lookRight, gaze: { t in -0.1 * LivenessChallenge.lookTargetPosition(elapsed: t) },
			yaw: { t in t > 0.2 ? 0.26 : 0 })
		check(!turned.isComplete, "turning the head to follow the light does not pass")
		let tooSmall = pursue(.lookRight) { t in -0.02 * LivenessChallenge.lookTargetPosition(elapsed: t) }
		check(!tooSmall.isComplete, "an eye movement too small to see does not pass")
		let r = { (t: Double) in LivenessChallenge.lookTargetPosition(elapsed: t) }
		let up = pursue(.lookRight, angle: .pi / 2, gaze: { _ in 0 }, gazeY: { t in 0.06 * r(t) })
		check(up.isComplete, "eyes following the light upward pass")
		let diagonal = pursue(.lookRight, angle: .pi * 5 / 4,
			gaze: { t in 0.07 * r(t) }, gazeY: { t in -0.035 * r(t) })
		check(diagonal.isComplete, "eyes following the light down and to the left pass")
		let sideways = pursue(.lookRight, angle: .pi / 2, gaze: { t in -0.1 * r(t) }, gazeY: { _ in 0 })
		check(!sideways.isComplete, "moving the eyes sideways when the light goes up does not pass")
		let noVertical = pursue(.lookRight, angle: .pi / 2, gaze: { _ in 0 })
		check(!noVertical.isComplete, "an upward pass needs a vertical reading")
		let a1 = LivenessChallenge.lookAngle(cycle: 0, seed: 42), a2 = LivenessChallenge.lookAngle(cycle: 1, seed: 42)
		check(a1 != a2 && (0..<(2 * Double.pi)).contains(a1), "each pass gets its own direction")
		check(LivenessChallenge.lookAngle(cycle: 3, seed: 7) == LivenessChallenge.lookAngle(cycle: 3, seed: 7),
			"the light and the scoring agree on a pass's direction")
		let untracked = LivenessChallenge(action: .lookLeft)
		for _ in 0..<14 { untracked.consume(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1) }
		check(untracked.action == .lookLeft, "brief gaze dropouts keep the look action")
		untracked.consume(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1)
		check(!untracked.action.isLook, "untracked eyes fall back to a non-look action")
		let blink = LivenessChallenge(action: .blink)
		for action in [LivenessChallenge.Action.turnLeft, .turnRight, .nod] {
			let measured = LivenessChallenge(action: action)
			check(measured.poseMeasurement(yaw: 0.2, pitch: -0.1) == nil, "unprepared pose is not reported as a zero offset")
			for _ in 0..<3 { measured.prepareBaseline(yaw: 0.2, pitch: -0.1, eyes: 0.3, mouth: 0.1) }
			let yaw = action == .turnLeft ? 0.55 : action == .turnRight ? -0.15 : 0.2
			let pitch = action == .nod ? 0.12 : -0.1
			let measurement = measured.poseMeasurement(yaw: yaw, pitch: pitch)!
			let expectedOffset = action == .turnLeft ? 0.35 : action == .turnRight ? -0.35 : 0.22
			check(abs(measurement.offset - expectedOffset) < 0.000001, "diagnostics report movement relative to the actual baseline")
			check(!measured.isReturningToRest && !measured.isComplete, "reading diagnostics cannot admit movement evidence")
			check(measured.poseMeasurement(yaw: .nan, pitch: pitch) == nil, "invalid pose is not displayed as a real movement")
			for _ in 0..<2 { sample(measured, yaw: yaw, pitch: pitch) }
			check(measured.isReturningToRest && !measured.isComplete, "diagnostic reads do not change the required excursion")
			let returned = measured.poseMeasurement(yaw: 0.2, pitch: -0.1)!
			check(returned.offset == 0 && returned.returnTolerance == abs(returned.target) / 3,
				"return diagnostics use the same baseline and tolerance as the movement check")
			sample(measured, yaw: 0.2, pitch: -0.1)
			check(measured.isComplete, "return to a nonzero starting pose still completes normally")
			measured.reset()
			check(measured.poseMeasurement(yaw: yaw, pitch: pitch) == nil, "reset removes diagnostic baseline")
		}
		for _ in 0..<4 { sample(blink, eyes: 0.1) }
		sample(blink)
		check(!blink.isComplete, "arriving with closed eyes is not a blink response")
		print("PASS: \(checks) unlock-flow checks; synthetic measurements only, no camera or credential access, no input posted.")
	}

	static func sample(_ challenge: LivenessChallenge, yaw: Double = 0, pitch: Double = 0,
		eyes: Float = 0.3, mouth: Float = 0.1, gaze: Double? = nil) {
		challenge.consume(yaw: yaw, pitch: pitch, eyes: eyes, mouth: mouth, gaze: gaze)
	}
}
