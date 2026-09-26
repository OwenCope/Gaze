import Foundation
import Vision

// Focused production-gate regression for configurable movement count.
// Synthetic timestamps and scalar pose only — no camera, enrollment,
// credentials, lock-screen replay or input posting.

struct FaceSample {
	let pose: FacePose
	let landmarks: VNFaceLandmarks2D
}

@main @MainActor
enum UnlockChallengeGateCountTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func main() {
		check(UnlockChallengeGate.defaultRequiredActions == 2, "default stays two movements")
		check(UnlockChallengeGate().requiredActions == 2, "default init retains two actions")
		check(UnlockChallengeGate(requiredActions: 1).requiredActions == 1, "one movement is configurable")
		check(UnlockChallengeGate(requiredActions: 2).requiredActions == 2, "two movements stay selectable")
		check(UnlockChallengeGate.presentationDelay == .milliseconds(350), "pin 350ms presentation interval")
		check(UnlockChallengeGate.responseTimeout == .seconds(8), "pin eight-second response timeout")
		invalidValues()
		oneActionCompletion()
		twoActionCompletion()
		noCompletionWithoutEvidence()
		resetPreservesCount()
		timingAndReplay(for: 1)
		timingAndReplay(for: 2)
		turnAndReturnThroughGate(for: 1)
		turnAndReturnThroughGate(for: 2)
		print("PASS: \(checks) challenge-count checks; synthetic timestamps and scalar pose only.")
	}

	static func invalidValues() {
		for value in [0, 3, -1, 99, Int.min, Int.max] {
			check(UnlockChallengeGate(requiredActions: value).requiredActions == 2,
				"invalid count \(value) resolves to two")
			check(!UnlockChallengeGate(requiredActions: value).isVerified,
				"invalid count \(value) starts unverified")
		}
	}

	static func admit(_ gate: inout UnlockChallengeGate, frameID: UInt64,
		capturedAt: ContinuousClock.Instant, now: ContinuousClock.Instant,
		_ description: String) {
		check(gate.admits(frameID: frameID, capturedAt: capturedAt, now: now), description)
	}

	static func oneActionCompletion() {
		let start = ContinuousClock.now
		var gate = UnlockChallengeGate(requiredActions: 1)
		check(!gate.isVerified, "one-action gate starts unverified")
		gate.present(at: start, frameID: 1)
		check(gate.isPresented, "one-action present shows guidance")
		let at = start.advanced(by: .milliseconds(400))
		admit(&gate, frameID: 2, capturedAt: at, now: at, "one-action fresh evidence admitted")
		gate.completeAction()
		check(gate.completedActions == 1 && gate.isVerified, "one admitted movement verifies a one-action gate")
		check(!gate.isPresented, "completion withdraws presentation")
		gate.present(at: at, frameID: 3)
		check(!gate.isPresented && gate.isVerified, "verified gate presents nothing further")
		check(!gate.admits(frameID: 4, capturedAt: at, now: at), "verified gate admits nothing further")
		gate.completeAction()
		check(gate.completedActions == 1 && gate.isVerified, "verified completion cannot count twice")
	}

	static func twoActionCompletion() {
		let start = ContinuousClock.now
		var gate = UnlockChallengeGate(requiredActions: 2)
		gate.present(at: start, frameID: 1)
		let first = start.advanced(by: .milliseconds(400))
		admit(&gate, frameID: 2, capturedAt: first, now: first, "two-action first evidence admitted")
		gate.completeAction()
		check(gate.completedActions == 1 && !gate.isVerified, "one movement cannot verify a two-action gate")
		gate.completeAction()
		check(gate.completedActions == 1, "completed movement cannot count twice")
		gate.present(at: first, frameID: 3)
		let second = first.advanced(by: .milliseconds(500))
		admit(&gate, frameID: 4, capturedAt: second, now: second, "two-action second evidence admitted")
		gate.completeAction()
		check(gate.completedActions == 2 && gate.isVerified, "two distinct prompted responses verify")
		// The default init keeps the same two-action behaviour for existing callers.
		var def = UnlockChallengeGate()
		check(def.requiredActions == 2, "default init requires two")
		def.present(at: start, frameID: 11)
		admit(&def, frameID: 12, capturedAt: first, now: first, "default first evidence admitted")
		def.completeAction()
		check(!def.isVerified, "default still needs the second movement")
		def.present(at: first, frameID: 13)
		admit(&def, frameID: 14, capturedAt: second, now: second, "default second evidence admitted")
		def.completeAction()
		check(def.isVerified, "default verifies after two movements")
	}

	static func noCompletionWithoutEvidence() {
		for count in [1, 2] {
			var unprompted = UnlockChallengeGate(requiredActions: count)
			unprompted.completeAction()
			check(!unprompted.isVerified && unprompted.completedActions == 0,
				"unprompted completion denied for count \(count)")
			check(!unprompted.admits(frameID: 1, capturedAt: .now, now: .now),
				"unprompted sample denied for count \(count)")
			var presented = UnlockChallengeGate(requiredActions: count)
			presented.present(at: .now, frameID: 1)
			presented.completeAction()
			check(!presented.isVerified && presented.completedActions == 0,
				"presentation without admitted evidence cannot complete for count \(count)")
		}
	}

	static func resetPreservesCount() {
		for count in [1, 2] {
			var idle = UnlockChallengeGate(requiredActions: count)
			check(!idle.reset(), "idle reset changes nothing for count \(count)")
			check(idle.requiredActions == count && !idle.isVerified && idle.completedActions == 0,
				"idle reset preserves count \(count)")
			let start = ContinuousClock.now
			var partial = UnlockChallengeGate(requiredActions: count)
			partial.present(at: start, frameID: 1)
			let at = start.advanced(by: .milliseconds(400))
			check(partial.admits(frameID: 2, capturedAt: at, now: at), "partial evidence admitted for count \(count)")
			check(partial.reset(), "reset after partial completion withdraws guidance for count \(count)")
			check(partial.requiredActions == count && partial.completedActions == 0
				&& !partial.isPresented && !partial.isVerified,
				"reset clears partial proof but keeps count \(count)")
			check(!partial.admits(frameID: 3, capturedAt: at, now: at),
				"withdrawn guidance cannot accept the old response for count \(count)")
			var full = UnlockChallengeGate(requiredActions: count)
			full.present(at: start, frameID: 11)
			var frame: UInt64 = 12
			var atTime = start.advanced(by: .milliseconds(400))
			for _ in 0..<count {
				check(full.admits(frameID: frame, capturedAt: atTime, now: atTime),
					"completion evidence admitted for count \(count)")
				full.completeAction()
				frame += 2
				let presentedAt = atTime
				atTime = atTime.advanced(by: .milliseconds(500))
				if !full.isVerified {
					full.present(at: presentedAt, frameID: frame - 1)
				}
			}
			check(full.isVerified, "gate verifies before full reset for count \(count)")
			check(full.reset(), "reset after verification withdraws completed guidance for count \(count)")
			check(full.requiredActions == count && full.completedActions == 0 && !full.isVerified,
				"reset clears full proof but keeps count \(count)")
		}
		// Interrupted two-action sequence still requires two new movements.
		let start = ContinuousClock.now
		var interrupted = UnlockChallengeGate(requiredActions: 2)
		interrupted.present(at: start, frameID: 1)
		let at = start.advanced(by: .milliseconds(400))
		check(interrupted.admits(frameID: 2, capturedAt: at, now: at), "interrupted first evidence admitted")
		interrupted.completeAction()
		check(interrupted.reset(), "loss between movements withdraws the previous animation")
		check(interrupted.requiredActions == 2 && interrupted.completedActions == 0 && !interrupted.isPresented,
			"interrupted sequence keeps two and requires two new prompted movements")
	}

	static func timingAndReplay(for count: Int) {
		let start = ContinuousClock.now
		var gate = UnlockChallengeGate(requiredActions: count)
		gate.present(at: start, frameID: 100)
		for milliseconds in [-10, 0, 100, 349] {
			let time = start.advanced(by: .milliseconds(milliseconds))
			check(!gate.admits(frameID: 101, capturedAt: time, now: time),
				"pre-prompt and presentation frames denied for count \(count)")
		}
		let response = start.advanced(by: .milliseconds(400))
		check(!gate.admits(frameID: 100, capturedAt: response, now: response),
			"presentation frame cannot be reused for count \(count)")
		check(!gate.admits(frameID: 101, capturedAt: response, now: start),
			"future capture denied for count \(count)")
		check(!gate.admits(frameID: 101, capturedAt: response, now: response.advanced(by: .seconds(1))),
			"stale capture denied for count \(count)")
		check(gate.admits(frameID: 101, capturedAt: response, now: response),
			"fresh post-prompt capture accepted for count \(count)")
		check(!gate.admits(frameID: 101, capturedAt: response, now: response),
			"reused evidence denied for count \(count)")
		check(!gate.admits(frameID: 102, capturedAt: response, now: response),
			"duplicate timestamp denied for count \(count)")
		var expiring = UnlockChallengeGate(requiredActions: count)
		expiring.present(at: start, frameID: 200)
		check(expiring.expired(at: start.advanced(by: .seconds(8))),
			"challenge timeout uses monotonic time for count \(count)")
		check(expiring.expired(at: start.advanced(by: .seconds(-1))),
			"clock reversal fails closed for count \(count)")
		let late = start.advanced(by: .seconds(8))
		check(!expiring.admits(frameID: 201, capturedAt: late, now: late),
			"expired challenge cannot accept response for count \(count)")
		expiring.completeAction()
		check(!expiring.isVerified, "expired challenge cannot authorize for count \(count)")
	}

	static func feed(_ challenge: LivenessChallenge, yaw: Double, pitch: Double = 0) {
		challenge.consume(yaw: yaw, pitch: pitch, eyes: 0.3, mouth: 0.1)
	}

	static func completeTurn(_ challenge: LivenessChallenge, gate: inout UnlockChallengeGate,
		start: ContinuousClock.Instant, presentFrame: UInt64, excursionYaw: Double, _ label: String) {
		for _ in 0..<3 { challenge.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1) }
		check(challenge.isBaselineReady, "turn baseline prepares \(label)")
		gate.present(at: start, frameID: presentFrame)
		let first = start.advanced(by: .milliseconds(400))
		check(gate.admits(frameID: presentFrame + 1, capturedAt: first, now: first),
			"post-interval excursion frame admitted \(label)")
		feed(challenge, yaw: excursionYaw)
		check(!challenge.isReturningToRest && !challenge.isComplete,
			"one excursion sample is not yet movement \(label)")
		let second = start.advanced(by: .milliseconds(450))
		check(gate.admits(frameID: presentFrame + 2, capturedAt: second, now: second),
			"second excursion frame admitted \(label)")
		feed(challenge, yaw: excursionYaw)
		check(challenge.isReturningToRest && !challenge.isComplete,
			"admitted excursion observes movement without completing \(label)")
		let returned = start.advanced(by: .milliseconds(600))
		check(gate.admits(frameID: presentFrame + 3, capturedAt: returned, now: returned),
			"return frame admitted \(label)")
		feed(challenge, yaw: 0.0)
		check(challenge.isComplete, "admitted excursion plus admitted return completes \(label)")
		gate.completeAction()
	}

	static func turnAndReturnThroughGate(for count: Int) {
		if count == 1 {
			let challenge = LivenessChallenge(action: .turnLeft)
			var gate = UnlockChallengeGate(requiredActions: 1)
			let start = ContinuousClock.now
			// Production excursion is 0.30 rad with two qualifying samples and a
			// 0.10 rad return window; 0.35 exceeds it, 0.0 returns inside it.
			completeTurn(challenge, gate: &gate, start: start, presentFrame: 300,
				excursionYaw: 0.35, "single turn-left")
			check(gate.completedActions == 1 && gate.isVerified,
				"one turn-and-return verifies a one-action gate")
		} else {
			let first = LivenessChallenge(action: .turnLeft)
			var gate = UnlockChallengeGate(requiredActions: 2)
			let start = ContinuousClock.now
			completeTurn(first, gate: &gate, start: start, presentFrame: 400,
				excursionYaw: 0.35, "first turn-left of two")
			check(gate.completedActions == 1 && !gate.isVerified,
				"one admitted turn-and-return still requires the second prompted action")
			let presentedAt = start.advanced(by: .milliseconds(600))
			let second = LivenessChallenge(action: .turnRight)
			completeTurn(second, gate: &gate, start: presentedAt, presentFrame: 500,
				excursionYaw: -0.35, "second turn-right of two")
			check(gate.completedActions == 2 && gate.isVerified,
				"two turn-and-returns verify a two-action gate")
		}
	}
}
