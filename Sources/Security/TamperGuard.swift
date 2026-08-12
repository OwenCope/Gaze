import AppKit
import Foundation
import Security
import os

/// Requires administrator authentication before the app can be quit, and notices when
/// its own bundle is modified or removed.
///
/// An honest statement of what this can and cannot do: anyone with administrator rights
/// on this Mac can delete the app. SIP protects Apple's software, not ours, and there is
/// no entitlement that makes a third-party app undeletable. What this buys is that
/// removal is *deliberate and noisy* — it cannot happen by someone casually hitting ⌘Q
/// or dragging the app to the Trash without an authentication prompt and a log entry.
/// Treat it as tamper *evidence* with a speed bump, not tamper *proofing*.
@MainActor
final class TamperGuard {

	static let shared = TamperGuard()

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "TamperGuard")

	private var bundleWatcher: DispatchSourceFileSystemObject?
	private(set) var bundleWasModified = false

	private init() {}

	func start() {
		guard Preferences.shared.tamperProtection else { return }
		watchBundle()
		Self.logger.notice("Tamper protection active.")
	}

	func stop() {
		bundleWatcher?.cancel()
		bundleWatcher = nil
	}

	// MARK: - Quitting

	/// Called from `applicationShouldTerminate`. Returns true when the quit may proceed.
	func authorizeQuit() -> Bool {
		guard Preferences.shared.tamperProtection else { return true }

		if requestAdminRights(
			prompt: "Face ID is protected. Authenticate to quit it.")
		{
			Self.logger.notice("Quit authorised by administrator.")
			return true
		}

		Self.logger.notice("Quit refused — administrator authentication failed.")
		return false
	}

	/// Prompts for administrator credentials through Authorization Services.
	///
	/// Uses `system.privilege.admin`, the same right the system uses for its own
	/// padlock buttons, so the prompt is the familiar one and we never see the password.
	private func requestAdminRights(prompt: String) -> Bool {
		var authRef: AuthorizationRef?
		guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
			let authRef
		else { return false }
		defer { AuthorizationFree(authRef, []) }

		return "system.privilege.admin".withCString { name -> Bool in
			var item = AuthorizationItem(
				name: name, valueLength: 0, value: nil, flags: 0)
			return withUnsafeMutablePointer(to: &item) { pointer in
				var rights = AuthorizationRights(count: 1, items: pointer)
				let flags: AuthorizationFlags = [
					.interactionAllowed, .extendRights, .preAuthorize,
				]
				let status = AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
				return status == errAuthorizationSuccess
			}
		}
	}

	// MARK: - Bundle integrity

	/// Watches the app bundle for deletion, renaming or in-place modification.
	///
	/// This cannot prevent any of those — it observes them, so the next launch can warn
	/// that the app is not the one that was enrolled against.
	private func watchBundle() {
		let path = Bundle.main.bundlePath
		let descriptor = open(path, O_EVTONLY)
		guard descriptor >= 0 else {
			Self.logger.error("Could not watch the app bundle at \(path).")
			return
		}

		// Deletion and renaming only.
		//
		// `.write` and `.attrib` fire constantly for reasons that are not tampering — the
		// OS touches bundles, and a rebuild rewrites the whole thing. Worse, the alert
		// below is modal: showing it from the handler meant the alert's own run loop let
		// more events land, which raised another alert, which... The app sat at 79% CPU
		// doing nothing else, and dragged the window server with it.
		let source = DispatchSource.makeFileSystemObjectSource(
			fileDescriptor: descriptor,
			eventMask: [.delete, .rename],
			queue: .main)

		source.setEventHandler { [weak self] in
			guard let self else { return }

			// Once only. This is tamper *evidence*, and the evidence does not improve by
			// being reported repeatedly.
			guard !self.bundleWasModified else { return }

			// Wait, then look again, because a *replacement* is not a removal.
			//
			// An update — `build.sh` swapping in a new bundle, or any installer — renames the
			// old bundle out and the new one in. The watcher sees the rename and, before this,
			// raised a critical "Face ID was modified" alert every single time the app was
			// rebuilt. A guard that fires on the normal update path is one people learn to
			// dismiss without reading, which costs exactly the signal it exists to give.
			//
			// A genuine removal leaves nothing at the path a moment later; a swap leaves a
			// valid bundle. Only the first is worth an alert.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
				guard let self, !self.bundleWasModified else { return }

				if FileManager.default.fileExists(atPath: path) {
					Self.logger.notice("App bundle was replaced; re-arming the watcher.")
					// The old descriptor points at the bundle that was renamed away, so it
					// will never report on the new one. Watch the new bundle instead.
					self.stop()
					self.watchBundle()
					return
				}

				self.bundleWasModified = true
				Self.logger.fault("The Face ID app bundle was moved or removed.")
				self.warnAboutTampering()
			}
		}
		source.setCancelHandler { close(descriptor) }
		source.resume()

		bundleWatcher = source
	}

	private func warnAboutTampering() {
		// A notification, not a modal alert. Blocking the main thread from a file-system
		// event handler is what turned one rebuild into a CPU spin.
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = "Face ID was modified"
		alert.informativeText = """
			The Face ID application bundle changed while it was running. If you didn't \
			update or move it, your enrolled face may no longer be trustworthy — remove \
			the enrolment and set it up again.
			"""
		alert.addButton(withTitle: "OK")
		// Deferred, so the event handler returns immediately and the source is free to be
		// cancelled while the alert is up.
		DispatchQueue.main.async { alert.runModal() }
	}
}
