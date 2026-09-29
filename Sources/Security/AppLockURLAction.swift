import Foundation

/// The Finder's `gaze://app-lock/toggle?bundle=<id>` link.
///
/// Parsing is pure; `perform` authorises with face or password first, since
/// locking or unlocking an app is a security change that must never happen
/// from a click alone. The URL parse mirrors FinderLockMenu on the extension
/// side, which cannot link this target.
enum AppLockURLAction {

	static func bundleID(from url: URL) -> String? {
		guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
			parts.scheme?.lowercased() == "gaze",
			parts.host?.lowercased() == "app-lock",
			parts.path == "/toggle"
		else { return nil }
		let bundleID = parts.queryItems?.first(where: { $0.name == "bundle" })?.value ?? ""
		return bundleID.isEmpty ? nil : bundleID
	}

	/// Toggles the lock, but only after authorisation. Returns whether the
	/// locked-apps list changed.
	@MainActor
	static func perform(
		url: URL, store: AppLockStore,
		authorize: (BiometricGate.Reason) async -> Bool = BiometricGate.require
	) async -> Bool {
		guard let bundleID = bundleID(from: url),
			!AppLockStore.isNeverLockable(bundleID)
		else { return false }
		guard await authorize(.toggleAppLock) else { return false }
		if store.isLocked(bundleID) {
			store.remove(bundleID)
		} else {
			guard store.add(bundleID) else { return false }
		}
		return true
	}
}
