import AppKit

enum BrowserAppLocator {
	@MainActor static func open(identifier: String, name: String, arguments: [String] = [], preferredURL: URL? = nil) async throws {
		let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(name + ".app")
		let candidates = [preferredURL, sibling, NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)].compactMap { $0 }
		guard let url = candidates.first(where: { (try? BrowserPeerTrust.verifyApplication($0, identifier: identifier)) != nil }) else {
			throw BrowserBridgeError.unavailable
		}
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = identifier == "com.gazeunlock.Passwords"
		configuration.arguments = arguments
		_ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
	}

	static func socketPath(_ name: String) -> String {
		URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gaze-browser/" + name).path
	}
}
