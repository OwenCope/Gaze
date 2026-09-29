import Foundation

/// Per-app lock state for App Lock: locked, unlocked, locked again.
///
/// The store says *which* apps are locked; this says which of them are
/// currently unlocked after a successful face check. An unlock lasts until the
/// app quits, the Mac locks or sleeps, or the "Lock again" option says
/// otherwise. Unlock state is memory-only on purpose: a relaunch must never
/// inherit an unlocked app.
///
/// Every method takes `now` so tests can move the clock instead of waiting.
final class AppLockStateMachine {

	enum AppState: Equatable, Sendable {
		case locked
		case unlocked
	}

	/// Background time after which `.afterFiveMinutesInBackground` relocks.
	static let backgroundLimit: TimeInterval = 5 * 60

	/// Face misses after which only Use Password works, until a success clears it.
	static let maxFaceMisses = 3

	private let store: AppLockStore
	private var unlocked: Set<String> = []
	/// When each unlocked app stopped being frontmost, if it has.
	private var backgroundSince: [String: Date] = [:]
	/// Failed face scans per app. Cleared only by a successful unlock.
	private var faceMisses: [String: Int] = [:]
	/// When each app was last unlocked, so a launch notification that arrives after
	/// the unlock (macOS sends it late for an app opened while locked) can't undo it.
	private var unlockedAt: [String: Date] = [:]
	/// How long after an unlock the same app is never shielded again. The unlock
	/// itself moves windows and activation around, and each move is an activation.
	static let unlockGrace: TimeInterval = 3

	init(store: AppLockStore) {
		self.store = store
	}

	// MARK: - Queries

	func state(for bundleID: String, now: Date = Date()) -> AppState {
		isUnlocked(bundleID, now: now) ? .unlocked : .locked
	}

	/// Whether the app may run without the shield right now.
	///
	/// Lazily expires time-based unlocks, so asking is what relocks an app
	/// left in the background past the limit.
	func isUnlocked(_ bundleID: String, now: Date = Date()) -> Bool {
		guard store.isLocked(bundleID), unlocked.contains(bundleID) else { return false }
		switch store.relockPolicy {
		case .afterQuit, .everyTime:
			return true
		case .afterFiveMinutesInBackground:
			guard let since = backgroundSince[bundleID] else { return true }
			if now.timeIntervalSince(since) >= Self.backgroundLimit {
				unlocked.remove(bundleID)
				backgroundSince.removeValue(forKey: bundleID)
				return false
			}
			return true
		}
	}

	/// Whether the shield must cover the app before it can be used.
	func needsShield(_ bundleID: String, now: Date = Date()) -> Bool {
		guard store.isLocked(bundleID) else { return false }
		if let at = unlockedAt[bundleID], now >= at, now.timeIntervalSince(at) < Self.unlockGrace { return false }
		return !isUnlocked(bundleID, now: now)
	}

	// MARK: - Face misses

	/// Failed face scans for the app since the last successful unlock.
	func faceMissCount(for bundleID: String) -> Int {
		faceMisses[bundleID, default: 0]
	}

	/// Whether the face is disabled for the app after too many misses, so
	/// only Use Password works until a password success clears the counter.
	func isFaceDisabled(_ bundleID: String) -> Bool {
		faceMissCount(for: bundleID) >= Self.maxFaceMisses
	}

	/// A face scan saw the user but never held a match. Scans that saw nobody
	/// do not count: walking away must not spend the face attempts.
	func recordFaceMiss(_ bundleID: String) {
		faceMisses[bundleID, default: 0] += 1
	}

	// MARK: - Events

	/// A face (or password) check passed for the app.
	func unlock(_ bundleID: String, now: Date = Date()) {
		guard store.isLocked(bundleID) else { return }
		unlocked.insert(bundleID)
		unlockedAt[bundleID] = now
		backgroundSince.removeValue(forKey: bundleID)
		// Both paths clear the miss counter: the face path can only run while
		// it is still enabled, so this is the password reset in practice.
		faceMisses.removeValue(forKey: bundleID)
	}

	/// The app became frontmost. Ends any background timing.
	func appDidActivate(_ bundleID: String, now: Date = Date()) {
		backgroundSince.removeValue(forKey: bundleID)
	}

	/// The app stopped being frontmost.
	///
	/// "Every time it opens" relocks here, at the moment it leaves the front,
	/// so the next activation always needs the face.
	func appDidResign(_ bundleID: String, now: Date = Date()) {
		guard unlocked.contains(bundleID) else { return }
		switch store.relockPolicy {
		case .everyTime:
			unlocked.remove(bundleID)
			backgroundSince.removeValue(forKey: bundleID)
			// Leaving on purpose ends the grace; the unlock's own window shuffle doesn't
			// resign the app, so this only runs when the person really switches away.
			unlockedAt.removeValue(forKey: bundleID)
		case .afterFiveMinutesInBackground:
			// First resign starts the clock; later ones must not restart it.
			if backgroundSince[bundleID] == nil {
				backgroundSince[bundleID] = now
			}
		case .afterQuit:
			break
		}
	}

	/// A process for the app started. A launch that began before the app was last
	/// unlocked is the one that was just unlocked, so it keeps its unlock.
	func appDidLaunch(_ bundleID: String, launchedAt: Date?) {
		if let launchedAt, let at = unlockedAt[bundleID], at >= launchedAt { return }
		appDidQuit(bundleID)
	}

	/// The app quit. A fresh launch is never unlocked, under any option.
	func appDidQuit(_ bundleID: String) {
		unlocked.remove(bundleID)
		unlockedAt.removeValue(forKey: bundleID)
		backgroundSince.removeValue(forKey: bundleID)
	}

	/// The Mac is going to sleep, or the screen locked: everything relocks.
	func systemDidSleep() {
		unlocked.removeAll()
		unlockedAt.removeAll()
		backgroundSince.removeAll()
	}

	func screenDidLock() {
		unlocked.removeAll()
		unlockedAt.removeAll()
		backgroundSince.removeAll()
	}
}
