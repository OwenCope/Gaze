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

	/// Pure eligibility: a bare launch hands off, as before, and any launch
	/// carrying `--settings` hands off unless a service-mode flag is present.
	///
	/// - Parameter arguments: argv after the executable
	///   (`Array(CommandLine.arguments.dropFirst())` in production).
	/// - Returns: true for `[]`, or when `--settings` is present without any of
	///   `--agent`, `--scan-only`, `--ui-review`, or `--browser-only`. Those modes
	///   change what the new process would do, so they bypass the handoff
	///   unchanged — as does anything without `--settings` at all. `--settings`
	///   combined with `--settings-pane=<name>` hands off; the pane is staged
	///   under `pendingPaneKey` for the running app instead of starting a
	///   duplicate process to display it.
	static func isEligibleLaunch(arguments: [String]) -> Bool {
		if arguments.isEmpty { return true }
		guard arguments.contains("--settings") else { return false }
		return !arguments.contains(where: { serviceModeFlags.contains($0) })
	}

	/// Flags that put the new process into a service or review mode. Handing off
	/// would silently drop that mode, so these bypass the handoff unchanged.
	private static let serviceModeFlags: Set<String> = [
		"--agent", "--scan-only", "--ui-review", "--browser-only",
	]

	/// Shared-defaults key staging a `--settings-pane=` request for the running app.
	///
	/// The running app reads its pane from its own argv, which a handoff never
	/// changes, so the handing-off process leaves the validated pane name here
	/// for it to consume when it presents Settings.
	static let pendingPaneKey = "com.gazeunlock.Gaze.pendingSettingsPane"
	private static let paneFlagPrefix = "--settings-pane="

	/// First `--settings-pane=<name>` value, validated against the known panes so
	/// a typo never stages a request the running app cannot honour. Mirrors the
	/// `first(where:)` parse in SettingsView, so handoff and fresh launch agree.
	static func requestedPane(arguments: [String]) -> String? {
		guard let argument = arguments.first(where: { $0.hasPrefix(paneFlagPrefix) }) else { return nil }
		let name = String(argument.dropFirst(paneFlagPrefix.count))
		guard SettingsPane(rawValue: name) != nil else { return nil }
		return name
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
		if let pane = requestedPane(arguments: arguments) {
			UserDefaults.standard.set(pane, forKey: pendingPaneKey)
		}
		target.activate()
		if !NSWorkspace.shared.open(bundleURL) {
			logger.notice("Settings launch handoff could not reopen the running app; exiting without starting services.")
		}
		return true
	}
}
