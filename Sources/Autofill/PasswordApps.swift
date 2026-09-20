import AppKit
import os

/// Finds the password managers already installed on this Mac.
///
/// The reason Places exists at all is almost always a password manager: the app you most
/// want to unlock by looking at it is the one holding everything else. Making the user
/// hunt through their Applications folder for it first is the wrong first run.
///
/// **How they are found.** Not by a hardcoded list of bundle identifiers. A list is wrong
/// the moment somebody installs a manager that was not on it, silently — no error, just a
/// suggestion that never appears — and maintaining one means guessing at identifiers for
/// apps nobody here has installed.
///
/// Instead: every credential manager on macOS ships an **AutoFill credential provider
/// extension**, because that is the only way to appear in Passwords settings and offer
/// fills to Safari. That extension declares itself in its `Info.plist` with a fixed
/// extension point identifier. So an app that can hold your passwords is an app with that
/// appex inside it, and that is a fact about the app rather than a fact about our list.
///
/// The scan is the filesystem rather than `pluginkit`, which indexes the same thing:
/// spawning a subprocess from a security app to read plists it can read itself is a worse
/// trade than a few dozen small file reads.
///
/// A short curated list covers the exceptions — Apple's own apps do not register a
/// third-party credential extension, because they *are* the system's provider. Those are
/// verified identifiers, not guesses.
enum PasswordApps {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "PasswordApps")

	/// The extension point every third-party credential manager declares.
	private static let credentialProviderPoint =
		"com.apple.authentication-services-credential-provider-ui"

	/// Apple's own, which never appear in the scan above because they *are* the system's
	/// provider rather than a third party registering with it.
	///
	/// Passwords only. Keychain Access was here and was removed: its prompts are
	/// system-modal SecurityAgent dialogs, not app text fields, so the Accessibility path
	/// this feature is built on cannot reach them. Suggesting it would be offering
	/// something that does not work.
	private static let builtIn = [
		"com.apple.Passwords"
	]

	struct Suggestion: Identifiable, Hashable {
		var id: String { bundleID }
		let bundleID: String
		let name: String
		let url: URL
	}

	/// Installed password managers, minus anything already saved.
	///
	/// Sorted by name so the list does not reorder itself between launches depending on
	/// what order the filesystem handed the apps over in.
	static func suggestions(excluding saved: [String]) -> [Suggestion] {
		var found: [String: Suggestion] = [:]

		for directory in searchDirectories() {
			guard
				let contents = try? FileManager.default.contentsOfDirectory(
					at: directory, includingPropertiesForKeys: nil,
					options: [.skipsHiddenFiles, .skipsPackageDescendants])
			else { continue }

			for url in contents where url.pathExtension == "app" {
				guard let bundle = Bundle(url: url),
					let bundleID = bundle.bundleIdentifier,
					hasCredentialProvider(at: url)
				else { continue }
				found[bundleID] = Suggestion(bundleID: bundleID, name: displayName(of: bundle, url: url), url: url)
			}
		}

		for bundleID in builtIn {
			guard found[bundleID] == nil,
				let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
				let bundle = Bundle(url: url)
			else { continue }
			found[bundleID] = Suggestion(bundleID: bundleID, name: displayName(of: bundle, url: url), url: url)
		}

		let savedSet = Set(saved)
		return
			found
			.filter { !savedSet.contains($0.key) }
			.map(\.value)
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	// MARK: - Scanning

	/// `/Applications`, the user's own, and the subfolder Setapp and similar install into.
	/// Not the whole disk: a recursive search for an appex is a lot of I/O to run behind a
	/// settings pane.
	private static func searchDirectories() -> [URL] {
		var directories = [URL(fileURLWithPath: "/Applications")]
		if let home = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
			.first
		{
			directories.append(home)
		}
		directories.append(URL(fileURLWithPath: "/Applications/Setapp"))
		return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
	}

	private static func hasCredentialProvider(at appURL: URL) -> Bool {
		let plugIns = appURL.appendingPathComponent("Contents/PlugIns")
		guard
			let extensions = try? FileManager.default.contentsOfDirectory(
				at: plugIns, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return false }

		for url in extensions where url.pathExtension == "appex" {
			guard let bundle = Bundle(url: url),
				let extensionInfo = bundle.object(forInfoDictionaryKey: "NSExtension")
					as? [String: Any],
				let point = extensionInfo["NSExtensionPointIdentifier"] as? String
			else { continue }
			if point == credentialProviderPoint { return true }
		}
		return false
	}

	private static func displayName(of bundle: Bundle, url: URL) -> String {
		(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
			?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
			?? url.deletingPathExtension().lastPathComponent
	}
}
