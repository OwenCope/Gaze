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
/// Deliberately narrower than the shortcut. The manual path accepts a plain text field too,
/// because you pressed a key and said what you wanted; this one only ever acts on a secure
/// field. Typing a password into an ordinary text box because an app happened to come
/// forward is the failure that would make this feature indefensible, and requiring the
/// secure subrole rules it out structurally rather than by care.
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
		// Whatever we were waiting for is no longer frontmost. Stop looking for it.
		pending?.cancel()
		pending = nil

		guard Preferences.shared.autofillOnActivation else { return }
		guard !Preferences.shared.isPaused else { return }
		guard store.isEnrolled else { return }
		guard let bundleID = app?.bundleIdentifier else { return }
		guard savedApps.savedApp(forBundleID: bundleID) != nil else { return }

		// Never automatically, into a browser.
		//
		// A password saved against an application is bound to that application, and for a
		// browser that is not a meaningful boundary: every website shares one process and
		// one bundle identifier. The trigger here is *activation*, so switching to a
		// browser that happens to be showing a page with a focused password field is
		// enough — including a page chosen by whoever wrote it, and the field it receives
		// belongs to that site rather than to the one the password was saved for.
		//
		// Doing this properly needs an origin the browser vouches for, which needs a real
		// browser integration. Until then the shortcut still works, because pressing it is
		// the user saying which field they meant.
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

	/// Looks for a focused secure field for a short while, then gives up quietly.
	///
	/// The camera is opened *now*, alongside the polling, rather than after a field is
	/// found. Starting an `AVCaptureSession` costs between half a second and a second and
	/// a half — more than every other step here combined — so doing it serially meant the
	/// user watched a password box do nothing for two or three seconds. Run in parallel,
	/// the camera is usually already delivering frames by the time the field appears, and
	/// the recognition is the only thing left to wait for.
	///
	/// The cost is honest and worth naming: switching to a saved app that is *not* locked
	/// lights the camera indicator for up to two seconds while this looks for a field that
	/// never comes. That only happens for apps you saved a password for, and never while
	/// autofill is switched off.
	private func waitForLockScreen(of bundleID: String) async {
		let camera = CameraController()
		var cameraStarted = false
		defer { if cameraStarted { camera.stop() } }

		async let warmUp: Void = camera.start(
			pinnedDeviceID: Preferences.shared.requireBuiltInCamera ? store.pinnedCameraID : nil)

		for _ in 0..<Self.pollAttempts {
			try? await Task.sleep(for: Self.pollInterval)
			if Task.isCancelled { return }

			// Still the same app in front? Activation can change again mid-poll.
			guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
				return
			}
			// Secure only. See the note on this type.
			guard AutofillService.focusedField() == .secure else { continue }

			lastAttempt[bundleID] = Date()
			Self.logger.notice("\(bundleID, privacy: .public) is asking for a password.")

			// Collect the warm-up before handing the camera over, so `state` is settled
			// rather than still mid-start when `FaceCheck` looks at it.
			await warmUp
			cameraStarted = true
			await AutofillService.fillFrontmost(
				savedApps: savedApps, store: store, capsule: capsule, warmCamera: camera)
			return
		}

		// No password box appeared. Tidy up the camera we opened on spec.
		await warmUp
		cameraStarted = true
	}
}
