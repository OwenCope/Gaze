import Foundation
import ServiceManagement
import os

/// Starts Face ID when you log in.
///
/// Uses `SMAppService.mainApp` rather than a LaunchAgent plist. The plist approach is
/// what the authorization-plugin path needed — only launchd can vend a mach service — but
/// it came with `KeepAlive`, and `KeepAlive` plus a startup crash is an infinite restart
/// loop. Combined with an unconditional `activate()` that produced a process which stole
/// focus every few seconds and could not be quit.
///
/// The keystroke backend needs none of that. It just needs to be running, so a plain login
/// item is both sufficient and far harder to get wrong: launchd starts it once, and if it
/// exits it stays exited.
enum LoginItem {

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "LoginItem")

	static var isEnabled: Bool {
		SMAppService.mainApp.status == .enabled
	}

	/// True when the user has to approve it in System Settings before it takes effect.
	static var needsApproval: Bool {
		SMAppService.mainApp.status == .requiresApproval
	}

	@discardableResult
	static func setEnabled(_ enabled: Bool) -> Bool {
		do {
			if enabled {
				try SMAppService.mainApp.register()
				logger.notice("Registered as a login item.")
			} else {
				try SMAppService.mainApp.unregister()
				logger.notice("Unregistered as a login item.")
			}
			return true
		} catch {
			logger.error("Could not change login item state: \(error.localizedDescription)")
			return false
		}
	}
}
