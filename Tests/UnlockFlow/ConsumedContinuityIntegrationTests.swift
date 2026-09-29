import Foundation

// TEAM-INVESTIGATION-20260915.md section 2: RecognitionFrameGate judges continuity
// between *consumed* captures, while CameraEvidenceContinuity tracks every *delivered*
// camera frame. The previous LockWatcher slept 60 ms per loop after evaluator work before
// polling again, so consumed captures can land more than 240 ms apart — tripping the
// movement-proof reset — while the delivered stream never gapped and the evaluated
// sample stays inside its 500 ms lease. These checks pin that divergence with the
// production constants and types; timestamps are synthetic.

@main
enum ConsumedContinuityIntegrationTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func main() {
		check(CameraEvidenceContinuity.maximumGap == .milliseconds(240), "pin delivered-gap constant")
		check(CameraFrameLease.maximumAge == .milliseconds(500), "pin evidence-lease constant")
		let start = ContinuousClock.now
		// Delivered view: continuous 30 Hz usable frames, as CameraController records them.
		var delivered = CameraEvidenceContinuity()
		check(delivered.record(usable: true, capturedAt: start), "initial delivery accepted")
		let streamRevision = delivered.revision
		for frame in 1...8 {
			check(delivered.record(usable: true, capturedAt: start.advanced(by: .milliseconds(frame * 33))),
				"30Hz delivery accepted at frame \(frame)")
		}
		check(delivered.revision == streamRevision, "continuous delivery preserves the camera revision")
		// Previous consumed view: 220 ms inference plus a fixed 60 ms sleep polls
		// at 280 ms. The latest delivered capture is frame 8 at 264 ms.
		var consumed = RecognitionFrameGate(now: start)
		check(consumed.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false),
			"first consumed frame starts without inherited evidence")
		let second = start.advanced(by: .milliseconds(280))
		let secondCapture = start.advanced(by: .milliseconds(264))
		check(consumed.observe(id: 9, capturedAt: secondCapture, now: second) == .fresh(continuous: false),
			"264ms consumed spacing reports a frame gap while the delivered stream stayed continuous")
		check(delivered.permits(streamRevision, at: second),
			"the same instant still passes the camera-continuity lease check")
		for frame in 9...20 {
			check(delivered.record(usable: true, capturedAt: start.advanced(by: .milliseconds(frame * 33))),
				"later 30Hz delivery accepted at frame \(frame)")
		}
		check(delivered.revision == streamRevision,
			"the delivered stream never gapped across the whole consumed interval")
		// With inference included in the poll interval, the same 220 ms workload
		// polls immediately and consumes the latest real capture at 198 ms.
		let evaluatedAt = start.advanced(by: .milliseconds(220))
		check(RecognitionScanPacing.delay(since: start, now: evaluatedAt) == .zero,
			"slow evaluation must not add another fixed sleep")
		check(RecognitionScanPacing.delay(since: start, now: start.advanced(by: .milliseconds(5))) == RecognitionScanPacing.minimumPollInterval - .milliseconds(5),
			"fast or empty polls remain throttled instead of busy looping")
		var paced = RecognitionFrameGate(now: start)
		_ = paced.observe(id: 1, capturedAt: start, now: start)
		let pacedCapture = start.advanced(by: .milliseconds(198))
		check(paced.observe(id: 7, capturedAt: pacedCapture, now: evaluatedAt) == .fresh(continuous: true),
			"220ms evaluation can consume continuous evidence without changing the 240ms gate")
		check(RecognitionScanPacing.delay(since: start, now: start) == RecognitionScanPacing.minimumPollInterval,
			"initial polling interval is unchanged")
		// Consumed-side gap boundary (the delivered-side boundary is pinned in ContinuityTests).
		var exact = RecognitionFrameGate(now: start)
		check(exact.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false),
			"boundary stream starts")
		let atGap = start.advanced(by: CameraEvidenceContinuity.maximumGap)
		check(exact.observe(id: 2, capturedAt: atGap, now: atGap) == .fresh(continuous: true),
			"consumed captures exactly one maximum gap apart stay continuous")
		var over = RecognitionFrameGate(now: start)
		check(over.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false),
			"overrun stream starts")
		let pastGap = start.advanced(by: .milliseconds(240)).advanced(by: .nanoseconds(1))
		check(over.observe(id: 2, capturedAt: pastGap, now: pastGap) == .fresh(continuous: false),
			"one nanosecond past the consumed gap breaks continuity")
		// A fresh-but-gapped sample is admitted (and trips the consumed-gap reset),
		// while a stale sample is refused outright: distinct outcomes, distinct reasons.
		var gapped = RecognitionFrameGate(now: start)
		check(gapped.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false),
			"gapped stream starts")
		let gappedAt = start.advanced(by: .milliseconds(300))
		check(gapped.observe(id: 2, capturedAt: gappedAt, now: gappedAt) == .fresh(continuous: false),
			"captures 300ms apart can be fresh at consumption while still breaking continuity")
		var stale = RecognitionFrameGate(now: start)
		check(stale.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false),
			"stale stream starts")
		let staleCapture = start.advanced(by: .milliseconds(100))
		let staleNow = start.advanced(by: .milliseconds(700))
		check(stale.observe(id: 2, capturedAt: staleCapture, now: staleNow) == .waiting,
			"evidence polled 600ms after capture is refused as stale, not reported as a fresh gap")
		print("PASS: \(checks) consumed-vs-delivered continuity checks; synthetic timestamps only, no camera or observed lock-screen replay.")
	}
}
