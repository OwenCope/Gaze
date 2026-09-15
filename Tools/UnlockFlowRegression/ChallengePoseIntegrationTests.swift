import Foundation
import Vision

// Production FaceSample lives in Sources/Camera/CameraController.swift (AVFoundation
// stack) and is not compiled into this focused binary. This stub exposes the members
// production LivenessChallenge touches (pose yaw/pitch, landmarks), mirroring
// Tools/HeadPoseRegression/Tests.swift. All movement assertions below drive the
// production scalar overloads with production FacePose values, so the tested
// thresholds, stability window, excursion counts and return tolerance are the real ones.

struct FaceSample {
	let pose: FacePose
	let landmarks: VNFaceLandmarks2D
}

@main @MainActor
enum ChallengePoseIntegrationTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func prepare(_ challenge: LivenessChallenge, yaw: Double, pitch: Double = 0) {
		let pose = FacePose(yaw: yaw, pitch: pitch, roll: 0)
		challenge.prepareBaseline(yaw: pose.yaw, pitch: pose.pitch, eyes: 0.3, mouth: 0.1)
	}

	static func feed(_ challenge: LivenessChallenge, yaw: Double, pitch: Double = 0) {
		let pose = FacePose(yaw: yaw, pitch: pitch, roll: 0)
		challenge.consume(yaw: pose.yaw, pitch: pose.pitch, eyes: 0.3, mouth: 0.1)
	}

	static func main() {
		check(UnlockChallengeGate.requiredActions == 2, "two prompted movements stay required")
		check(UnlockChallengeGate.presentationDelay == .milliseconds(350), "pin 350ms presentation interval")
		check(UnlockChallengeGate.responseTimeout == .seconds(8), "pin eight-second response timeout")
		nonfrontalReturnToStart()
		retryReacquisition()
		poseSourceSwitch()
		promptAdmissionTiming()
		print("PASS: \(checks) challenge/pose/gate integration checks; synthetic scalar sequences only, no camera, enrollment, credentials or observed lock-screen replay.")
	}

	// TEAM-INVESTIGATION-20260915.md section 1: the challenge is relative to wherever
	// the head started (LivenessChallenge.swift), while return guidance says
	// the starting position. A nonfrontal baseline remains valid; returning to frontal
	// zero is not a substitute for returning to that baseline.
	static func nonfrontalReturnToStart() {
		for (action, base, excursion) in [
			(LivenessChallenge.Action.turnLeft, 0.20, 0.55),
			(LivenessChallenge.Action.turnRight, -0.20, -0.55)
		] as [(LivenessChallenge.Action, Double, Double)] {
			let challenge = LivenessChallenge(action: action)
			for _ in 0..<3 { prepare(challenge, yaw: base) }
			check(challenge.isBaselineReady, "nonfrontal baseline prepares for \(action)")
			let measured = challenge.poseMeasurement(yaw: excursion, pitch: 0)!
			check(abs(measured.offset - (excursion - base)) < 0.000001,
				"diagnostics report the excursion relative to the nonfrontal baseline for \(action)")
			check(abs(measured.returnTolerance - 0.10) < 0.000001,
				"return window stays 0.10 rad for \(action)")
			for _ in 0..<2 { feed(challenge, yaw: excursion) }
			check(challenge.isReturningToRest && !challenge.isComplete,
				"nonfrontal excursion observes movement without completing \(action)")
			check(challenge.guidancePrompt == "Return to your starting position",
				"return guidance names the baseline the detector actually requires")
			feed(challenge, yaw: 0.0)
			check(!challenge.isComplete && challenge.isReturningToRest,
				"frontal return after a nonfrontal start does not complete \(action): offset 0.20 exceeds the 0.10 window")
			feed(challenge, yaw: base)
			check(challenge.isComplete, "return to the starting pose completes \(action)")
		}
	}

	// After LockWatcher.resetMovementGuidance the challenge baseline is cleared and
	// rebuilt from verified frames. The stability window (0.05 rad) re-anchors to
	// wherever the user actually holds still, including a new pose.
	static func retryReacquisition() {
		let challenge = LivenessChallenge(action: .turnLeft)
		for _ in 0..<2 { prepare(challenge, yaw: 0.20) }
		check(!challenge.isBaselineReady, "two baseline frames cannot start a retry")
		for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
		check(challenge.isBaselineReady, "retry baseline re-anchors to the held frontal pose")
		check(challenge.poseMeasurement(yaw: 0.0, pitch: 0)!.offset == 0,
			"reacquired baseline measures zero offset at the held pose")
		for _ in 0..<2 { feed(challenge, yaw: 0.35) }
		check(challenge.isReturningToRest, "movement from the reacquired baseline is observed")
		challenge.reset()
		check(!challenge.isBaselineReady && !challenge.isReturningToRest && !challenge.isComplete,
			"guidance reset clears baseline, excursion and completion together")
		for _ in 0..<3 { prepare(challenge, yaw: -0.15) }
		check(challenge.isBaselineReady, "post-reset baseline can prepare at another held pose")
		check(challenge.poseMeasurement(yaw: -0.15, pitch: 0)!.offset == 0,
			"post-reset diagnostics use the new baseline")
	}

	// TEAM-INVESTIGATION-20260915.md section 3: CameraController selects Vision
	// yaw/pitch/roll per axis and falls back to FacePose.estimate per axis when Vision
	// omits one. FacePose carries yaw/pitch/roll only, so the challenge cannot tell a
	// source transition from a physical turn, and fallback magnitudes are uncalibrated
	// (FacePose.swift documents the sign agreement but not the scale).
	static func poseSourceSwitch() {
		let biased = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(biased, yaw: 0.10) }
		for _ in 0..<2 { feed(biased, yaw: 0.45) }
		check(biased.isReturningToRest, "excursion observed before the return")
		feed(biased, yaw: 0.25)
		check(!biased.isComplete && biased.isReturningToRest,
			"source-biased return (offset 0.15) misses the 0.10 window despite a physical return")
		feed(biased, yaw: 0.10)
		check(biased.isComplete, "unbiased return to the starting pose completes")
		// A hypothetical pitch-source bias can also make the same physical nod
		// look like movement in the opposite direction. The estimator's +0.55
		// term alone is not frontal pitch; measured nose displacement offsets it.
		let nod = LivenessChallenge(action: .nod)
		for _ in 0..<3 { prepare(nod, yaw: 0, pitch: 0.25) }
		check(nod.isBaselineReady, "hypothetically biased nod baseline prepares")
		for _ in 0..<2 { feed(nod, yaw: 0, pitch: 0.20) }
		check(!nod.isReturningToRest,
			"a source-biased baseline can miss a nod on a different measurement scale")
	}

	// UnlockChallengeGate admission shares the clock with LivenessChallenge evidence:
	// frames inside the 350 ms presentation interval are denied before the challenge
	// ever sees them (LockWatcher admits-then-consumes). Fast compliance is invisible
	// by design, which reads as "I turned and nothing happened" without any reset.
	static func promptAdmissionTiming() {
		let start = ContinuousClock.now
		let challenge = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(challenge, yaw: 0.0) }
		var gate = UnlockChallengeGate()
		gate.present(at: start, frameID: 7)
		let early = start.advanced(by: .milliseconds(100))
		check(!gate.admits(frameID: 8, capturedAt: early, now: early),
			"turn begun inside the presentation interval is not admitted")
		for (frameID, milliseconds) in [(UInt64(9), 400), (UInt64(10), 450)] {
			let at = start.advanced(by: .milliseconds(milliseconds))
			check(gate.admits(frameID: frameID, capturedAt: at, now: at),
				"post-interval excursion frame \(frameID) admitted")
			feed(challenge, yaw: 0.35)
		}
		check(challenge.isReturningToRest && !challenge.isComplete,
			"admitted excursion observes movement without completing")
		let returned = start.advanced(by: .milliseconds(800))
		check(gate.admits(frameID: 11, capturedAt: returned, now: returned),
			"return frame admitted")
		feed(challenge, yaw: 0.0)
		check(challenge.isComplete, "admitted excursion plus admitted return completes")
		gate.completeAction()
		check(gate.completedActions == 1 && !gate.isVerified,
			"one admitted movement still requires the second prompted action")
		let hurried = LivenessChallenge(action: .turnLeft)
		for _ in 0..<3 { prepare(hurried, yaw: 0.0) }
		var hurriedGate = UnlockChallengeGate()
		hurriedGate.present(at: start, frameID: 20)
		for (frameID, milliseconds) in [(UInt64(21), 100), (UInt64(22), 150), (UInt64(23), 200)] {
			let at = start.advanced(by: .milliseconds(milliseconds))
			check(!hurriedGate.admits(frameID: frameID, capturedAt: at, now: at),
				"sub-interval frame \(frameID) denied")
		}
		check(!hurried.isReturningToRest && !hurried.isComplete,
			"a full turn-and-return inside the presentation interval leaves no evidence at all")
	}
}
