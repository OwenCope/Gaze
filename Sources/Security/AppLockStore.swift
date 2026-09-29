import Foundation

/// When a locked app locks again after a successful unlock.
///
/// The titles are the future Settings picker labels, written the way Apple
/// would: what happens, in plain words.
enum AppLockRelockPolicy: String, CaseIterable, Sendable {
	/// The app stays unlocked until it quits, the Mac locks, or it sleeps.
	case afterQuit
	/// The app relocks after 5 minutes in the background.
	case afterFiveMinutesInBackground
	/// The app relocks every time it stops being frontmost.
	case everyTime

	var title: String {
		switch self {
		case .afterQuit: return "After quitting"
		case .afterFiveMinutesInBackground: return "After 5 minutes in the background"
		case .everyTime: return "Every time it opens"
		}
	}
}

/// The persisted set of bundle IDs locked by App Lock.
///
/// Lives in the standard defaults and is mirrored to the app-group suite
/// `group.com.gazeunlock.Gaze`, so a future Finder extension reading only the
/// shared suite agrees with the app. Every mutation writes both; reads come
/// from the standard defaults, adopting the shared suite once when it holds
/// values the app has never seen (for example set by the extension first).
///
/// Self-contained on purpose: the test suite compiles this file standalone,
/// so it touches nothing else in the app.
final class AppLockStore {

	static let appGroupID = "group.com.gazeunlock.Gaze"

	/// Apps that can never be locked or shielded, whatever is asked for.
	///
	/// Locking Gaze itself would lock the unlock path; Finder and System
	/// Settings are the Mac's own furniture; the login window is not an app
	/// at all. All four are refused by `add(_:)` and read as unlocked by
	/// `isLocked(_:)` even if they somehow end up in storage.
	static let neverLockable: Set<String> = [
		"com.gazeunlock.Gaze",
		"com.apple.finder",
		"com.apple.systempreferences",
		"com.apple.loginwindow",
	]

	static func isNeverLockable(_ bundleID: String) -> Bool {
		neverLockable.contains(bundleID)
	}

	private enum Key {
		static let lockedApps = "appLockLockedApps"
		static let relockPolicy = "appLockRelockPolicy"
		static let isEnabled = "appLockEnabled"
	}

	private let defaults: UserDefaults
	private let groupDefaults: UserDefaults?

	init(
		defaults: UserDefaults = .standard,
		groupDefaults: UserDefaults? = UserDefaults(suiteName: AppLockStore.appGroupID)
	) {
		self.defaults = defaults
		self.groupDefaults = groupDefaults
		// Adopt values written to the shared suite before this app ever saved
		// any — the Finder side may get there first.
		if defaults.object(forKey: Key.lockedApps) == nil,
			let shared = groupDefaults?.stringArray(forKey: Key.lockedApps),
			!shared.isEmpty {
			defaults.set(shared, forKey: Key.lockedApps)
		}
	}

	/// Every locked bundle ID, never including the never-lockable list.
	var lockedBundleIDs: Set<String> {
		get {
			let stored = defaults.stringArray(forKey: Key.lockedApps) ?? []
			return Set(stored).subtracting(Self.neverLockable)
		}
		set {
			let sorted = Array(Set(newValue).subtracting(Self.neverLockable)).sorted()
			defaults.set(sorted, forKey: Key.lockedApps)
			groupDefaults?.set(sorted, forKey: Key.lockedApps)
		}
	}

	/// The shared-suite copy, for the future Finder extension's side.
	var mirroredBundleIDs: Set<String> {
		Set(groupDefaults?.stringArray(forKey: Key.lockedApps) ?? [])
	}

	/// Which "Lock again" option is in force. After quitting by default.
	var relockPolicy: AppLockRelockPolicy {
		get {
			defaults.string(forKey: Key.relockPolicy)
				.flatMap(AppLockRelockPolicy.init(rawValue:)) ?? .afterQuit
		}
		set {
			defaults.set(newValue.rawValue, forKey: Key.relockPolicy)
			groupDefaults?.set(newValue.rawValue, forKey: Key.relockPolicy)
		}
	}

	/// Whether App Lock is on at all. Off by default; the list below it is kept
	/// either way so turning it off never loses the chosen apps.
	var isEnabled: Bool {
		get { defaults.bool(forKey: Key.isEnabled) }
		set {
			defaults.set(newValue, forKey: Key.isEnabled)
			groupDefaults?.set(newValue, forKey: Key.isEnabled)
		}
	}

	func isLocked(_ bundleID: String) -> Bool {
		!Self.isNeverLockable(bundleID) && lockedBundleIDs.contains(bundleID)
	}

	/// Locks an app. Returns false, changing nothing, for never-lockable apps.
	@discardableResult
	func add(_ bundleID: String) -> Bool {
		guard !bundleID.isEmpty, !Self.isNeverLockable(bundleID) else { return false }
		var current = lockedBundleIDs
		current.insert(bundleID)
		lockedBundleIDs = current
		return true
	}

	func remove(_ bundleID: String) {
		var current = lockedBundleIDs
		current.remove(bundleID)
		lockedBundleIDs = current
	}
}
