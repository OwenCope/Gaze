import AppKit
import Foundation

/// Synthetic AppKit host for the settings-launch handoff regression.
///
/// Compiled together with the production `SettingsLaunchHandoff.swift` into a test
/// bundle with a unique bundle ID, so the handoff under test is the real one: bundle
/// identifier, executable-URL and bundle-URL matching all behave as in production.
///
/// Modes (all driven by argv after the executable plus environment):
/// - Two-process test: launch once with no args (becomes the "running app": writes a
///   per-PID service marker, then idles and records `applicationShouldHandleReopen`
///   into a reopen marker). Launch the same executable again with `--settings`: the
///   handoff must find the first instance, reopen it, and exit(0) without writing a
///   service marker of its own.
/// - Self-test (`GAZE_HANDOFF_SELFTEST=1`): exercises the pure eligibility function
///   over the bypass flags plus the no-existing-instance redirect case, with no
///   NSApplication event loop. Prints PASS/FAIL lines and exits nonzero on failure.
///
/// Marker directory comes from `GAZE_HANDOFF_TEST_DIR`. This fixture never touches
/// production Gaze, its LaunchAgent, the camera, credentials, real defaults, or any
/// service: the "service start" is creating one small file.
@main
struct HandoffFixture {

	static func main() {
		let testDir = ProcessInfo.processInfo.environment["GAZE_HANDOFF_TEST_DIR"] ?? NSTemporaryDirectory()
		if ProcessInfo.processInfo.environment["GAZE_HANDOFF_SELFTEST"] != nil {
			let failures = MainActor.assumeIsolated { Self.runSelfTest(testDir: testDir) }
			if !failures.isEmpty {
				for failure in failures { print("FAIL \(failure)") }
				exit(1)
			}
			print("PASS settings-launch-handoff selftest")
			exit(0)
		}

		let handled: Bool = MainActor.assumeIsolated { SettingsLaunchHandoff.redirectIfNeeded() }
		if handled { exit(0) }

		// Past the handoff: this instance is the running app. The service marker is
		// per-PID so the harness can tell a second instance started its own stack.
		let pid = ProcessInfo.processInfo.processIdentifier
		let marker = (testDir as NSString).appendingPathComponent("service-\(pid)")
		try? "started".write(toFile: marker, atomically: true, encoding: .utf8)

		let app = NSApplication.shared
		app.setActivationPolicy(.accessory)
		let delegate = FixtureDelegate(testDir: testDir)
		app.delegate = delegate
		// Safety net so a stray fixture can never linger past the harness.
		Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in NSApp.terminate(nil) }
		app.run()
	}

	@MainActor
	static func runSelfTest(testDir: String) -> [String] {
		var failures: [String] = []
		func check(_ name: String, _ actual: Bool, _ expected: Bool) {
			print("\(actual == expected ? "PASS" : "FAIL") eligibility \(name) -> \(actual)")
			if actual != expected { failures.append("eligibility \(name)") }
		}
		check("empty", SettingsLaunchHandoff.isEligibleLaunch(arguments: []), true)
		check("--settings", SettingsLaunchHandoff.isEligibleLaunch(arguments: ["--settings"]), true)
		for bypass in [
			["--agent"], ["--setup"], ["--setup-step"], ["--setup-step=face"],
			["--ui-review"], ["--scan-only"], ["--browser-only"],
			["--shoot-lockscreen"], ["--capture-dataset"], ["--startup-diagnostics"],
			["--debug-windows"], ["--other"], ["settings"], ["--settings", "--settings"],
			["--settings", "--agent"], ["--agent", "--settings"],
		] {
			check(bypass.joined(separator: " "), SettingsLaunchHandoff.isEligibleLaunch(arguments: bypass), false)
		}
		// No other instance of this test bundle is running during the self-test, so an
		// eligible launch must report no redirect, and a bypassed launch must not
		// redirect either (and must not activate or open anything as a side effect).
		let noInstance = SettingsLaunchHandoff.redirectIfNeeded(arguments: [])
		print("\(noInstance == false ? "PASS" : "FAIL") redirect no-existing-instance -> \(noInstance)")
		if noInstance { failures.append("redirect no-existing-instance") }
		let bypassed = SettingsLaunchHandoff.redirectIfNeeded(arguments: ["--agent"])
		print("\(bypassed == false ? "PASS" : "FAIL") redirect bypass-flag -> \(bypassed)")
		if bypassed { failures.append("redirect bypass-flag") }
		return failures
	}
}

final class FixtureDelegate: NSObject, NSApplicationDelegate {
	let testDir: String

	init(testDir: String) {
		self.testDir = testDir
		super.init()
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		let marker = (testDir as NSString).appendingPathComponent("reopened")
		try? "reopened".write(toFile: marker, atomically: true, encoding: .utf8)
		return false
	}
}
