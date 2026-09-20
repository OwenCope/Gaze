import AppKit
import Foundation

@MainActor
final class UpdateChecker {
	static let shared = UpdateChecker()

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
