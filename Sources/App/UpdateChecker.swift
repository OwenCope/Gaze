import AppKit
import Foundation

/// Repo-reveal helper for the Settings About row, not an updater.
///
/// Despite the legacy name, this type never checks for updates: it only reports the running
/// version and reveals the checkout's source folder. Release checks live in
/// `ReleaseUpdateChecker`.
@MainActor
final class RepoRevealHelper {
	static let shared = RepoRevealHelper()

	var repositoryURL: URL? {
		var directory = Bundle.main.bundleURL.deletingLastPathComponent()
		for _ in 0..<5 {
			if FileManager.default.fileExists(atPath: directory.appending(path: ".git").path) {
				return directory
			}
			let parent = directory.deletingLastPathComponent()
			guard parent != directory else { break }
			directory = parent
		}
		return nil
	}

	var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
	}

	func revealRepository() {
		guard let repositoryURL else { return }
		NSWorkspace.shared.activateFileViewerSelecting([repositoryURL])
	}
}

/// Legacy name for `RepoRevealHelper`, kept so older call sites keep compiling.
typealias UpdateChecker = RepoRevealHelper
