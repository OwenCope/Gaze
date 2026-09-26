import Foundation

@main
@MainActor
enum DiagnosticsTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		guard condition() else { print("FAIL: \(description)"); exit(1) }
		checks += 1
	}

	static func main() {
		let diagnostics = LockScanDiagnostics()
		let first = UUID()
		let second = UUID()
		check(diagnostics.outcome == nil, "fresh app does not invent a previous result")
		diagnostics.begin(first)
		check(diagnostics.outcome == .starting, "attempt begins as camera startup, not face recognition")
		diagnostics.record(.scanning, for: first)
		check(diagnostics.outcome == .scanning, "fresh frames allow scanning status")
		diagnostics.begin(second)
		diagnostics.record(.submissionUnconfirmed, for: first)
		diagnostics.finishScanning(for: first)
		diagnostics.cancel(for: first)
		check(diagnostics.outcome == .starting, "stale completion and cancellation cannot overwrite a new attempt")
		for outcome in LockScanDiagnostics.Outcome.allCases {
			diagnostics.record(outcome, for: second)
			check(!diagnostics.summary.isEmpty, "every outcome has a recovery explanation")
			check(!diagnostics.summary.contains(second.uuidString), "attempt identifiers are not displayed")
			diagnostics.finishScanning(for: second)
			check(diagnostics.outcome == (outcome.isScanning ? .cancelled : outcome),
				"finishing preserves failure, pending-delivery and confirmed-unlock outcomes")
		}
		diagnostics.record(.submissionPending, for: second)
		diagnostics.cancel(for: second)
		check(diagnostics.outcome == .cancelled, "stopping the watcher withdraws pending attribution")
		diagnostics.record(.firstFrameTimeout, for: second)
		diagnostics.cancel(for: second)
		check(diagnostics.outcome == .firstFrameTimeout, "manual unlock preserves the useful camera failure")
		check(LockScanDiagnostics.Outcome.submissionStopped.message.contains("will not retry"), "partial delivery explains fallback without promising no input")
		check(!LockScanDiagnostics.Outcome.submissionStopped.message.contains("No password was sent"), "partial delivery is not misreported as zero input")
		let movement = LockScanDiagnostics.MovementFailure(action: "Turn slightly left", returning: false,
			comparedIdentity: true, score: 0.405, threshold: 0.45,
			poseOffset: -0.2, poseTarget: 0.3, returnTolerance: 0.1)
		diagnostics.recordMovementFailure(movement, for: first)
		check(diagnostics.movementFailure == nil, "stale movement diagnostics cannot overwrite the active attempt")
		diagnostics.recordMovementFailure(movement, for: second)
		check(diagnostics.summary.contains("0.405") && diagnostics.summary.contains("-0.20 rad"), "failed turn retains its comparison and relative pose")
		diagnostics.record(.scanning, for: second)
		check(diagnostics.summary.contains("Last movement stopped"), "reacquisition does not erase the reason the previous turn stopped")
		diagnostics.recordMovementFailure(.init(action: "Turn slightly right", returning: true,
			comparedIdentity: false, score: 0, threshold: 0.45,
			poseOffset: nil, poseTarget: nil, returnTolerance: nil), for: second)
		check(diagnostics.summary.contains("returning to the starting pose") && diagnostics.summary.contains("could not complete"),
			"return-stage comparison failure is distinct from an outbound low score")
		check(!diagnostics.summary.contains("was below") && !diagnostics.summary.contains("Movement from start"),
			"unavailable measurements are not invented")
		diagnostics.begin(UUID())
		check(diagnostics.movementFailure == nil && !diagnostics.summary.contains("Last movement stopped"),
			"a new attempt clears the previous diagnostic snapshot")
		print("PASS: \(checks) in-memory unlock diagnostic checks; no camera, credentials or persistence.")
	}
}
