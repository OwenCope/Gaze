import AppKit
import Darwin
import Security

enum SupportedPasswordBrowser: String, CaseIterable, Identifiable, Sendable {
	case browserOS = "BrowserOS", chrome = "Google Chrome", edge = "Microsoft Edge", brave = "Brave"
	var id: String { rawValue }
	var application: URL {
		let name = switch self {
		case .browserOS: "BrowserOS neo.app"
		case .chrome: "Google Chrome.app"
		case .edge: "Microsoft Edge.app"
		case .brave: "Brave Browser.app"
		}
		return URL(fileURLWithPath: "/Applications").appendingPathComponent(name)
	}
	var folder: [String] {
		switch self {
		case .browserOS: ["BrowserClaw"]
		case .chrome: ["Google", "Chrome"]
		case .edge: ["Microsoft Edge"]
		case .brave: ["BraveSoftware", "Brave-Browser"]
		}
	}
	var signature: (identifier: String, team: String) {
		switch self {
		case .browserOS: ("com.browseros.BrowserClaw", "8YMKWU47S5")
		case .chrome: ("com.google.Chrome", "EQHXZ8M8AV")
		case .edge: ("com.microsoft.edgemac", "UBF8T346G9")
		case .brave: ("com.brave.Browser", "KL8N8XSYF4")
		}
	}
}

enum BrowserSetup {
	struct DiscoveredBrowser: Identifiable, Sendable {
		let id: SupportedPasswordBrowser
		let application: URL
	}
	@MainActor static func discoveryCandidates() -> [DiscoveredBrowser] {
		SupportedPasswordBrowser.allCases.flatMap { browser in
			let located = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.signature.identifier)
			let userApplication = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
				.appendingPathComponent(browser.application.lastPathComponent)
			return ([located].compactMap { $0 } + [browser.application, userApplication])
				.map { DiscoveredBrowser(id: browser, application: $0.resolvingSymlinksInPath()) }
		}
	}
	static func verifiedBrowsers(_ candidates: [DiscoveredBrowser], isTrusted: (DiscoveredBrowser) -> Bool = BrowserSetup.isTrustedBrowser) -> [DiscoveredBrowser] {
		var seen = Set<String>()
		var accepted = Set<SupportedPasswordBrowser>()
		return candidates.filter { candidate in
			guard !accepted.contains(candidate.id), candidate.application.isFileURL,
				candidate.application.pathExtension.lowercased() == "app",
				seen.insert("\(candidate.id.rawValue):\(candidate.application.standardizedFileURL.path)").inserted,
				isTrusted(candidate) else { return false }
			accepted.insert(candidate.id)
			return true
		}
	}
	static var extensionFolder: URL? {
		guard let folder = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true) else { return nil }
		var directory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else { return nil }
		return folder
	}
	static func registrationURL(for browser: SupportedPasswordBrowser, home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
		(["Library", "Application Support"] + browser.folder + ["NativeMessagingHosts", "com.gazeunlock.passwords.json"])
			.reduce(home) { $0.appendingPathComponent($1) }
	}
	@MainActor static func openExtensions(for browser: DiscoveredBrowser) async throws {
		guard !PasswordsBuild.isUIReview else { throw SetupError.unavailable }
		try verifyBrowser(browser.id, application: browser.application)
		guard let url = URL(string: "chrome://extensions/") else { throw SetupError.unavailable }
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = true
		_ = try await NSWorkspace.shared.open([url], withApplicationAt: browser.application, configuration: configuration)
	}
	static func register(_ browser: SupportedPasswordBrowser, application: URL? = nil) throws {
		guard !PasswordsBuild.isUIReview else { throw SetupError.unavailable }
		try BrowserPeerTrust.verifyApplication(Bundle.main.bundleURL, identifier: "com.gazeunlock.Passwords")
		try verifyBrowser(browser, application: application ?? browser.application)
		guard let resources = Bundle.main.resourceURL else { throw SetupError.unavailable }
		let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/GazeBrowserBridge")
		try BrowserPeerTrust.verifyApplication(helper, identifier: "com.gazeunlock.Passwords.BrowserBridge")
		let identity = try JSONDecoder().decode(Identity.self, from: Data(contentsOf: resources.appendingPathComponent("BrowserIdentity.json")))
		let manifest = try manifest(helper: helper.path, extensionID: identity.extensionID)
		try writeRegistration(manifest, home: URL(fileURLWithPath: NSHomeDirectory()),
			components: ["Library", "Application Support"] + browser.folder + ["NativeMessagingHosts"])
	}
	private static func isTrustedBrowser(_ browser: DiscoveredBrowser) -> Bool {
		(try? verifyBrowser(browser.id, application: browser.application)) != nil
	}
	private static func verifyBrowser(_ browser: SupportedPasswordBrowser, application: URL) throws {
		guard application.isFileURL, application.pathExtension.lowercased() == "app" else { throw SetupError.unavailable }
		var code: SecStaticCode?
		var requirement: SecRequirement?
		let text = "anchor apple generic and identifier \"\(browser.signature.identifier)\" and certificate leaf[subject.OU] = \"\(browser.signature.team)\""
		guard SecStaticCodeCreateWithPath(application as CFURL, [], &code) == errSecSuccess, let code,
			SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
			SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { throw SetupError.unavailable }
	}

	static func manifest(helper: String, extensionID: String) throws -> Data {
		guard helper.hasPrefix("/"), !helper.contains("\0"),
			extensionID.range(of: "^[a-p]{32}$", options: .regularExpression) != nil else { throw SetupError.unavailable }
		return try JSONSerialization.data(withJSONObject: [
			"name": "com.gazeunlock.passwords", "description": "Gaze Passwords browser bridge",
			"path": helper, "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"]
		], options: [.sortedKeys])
	}

	static func writeRegistration(_ data: Data, home: URL, components: [String]) throws {
		guard data.count <= 16_384, !components.isEmpty,
			components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") }) else { throw SetupError.unavailable }
		var directory = open(home.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard directory >= 0 else { throw SetupError.unsafeLocation }
		defer { close(directory) }
		try validateDirectory(directory)
		for component in components {
			if mkdirat(directory, component, 0o700) != 0 && errno != EEXIST { throw SetupError.unsafeLocation }
			let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard next >= 0 else { throw SetupError.unsafeLocation }
			do { try validateDirectory(next) } catch { close(next); throw error }
			close(directory)
			directory = next
		}
		let name = "com.gazeunlock.passwords.json"
		let existing = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
		if existing >= 0 {
			defer { close(existing) }
			var metadata = stat()
			guard fstat(existing, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
				metadata.st_uid == geteuid(), metadata.st_mode & 0o022 == 0,
				metadata.st_size > 0, metadata.st_size <= 16_384 else { throw SetupError.unsafeLocation }
			var bytes = [UInt8](repeating: 0, count: Int(metadata.st_size))
			let count = bytes.withUnsafeMutableBytes { read(existing, $0.baseAddress, $0.count) }
			guard count == bytes.count,
				let current = try JSONSerialization.jsonObject(with: Data(bytes)) as? NSDictionary,
				let expected = try JSONSerialization.jsonObject(with: data) as? NSDictionary,
				current == expected else { throw SetupError.existingRegistration }
			return
		}
		guard errno == ENOENT else { throw SetupError.unsafeLocation }
		let temporary = ".gaze-\(UUID().uuidString).tmp"
		let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard file >= 0 else { throw SetupError.unsafeLocation }
		defer { close(file); unlinkat(directory, temporary, 0) }
		try data.withUnsafeBytes { bytes in
			var offset = 0
			while offset < bytes.count {
				let count = write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
				if count < 0 && errno == EINTR { continue }
				guard count > 0 else { throw SetupError.unsafeLocation }
				offset += count
			}
		}
		guard fsync(file) == 0 else { throw SetupError.unsafeLocation }
		guard linkat(directory, temporary, directory, name, 0) == 0 else { throw SetupError.existingRegistration }
	}

	private static func validateDirectory(_ descriptor: Int32) throws {
		var info = stat()
		guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
			info.st_mode & 0o022 == 0 else { throw SetupError.unsafeLocation }
	}
	private struct Identity: Decodable { let extensionID: String }
	enum SetupError: LocalizedError {
		case unavailable, unsafeLocation, existingRegistration
		var errorDescription: String? {
			switch self {
			case .unavailable: "Use the signed Gaze Passwords app and a supported, signed browser. Reopen Settings or refresh the browser list after installing or moving a browser."
			case .unsafeLocation: "The browser setup folder could not be updated safely. Nothing was overwritten."
			case .existingRegistration: "A different Gaze helper is already registered. Nothing was overwritten. Review the existing browser helper before reconnecting."
			}
		}
	}
}
