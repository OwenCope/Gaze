import Foundation
import Darwin

enum PasswordsBuild { static let isUIReview = true }

@main
struct BrowserSetupTests {
	static func main() throws {
		let home = FileManager.default.temporaryDirectory.appendingPathComponent("gaze-setup-test-\(UUID())")
		try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		defer { try? FileManager.default.removeItem(at: home) }
		var count = 0
		func check(_ success: Bool, _ name: String) { precondition(success, name); count += 1 }
		let data = try BrowserSetup.manifest(helper: "/synthetic/Gaze Passwords.app/Contents/Helpers/GazeBrowserBridge",
			extensionID: "dplcnjngbhocgeidhcgkiidilolbgadl")
		let components = ["Library", "Application Support", "SyntheticBrowser", "NativeMessagingHosts"]
		check(BrowserSetup.registrationURL(for: .browserOS, home: home).path == home.path + "/Library/Application Support/BrowserClaw/NativeMessagingHosts/com.gazeunlock.passwords.json",
			"connection recovery points to this browser's exact registration")
		try BrowserSetup.writeRegistration(data, home: home, components: components)
		let folder = components.reduce(home) { $0.appendingPathComponent($1) }
		let manifest = folder.appendingPathComponent("com.gazeunlock.passwords.json")
		check(try Data(contentsOf: manifest) == data, "atomic registration writes requested manifest")
		let permissions = try FileManager.default.attributesOfItem(atPath: manifest.path)[.posixPermissions] as? Int
		check(permissions == 0o600, "registration is user-only")
		try BrowserSetup.writeRegistration(data, home: home, components: components)
		check(try Data(contentsOf: manifest) == data, "matching registration is idempotent")
		let other = try BrowserSetup.manifest(helper: "/other/helper", extensionID: "dplcnjngbhocgeidhcgkiidilolbgadl")
		check((try? BrowserSetup.writeRegistration(other, home: home, components: components)) == nil, "conflicting registration is not overwritten")
		check(try Data(contentsOf: manifest) == data, "conflict preserves file bytes")
		check((try? BrowserSetup.writeRegistration(data, home: home, components: ["..", "escape"])) == nil, "path traversal rejected")
		check((try? BrowserSetup.writeRegistration(data, home: home, components: ["bad/path"])) == nil, "multi-component name rejected")
		let linked = home.appendingPathComponent("linked")
		try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: folder)
		check((try? BrowserSetup.writeRegistration(data, home: home, components: ["linked"])) == nil, "symlink directory rejected")
		let writable = home.appendingPathComponent("writable")
		try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: false)
		chmod(writable.path, 0o777)
		check((try? BrowserSetup.writeRegistration(data, home: home, components: ["writable"])) == nil, "world-writable parent rejected")
		try FileManager.default.removeItem(at: manifest)
		try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: home.appendingPathComponent("absent"))
		check((try? BrowserSetup.writeRegistration(data, home: home, components: components)) == nil, "dangling manifest symlink rejected")
		check(!FileManager.default.fileExists(atPath: home.appendingPathComponent("absent").path), "symlink target never created")
		check((try? BrowserSetup.manifest(helper: "relative", extensionID: "dplcnjngbhocgeidhcgkiidilolbgadl")) == nil, "relative helper path rejected")
		check((try? BrowserSetup.manifest(helper: "/helper", extensionID: "*")) == nil, "wildcard extension rejected")
		check((try? BrowserSetup.register(.chrome)) == nil, "UI review cannot install helper")
		let fakeBrowser = home.appendingPathComponent("Google Chrome.app", isDirectory: true)
		try FileManager.default.createDirectory(at: fakeBrowser, withIntermediateDirectories: false)
		check(BrowserSetup.verifiedBrowsers([.init(id: .chrome, application: fakeBrowser)]).isEmpty, "app filename alone cannot pass signature discovery")
		let moved = URL(fileURLWithPath: "/synthetic/Custom Browser Name.app")
		let fallback = URL(fileURLWithPath: "/synthetic/Applications/Google Chrome.app")
		let untrusted = URL(fileURLWithPath: "/synthetic/Impostor.app")
		var examined: [URL] = []
		let found = BrowserSetup.verifiedBrowsers([
			.init(id: .chrome, application: untrusted),
			.init(id: .chrome, application: untrusted),
			.init(id: .chrome, application: moved),
			.init(id: .chrome, application: fallback),
			.init(id: .brave, application: moved)
		]) { candidate in
			examined.append(candidate.application)
			return candidate.id == .chrome && [moved, fallback].contains(candidate.application)
		}
		check(found.count == 1 && found[0].id == .chrome && found[0].application == moved, "moved or renamed signed browser wins over fixed filename")
		check(examined.filter { $0 == untrusted }.count == 1, "duplicate rejected paths verified only once")
		check(!examined.contains(fallback), "one validated installation per browser")
		check(examined.filter { $0 == moved }.count == 2, "identity is verified independently for each browser label")
		let fallbackOnly = BrowserSetup.verifiedBrowsers([
			.init(id: .chrome, application: untrusted), .init(id: .chrome, application: fallback)
		]) { $0.application == fallback }
		check(fallbackOnly.first?.application == fallback, "invalid Launch Services candidate cannot hide a trusted fallback")
		var unsafeLookups = 0
		let unsafeCandidates = BrowserSetup.verifiedBrowsers([
			.init(id: .chrome, application: URL(string: "https://example.invalid/Browser.app")!),
			.init(id: .chrome, application: URL(fileURLWithPath: "/synthetic/not-an-app"))
		]) { _ in unsafeLookups += 1; return true }
		check(unsafeCandidates.isEmpty && unsafeLookups == 0, "nonlocal and nonbundle candidates skipped before verification")
		check(BrowserSetup.verifiedBrowsers([]).isEmpty, "no discovery candidates produces no choices")
		check((try? BrowserSetup.register(.chrome, application: moved)) == nil, "custom application URL cannot bypass UI-review registration guard")
		print("Browser setup: \(count) checks passed in temporary fixtures. No browser profile changed.")
	}
}
