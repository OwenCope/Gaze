import Foundation

enum RenderDiagnosticsTests {
	static func run() {
		var diagnostics = GazeRenderDiagnostics()
		precondition(diagnostics.record(start: .nan, end: 0, outcome: .submitted) == nil)
		precondition(diagnostics.record(start: 1, end: 0, outcome: .submitted) == nil)
		for frame in 0..<120 {
			let time = Double(frame) / 60
			precondition(diagnostics.record(start: time, end: time + 0.001, outcome: .submitted) == nil)
		}
		let summary = diagnostics.record(start: 2, end: 2.001, outcome: .busy)!
		precondition(summary.callbacks == 121 && summary.submitted == 120 && summary.busy == 1)
		precondition(summary.unavailable == 0 && summary.failed == 0)
		precondition(abs(summary.intervalP95Milliseconds - 1000 / 60) < 0.001)
		precondition(abs(summary.drawMaxMilliseconds - 1) < 0.001)
		precondition(diagnostics.record(start: 2.02, end: 2.03, outcome: .unavailable) == nil)
		let stalled = diagnostics.record(start: 4.1, end: 4.15, outcome: .failed)!
		precondition(stalled.callbacks == 2 && stalled.submitted == 0)
		precondition(stalled.unavailable == 1 && stalled.failed == 1)
		precondition(abs(stalled.intervalMaxMilliseconds - 2080) < 0.001)
		precondition(abs(stalled.drawMaxMilliseconds - 50) < 0.001)
		// A restarted clock/session must not inherit the previous sample's gap.
		precondition(diagnostics.record(start: 0, end: 0.001, outcome: .submitted) == nil)
		let restarted = diagnostics.record(start: 2, end: 2.001, outcome: .submitted)!
		precondition(restarted.callbacks == 2 && restarted.busy == 0 && restarted.failed == 0)
		precondition(diagnostics.record(start: 2.1, end: 2.12, outcome: .submitted, drawableSeconds: 0.015) == nil)
		let partial = diagnostics.finish()!
		precondition(partial.callbacks == 1 && abs(partial.drawableMaxMilliseconds - 15) < 0.001)
		precondition(diagnostics.finish() == nil, "Ending a short animation must report once, not lose or duplicate its sample")
		print("PASS: render timing distinguishes callbacks/submissions/skips, captures stalls, and resets sample windows")
	}
}
