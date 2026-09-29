import AppKit
import Foundation

/// Watches for locked apps coming to the front and asks for the shield.
///
/// Subscribes to activation and launch notifications, consults the store and
/// the state machine, and reports through `shouldShield(bundleID:)` and the
/// `onShieldNeeded` callback. It shows nothing itself: the shield window, the
/// settings UI and the Finder extension all come later.
///
/// The callback fires synchronously inside the activation handler, which is
/// what "before a locked app becomes key" means here — the notification
/// arrives as the app comes forward, and the shield request goes out before
/// the run loop hands it key status.
final class AppLockWatcher {

	/// Honest footer copy for the future settings and shield UI: App Lock is a
	/// privacy shield, not encryption. The app still runs, notifications still
	/// show, and quitting Gaze removes the shield.
	static let privacyNote =
		"App Lock keeps apps private from people using your Mac. It doesn’t encrypt them."

	private let store: AppLockStore
	private let machine: AppLockStateMachine
	private var observers: [NSObjectProtocol] = []
	private var isWatching = false

	/// Fired with the bundle ID every time a locked app needs the shield.
	var onShieldNeeded: ((String) -> Void)?

	init(store: AppLockStore, machine: AppLockStateMachine) {
		self.store = store
		self.machine = machine
	}

	// MARK: - Queries

	/// Whether the shield must cover the app right now.
	func shouldShield(bundleID: String, now: Date = Date()) -> Bool {
		machine.needsShield(bundleID, now: now)
	}

	/// An app became frontmost. Returns whether the shield is needed, and
	/// fires `onShieldNeeded` when it is.
	///
	/// The expiry check runs before background timing ends, so an app back
	/// from a long background still asks for the face on this activation.
	@discardableResult
	func appDidActivate(bundleID: String, now: Date = Date()) -> Bool {
		let shield = machine.needsShield(bundleID, now: now)
		machine.appDidActivate(bundleID, now: now)
		if shield {
			onShieldNeeded?(bundleID)
		}
		return shield
	}

	// MARK: - Watching

	func start() {
		guard !isWatching else { return }
		isWatching = true
		let workspace = NSWorkspace.shared.notificationCenter
		observers.append(
			workspace.addObserver(
				forName: NSWorkspace.didActivateApplicationNotification, object: nil,
				queue: .main
			) { [weak self] note in
				guard let bundleID = Self.bundleID(from: note) else { return }
				_ = self?.appDidActivate(bundleID: bundleID)
			})
		observers.append(
			workspace.addObserver(
				forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
				queue: .main
			) { [weak self] note in
				// A fresh process is never unlocked: make sure no stale unlock
				// survives a relaunch, whatever the "Lock again" option says.
				let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
				guard let bundleID = app?.bundleIdentifier else { return }
				self?.machine.appDidLaunch(bundleID, launchedAt: app?.launchDate)
			})
		observers.append(
			workspace.addObserver(
				forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
				queue: .main
			) { [weak self] note in
				guard let bundleID = Self.bundleID(from: note) else { return }
				self?.machine.appDidQuit(bundleID)
			})
		observers.append(
			workspace.addObserver(
				forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
			) { [weak self] _ in
				self?.machine.systemDidSleep()
			})
		observers.append(
			DistributedNotificationCenter.default().addObserver(
				forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
			) { [weak self] _ in
				self?.machine.screenDidLock()
			})
	}

	func stop() {
		for token in observers {
			NSWorkspace.shared.notificationCenter.removeObserver(token)
			DistributedNotificationCenter.default().removeObserver(token)
		}
		observers.removeAll()
		isWatching = false
	}

	private static func bundleID(from note: Notification) -> String? {
		(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
			.bundleIdentifier
	}
}
