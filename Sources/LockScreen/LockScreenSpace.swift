import AppKit
import os

/// Puts a window on the lock screen, via private SkyLight SPI.
///
/// The obvious approaches do not work. Raising `NSWindow.level` — even above
/// `CGShieldingWindowLevel()` — does nothing, because the lock screen is not merely a
/// window that outranks yours: it is a separate *space*, and the compositor simply does
/// not draw your space while it is up. Level is the wrong axis entirely.
///
/// What does work is creating our own space, pinning its absolute level to the one macOS
/// reserves for content shown at the screen lock, and moving the window into it by window
/// number.
///
/// This is unsupported SPI. It can break in any macOS release, so every call is optional
/// and failure degrades to "no capsule on the lock screen" rather than to a crash — face
/// unlock itself never depends on any of this.
@MainActor
final class LockScreenSpace {

	static let shared = LockScreenSpace()

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "LockScreenSpace")

	/// Absolute space levels macOS uses. Anything at or above the screen-lock level is
	/// composited while the screen is locked.
	private enum Level: Int32 {
		case screenLock = 300
		/// What Notification Center uses at the lock screen — above the lock UI itself,
		/// which is where a status capsule belongs.
		case notificationCentreAtScreenLock = 400
	}

	private typealias MainConnectionID = @convention(c) () -> Int32
	private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
	private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
	private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
	private typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
	private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32

	private var connection: Int32 = 0
	private var space: Int32 = 0
	private var addWindows: SpaceAddWindows?
	private var removeWindows: RemoveWindows?

	private(set) var isAvailable = false

	private init() {
		setUp()
	}

	private func setUp() {
		guard
			let handle = dlopen(
				"/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
				RTLD_NOW)
		else {
			Self.logger.error("SkyLight unavailable; no lock screen UI.")
			return
		}

		func symbol<T>(_ name: String, as type: T.Type) -> T? {
			guard let pointer = dlsym(handle, name) else {
				Self.logger.error("SkyLight is missing \(name); no lock screen UI.")
				return nil
			}
			return unsafeBitCast(pointer, to: type)
		}

		guard
			let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionID.self),
			let createSpace = symbol("SLSSpaceCreate", as: SpaceCreate.self),
			let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
			let showSpaces = symbol("SLSShowSpaces", as: ShowSpaces.self),
			let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddWindows.self),
			let remove = symbol("SLSRemoveWindowsFromSpaces", as: RemoveWindows.self)
		else { return }

		connection = mainConnection()
		space = createSpace(connection, 1, 0)
		_ = setLevel(connection, space, Level.notificationCentreAtScreenLock.rawValue)
		_ = showSpaces(connection, [space] as CFArray)

		addWindows = add
		removeWindows = remove
		isAvailable = true

		Self.logger.notice("Lock screen space \(self.space) ready.")
	}

	/// Moves a window into the lock screen space.
	///
	/// Must be called after the window exists on screen — it is addressed by window
	/// number, which is only assigned once the window has been ordered in.
	func adopt(_ window: NSWindow) {
		guard isAvailable, let addWindows else { return }
		// The trailing 7 is the selector mask SkyLight expects for a full move.
		_ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
	}

	func release(_ window: NSWindow) {
		guard isAvailable, let removeWindows else { return }
		_ = removeWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
	}
}
