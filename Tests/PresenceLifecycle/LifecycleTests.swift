import Foundation

private enum TestError: Error { case failed(String) }

/// Synthetic lifecycle tests for walk-away locking policy.
///
/// Exercises the real production `UnlockExecutionPolicy`: walk-away locking
/// must be an opt-in available under the normal policy independently of the
/// unlock backend and password replay, and never under scan-only, UI review,
/// browser-only or any other prohibited launch policy. No camera is opened,
/// no preferences are written, no enrollment or credentials are read, and
/// `ScreenLock` is never touched. Structural lifecycle behaviour (no
/// duplicate starts, stop/clear on disable, startup ordering) is covered by
/// `test-wiring.sh`, which asserts on the production `AppServices` source.
@main
enum PresenceLifecycleTests {
	static var checks = 0
	static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
		guard condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	static func main() throws {
		// Normal operation permits opt-in automatic locking. The property
		// takes no backend or replay inputs by construction — locking needs
		// neither password storage nor replay.
		try expect(UnlockExecutionPolicy.normal.permitsAutomaticLocking, "normal permits opt-in walk-away locking")

		// Every prohibited launch policy refuses it.
		try expect(!UnlockExecutionPolicy.scanOnly.permitsAutomaticLocking, "scan-only never starts the presence watcher")
		try expect(!UnlockExecutionPolicy.uiReview.permitsAutomaticLocking, "UI review never starts the presence watcher")
		try expect(!UnlockExecutionPolicy.browserOnly.permitsAutomaticLocking, "browser-only never starts the presence watcher")

		// Launch-flag parsing lands on a prohibited policy, so a flagged run
		// can never arm walk-away locking whatever the setting says.
		try expect(!UnlockExecutionPolicy(arguments: ["--scan-only"]).permitsAutomaticLocking, "--scan-only run cannot lock")
		try expect(!UnlockExecutionPolicy(arguments: ["--ui-review"]).permitsAutomaticLocking, "--ui-review run cannot lock")
		try expect(!UnlockExecutionPolicy(arguments: ["--browser-only"]).permitsAutomaticLocking, "--browser-only run cannot lock")
		try expect(UnlockExecutionPolicy(arguments: []).permitsAutomaticLocking, "unflagged run permits opt-in locking")

		// Scan-only has precedence over UI review, regardless of argument order.
		try expect(!UnlockExecutionPolicy(arguments: ["--scan-only", "--ui-review"]).permitsAutomaticLocking, "diagnostic flag combination stays prohibited")

		print("Lifecycle policy checks passed: \(checks)")
	}
}
