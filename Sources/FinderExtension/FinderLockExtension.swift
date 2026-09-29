import Cocoa
import FinderSync

/// The Finder Sync extension behind right-click Lock/Unlock with Gaze.
///
/// Sandboxed, so it never touches the locked-apps list except through the
/// shared app-group suite (via AppLockStore), and never toggles anything
/// itself: choosing the item opens a gaze:// URL and the app authorises the
/// change with face or password first.
@objc(FinderLockExtension)
final class FinderLockExtension: FIFinderSync {

	override init() {
		super.init()
		// /System/Applications too, for Messages, Photos, Notes and the like.
		var watched = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")]
		let homeApps = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Applications", isDirectory: true)
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: homeApps.path, isDirectory: &isDirectory),
			isDirectory.boolValue
		{
			watched.append(homeApps)
		}
		FIFinderSyncController.default().directoryURLs = Set(watched)
	}

	override func menu(for menuKind: FIMenuKind) -> NSMenu? {
		guard menuKind == .contextualMenuForItems else { return nil }
		let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
		guard selected.count == 1,
			let url = selected.first,
			let bundleID = FinderLockMenu.bundleID(forAppURL: url)
		else { return nil }
		let store = AppLockStore()
		guard
			let title = FinderLockMenu.title(
				selectedCount: 1, appBundleID: bundleID, isLocked: store.isLocked(bundleID))
		else { return nil }
		let menu = NSMenu()
		let item = NSMenuItem(title: title, action: #selector(toggleLock(_:)), keyEquivalent: "")
		item.target = self
		item.representedObject = bundleID
		menu.addItem(item)
		return menu
	}

	@objc private func toggleLock(_ sender: NSMenuItem) {
		guard let bundleID = sender.representedObject as? String,
			let url = FinderLockMenu.toggleURL(for: bundleID)
		else { return }
		NSWorkspace.shared.open(url)
	}
}
