import AppKit
import Observation
import os

/// Notices when a saved app comes forward showing its unlock screen, and fills it.
///
/// The shortcut came first and, on its own, was the wrong shape. You open 1Password, it
/// asks for your password, and pressing a key combination to make it stop asking is not
/// obviously less work than typing the password — the moment that wants automating is the
/// app appearing, not a keystroke afterwards.
///
/// **What "locked" means here.** Not a guess, and not a list of window titles. An app that
/// is waiting for a password has a **secure text field with keyboard focus** — that is what
/// a lock screen *is*, structurally, and Accessibility reports it directly. So the test is:
/// a saved app just became frontmost, and something secure has focus. Both, or nothing
/// happens.
///
/// **Why activation and not an observer.** Watching focus across every app would mean an
/// Accessibility observer on each one, permanently. `didActivateApplication` is a single
/// notification the system already posts, it fires exactly when the interesting thing
/// happens, and between activations this class does nothing at all.
@Observable
@MainActor
final class AutofillWatcher {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "AutofillWatch")

	/// An app's window is often not built at the instant it activates, so the secure field
	/// does not have focus yet. Rather than fire once and miss, look a few times across a
	/// short window and stop at the first sighting.
	private static let pollInterval: Duration = .milliseconds(250)
	private static let pollAttempts = 8

	/// How long before the same app may trigger again.
	///
	/// Without it, a failed face check leaves the app frontmost with the field still
	/// focused, and every subsequent activation — including the one caused by Gaze's own
	/// panel appearing and going away — starts another camera check. One refusal should
	/// mean the user types their password in peace.
	private static let cooldown: TimeInterval = 30

	private let savedApps: SavedAppStore
	private let store: FaceEnrollmentStore
	private let capsule: NotchCapsuleController

	private var observer: NSObjectProtocol?
	private var pending: Task<Void, Never>?
	/// Last time each app was acted on, so a refusal is not immediately retried.
	private var lastAttempt: [String: Date] = [:]

	init(savedApps: SavedAppStore, store: FaceEnrollmentStore, capsule: NotchCapsuleController) {
		self.savedApps = savedApps
		self.store = store
		self.capsule = capsule
	}

	func start() {
		guard observer == nil else { return }
		observer = NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
		) { [weak self] note in
			let app =
				note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			MainActor.assumeIsolated { self?.appActivated(app) }
		}
		Self.logger.notice("Watching for saved apps to come forward.")
	}

	func stop() {
		pending?.cancel()
		pending = nil
		if let observer {
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
			self.observer = nil
		}
	}

	// MARK: - Events

	private func appActivated(_ app: NSRunningApplication?) {
		guard !AutofillService.isBusy else { return }
		// Whatever we were waiting for is no longer frontmost. Stop looking for it.
		pending?.cancel()
		pending = nil

		guard Preferences.shared.autofillOnActivation else { return }
		guard !Preferences.shared.isPaused else { return }
		guard AutofillConsoleSession.current() != nil else { return }
		guard store.isEnrolled else { return }
		guard let bundleID = app?.bundleIdentifier else { return }
		guard savedApps.savedApp(forBundleID: bundleID) != nil else { return }

		guard !AppIdentity.isBrowser(bundleID: bundleID) else {
			Self.logger.notice(
				"\(bundleID, privacy: .public) is a browser; not filling on activation.")
			return
		}

		if let last = lastAttempt[bundleID],
			Date().timeIntervalSince(last) < Self.cooldown
		{
			return
		}

		pending = Task { [weak self] in
			await self?.waitForLockScreen(of: bundleID)
		}
	}

	private func waitForLockScreen(of bundleID: String) async {
		let session = AutofillSessionLease()

		for _ in 0..<Self.pollAttempts {
			try? await Task.sleep(for: Self.pollInterval)
			guard !Task.isCancelled, session.isValid, Preferences.shared.autofillOnActivation,
				!Preferences.shared.isPaused else { return }

			// Still the same app in front? Activation can change again mid-poll.
			guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
				return
			}
			// Secure only. See the note on this type.
			guard AutofillService.focusedField() == .secure else { continue }

			lastAttempt[bundleID] = Date()
			Self.logger.notice("\(bundleID, privacy: .public) is asking for a password.")

			await AutofillService.fillFrontmost(
				savedApps: savedApps, store: store, capsule: capsule)
			return
		}
	}
}
