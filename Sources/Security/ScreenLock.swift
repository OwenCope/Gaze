import AppKit
import os

/// Locks the screen, the same way the keyboard shortcut does.
///
/// There are three ways to do this on macOS and only one of them is honest.
///
/// `pmset displaysleepnow` sleeps the display and hopes a lock follows, which it only does
/// if the user has "require password immediately" set — so on a Mac configured any other
/// way it darkens the screen and leaves the session wide open. `CGSession -suspend` shows
/// the login window, but it is fast user switching: it lands on the user list rather than
/// on this session's lock screen, and Gaze's whole flow is built around the latter. The
/// private `SACLockScreenImmediate` in login.framework does the right thing and is a
/// private symbol that can be withdrawn in any point release.
///
/// So: post the system's own Lock Screen shortcut. It is public, it is exactly what the
/// user would do by hand, and it produces the identical lock state that `LockWatcher` is
/// already listening for — which means "Lock Screen Now" and closing the lid go down the
/// same path instead of two that have to be kept in agreement.
///
/// It needs Accessibility, which the keystroke backend already requires and which Settings
/// already asks for. Nothing new is being requested of the user.
enum ScreenLock {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "ScreenLock")

	/// `Q`, in the virtual key codes that never change with keyboard layout.
	private static let keyQ: CGKeyCode = 12

	static func now() {
		guard AXIsProcessTrusted() else {
			logger.error("Cannot lock: Accessibility access has not been granted.")
			return
		}
		guard let source = CGEventSource(stateID: .hidSystemState) else {
			logger.error("Cannot lock: no event source.")
			return
		}

		let modifiers: CGEventFlags = [.maskCommand, .maskControl]
		guard
			let down = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: true),
			let up = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: false)
		else {
			logger.error("Cannot lock: could not build the key events.")
			return
		}
		down.flags = modifiers
		up.flags = modifiers
		down.post(tap: .cghidEventTap)
		up.post(tap: .cghidEventTap)

		logger.notice("Locked the screen.")
	}
}
