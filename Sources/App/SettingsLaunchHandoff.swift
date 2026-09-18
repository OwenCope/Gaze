import AppKit
import os

/// Narrow foreground handoff: a same-bundle foreground launch reuses the already-running
/// app instead of starting a second full service stack.
///
/// This addresses same-bundle foreground/settings launches only. It is not a race-free
/// global singleton election, and it does not cover differently located app copies:
/// a candidate only matches when both its resolved executable URL and its resolved
/// bundle URL equal this bundle's, so two copies in different locations never match.
///
/// Mechanism is the normal AppKit reuse path — activate the existing app and reopen its
/// bundle, so its existing `applicationShouldHandleReopen`/`openSettings` callback
/// handles presentation. No new distributed notifications, sockets, AppleEvent
/// scripting, process locks, retries, blocking waits, or stopping the existing app.
@MainActor
enum SettingsLaunchHandoff {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Startup")

	/// Pure eligibility: only a bare launch or an exact `--settings` launch hands off.
	///
	/// - Parameter arguments: argv after the executable
	///   (`Array(CommandLine.arguments.dropFirst())` in production).
	/// - Returns: true only for `[]` or `["--settings"]`. Every flagged invocation —
	///   `--agent`, `--setup`, `--setup-step`, `--ui-review`, `--scan-only`,
	///   `--browser-only`, or anything else — bypasses the handoff unchanged.
	static func isEligibleLaunch(arguments: [String]) -> Bool {
		arguments.isEmpty || arguments == ["--settings"]
	}

	/// If an eligible launch finds the same bundle already running, hand presentation to
	/// it and report true so the caller exits before starting any services.
	///
	/// Returns true only when a matching existing instance was found — including when
	/// the reopen itself failed, since starting another service stack then would
	/// recreate the duplicate-process defect this exists to prevent. Such a failure is
	/// logged with a fixed diagnostic only.
	static func redirectIfNeeded(arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Bool {
		guard isEligibleLaunch(arguments: arguments) else { return false }
		guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
		guard let thisExecutable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return false }
		let thisBundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
		let currentPID = ProcessInfo.processInfo.processIdentifier
		let ordered = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
			.filter {
				$0.processIdentifier != currentPID
					&& !$0.isTerminated
					&& $0.executableURL?.resolvingSymlinksInPath() == thisExecutable
					&& $0.bundleURL?.resolvingSymlinksInPath() == thisBundle
			}
			.sorted {
				switch ($0.launchDate, $1.launchDate) {
				case let (first?, second?):
					return first != second
						? first < second
						: $0.processIdentifier < $1.processIdentifier
				case (_?, nil):
					return true
				case (nil, _?):
					return false
				case (nil, nil):
					return $0.processIdentifier < $1.processIdentifier
				}
			}
		guard let target = ordered.first, let bundleURL = target.bundleURL else { return false }
		target.activate()
		if !NSWorkspace.shared.open(bundleURL) {
			logger.notice("Settings launch handoff could not reopen the running app; exiting without starting services.")
		}
		return true
	}
}
