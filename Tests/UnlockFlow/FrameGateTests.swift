import Foundation

@main
@MainActor
enum FrameGateTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func main() {
		let start = ContinuousClock.now
		var cold = RecognitionFrameGate(now: start)
		for milliseconds in [0, 500, 1_000, 1_500, 3_000, 4_000, 7_500] {
			check(cold.observe(id: 0, capturedAt: nil, now: start.advanced(by: .milliseconds(milliseconds))) == .waiting,
				"cold camera gets a bounded first-frame warmup at \(milliseconds)ms")
		}
		let expired = start.advanced(by: .seconds(8)).advanced(by: .nanoseconds(1))
		check(cold.observe(id: 0, capturedAt: nil, now: expired) == .stalled, "missing first frame times out")
		check(cold.observe(id: 1, capturedAt: expired, now: expired) == .stalled, "late frame cannot revive timed-out attempt")

		for delay in [1_500, 2_500, 4_000] {
			var recovering = RecognitionFrameGate(now: start)
			let arriving = start.advanced(by: .milliseconds(delay))
			check(recovering.observe(id: 0, capturedAt: nil, now: start.advanced(by: .seconds(1))) == .waiting,
				"initial delay is not an established-stream stall")
			check(recovering.observe(id: 1, capturedAt: arriving, now: arriving) == .fresh(continuous: false),
				"first fresh frame after warmup starts without inherited evidence")
			let next = arriving.advanced(by: .milliseconds(100))
			check(recovering.observe(id: 2, capturedAt: next, now: next) == .fresh(continuous: true),
				"normal frames establish continuity after warmup")
			check(recovering.observe(id: 2, capturedAt: next, now: next.advanced(by: .seconds(1))) == .waiting,
				"established stream retains original one-second boundary")
			let stalled = next.advanced(by: .seconds(1)).advanced(by: .nanoseconds(1))
			check(recovering.observe(id: 2, capturedAt: next, now: stalled) == .stalled,
				"established stream does not inherit startup grace")
		}

		var invalid = RecognitionFrameGate(now: start)
		let twoSeconds = start.advanced(by: .seconds(2))
		check(invalid.observe(id: 1, capturedAt: start, now: twoSeconds) == .waiting,
			"warmup never admits stale image evidence")
		check(invalid.observe(id: 2, capturedAt: twoSeconds.advanced(by: .seconds(1)), now: twoSeconds) == .waiting,
			"warmup never admits future capture timestamps")
		check(invalid.observe(id: 3, capturedAt: expired, now: expired) == .stalled,
			"invalid frames cannot extend initial deadline")

		var delayedPoll = RecognitionFrameGate(now: start)
		check(delayedPoll.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false), "establish stream")
		check(delayedPoll.observe(id: 2, capturedAt: twoSeconds, now: twoSeconds) == .stalled,
			"a delayed poll cannot silently revive an expired stream")

		var reversed = RecognitionFrameGate(now: start)
		check(reversed.observe(id: 1, capturedAt: start, now: start.advanced(by: .nanoseconds(-1))) == .stalled,
			"clock reversal fails closed")
		check(reversed.observe(id: 2, capturedAt: start, now: start) == .stalled,
			"clock reversal cannot be undone within an attempt")

		var ageBoundary = RecognitionFrameGate(now: start)
		let halfSecond = start.advanced(by: CameraFrameLease.maximumAge)
		check(ageBoundary.observe(id: 1, capturedAt: start, now: halfSecond) == .fresh(continuous: false),
			"unchanged 500ms evidence-age boundary")
		var tooOld = RecognitionFrameGate(now: start)
		check(tooOld.observe(id: 1, capturedAt: start, now: halfSecond.advanced(by: .nanoseconds(1))) == .waiting,
			"one nanosecond past evidence lifetime is not admitted")
		var rejection = RecognitionRejectionHold()
		for tick in 0...40 {
			check(rejection.consume(capturedAt: start.advanced(by: .milliseconds(tick * 100)), required: .seconds(4)) == (tick == 40),
				"a continuous mismatch rejects only after the unchanged four-second hold")
		}
		rejection.reset()
		let afterLongMatch = start.advanced(by: .seconds(20))
		check(!rejection.consume(capturedAt: afterLongMatch, required: .seconds(4)),
			"time previously spent matching cannot turn one low-scoring frame into a rejection")
		for tick in 1...100 {
			rejection.reset()
			check(!rejection.consume(capturedAt: afterLongMatch.advanced(by: .milliseconds(tick * 100)), required: .seconds(4)),
				"intervening identity matches clear rejection history without granting authentication")
		}
		var discontinuous = RecognitionRejectionHold()
		for tick in 0...20 {
			check(!discontinuous.consume(capturedAt: start.advanced(by: .milliseconds(tick * 300)), required: .seconds(4)),
				"gapped mismatch evidence cannot accumulate into a rejection")
		}
		check(!discontinuous.consume(capturedAt: start, required: .seconds(4)), "out-of-order mismatch starts a new hold")
		check(!discontinuous.consume(capturedAt: start, required: .seconds(4)), "duplicate mismatch does not advance a hold")
		check(!discontinuous.consume(capturedAt: start, required: .zero), "invalid rejection duration does not immediately reject")
		print("PASS: \(checks) frame-startup, stall and rejection-timing checks; synthetic timestamps only.")
	}
}
