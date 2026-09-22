import AppKit
import Security
import os

/// Who an application actually is, as opposed to who it says it is.
///
/// A bundle identifier is a claim, not an identity. Any app can ship any
/// `CFBundleIdentifier` it likes — it is a string in a plist, it is not signed as a
/// statement about *who built the app*, and nothing at runtime stops two applications on
/// the same Mac claiming to be `com.apple.Passwords`. Matching a saved password on that
/// string alone means the answer to "is this the password manager I saved?" is decided by
/// the thing being asked about.
///
/// The signature is the part that cannot be copied. A *designated requirement* is the code
/// signing system's own answer to "what counts as this program, including its future
/// updates" — normally the identifier plus the signing authority. Recording it when the
/// user saves a place, and checking the live process against it before typing, means an
/// impostor is rejected on the one attribute it cannot forge without the developer's key.
enum AppIdentity {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "AppIdentity")

	struct Selection: Equatable {
		let url: URL
		let bundleID: String
		let requirement: String
	}

	static func selection(forAppAt url: URL) -> Selection? {
		let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
		guard let bundleID = Bundle(url: resolved)?.bundleIdentifier,
			let requirement = designatedRequirement(forAppAt: resolved)
		else { return nil }
		return Selection(url: resolved, bundleID: bundleID, requirement: requirement)
	}

	static func designatedRequirement(forAppAt url: URL) -> String? {
		var staticCode: SecStaticCode?
		guard
			SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
			let staticCode,
			SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
				== errSecSuccess
		else { return nil }

		var requirement: SecRequirement?
		guard
			SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
			let requirement
		else {
			logger.notice("\(url.lastPathComponent, privacy: .public) has no designated requirement.")
			return nil
		}

		var text: CFString?
		guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else {
			return nil
		}
		return text as String?
	}

	/// Whether the running process is the program that requirement describes.
	///
	/// Addressed by pid, which is what `NSWorkspace` gives us for the frontmost app. That
	/// is a real limitation and worth naming: a pid identifies a process only for as long
	/// as it lives, so this answers "is the process holding this pid right now the right
	/// program", not "is it the same process the user was looking at a second ago". The
	/// caller re-reads the frontmost app after the face check for that reason; this closes
	/// the identity half, not the timing half.
	static func process(_ pid: pid_t, matches requirement: String) -> Bool {
		var parsed: SecRequirement?
		guard
			SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess,
			let parsed
		else {
			logger.error("Stored requirement does not parse; refusing to fill.")
			return false
		}

		let attributes = [kSecGuestAttributePid: pid] as CFDictionary
		var code: SecCode?
		guard
			SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
			let code
		else {
			logger.error("Could not identify process \(pid); refusing to fill.")
			return false
		}

		let status = SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), parsed)
		if status != errSecSuccess {
			logger.error("Process \(pid) does not satisfy the saved requirement (\(status)).")
		}
		return status == errSecSuccess
	}

	private static let browserHandlerLock = NSLock()
	private static var cachedBrowserHandlers: (identifiers: Set<String>, fetchedAt: Date)?
	private static let browserHandlerCacheTTL: TimeInterval = 60

	/// Bundle identifiers that can open http(s), cached briefly: `urlsForApplications`
	/// hits Launch Services and this runs on every frontmost-app check.
	private static func browserHandlerIdentifiers() -> Set<String>? {
		browserHandlerLock.lock()
		let cached = cachedBrowserHandlers
		browserHandlerLock.unlock()
		if let cached, Date().timeIntervalSince(cached.fetchedAt) < browserHandlerCacheTTL {
			return cached.identifiers
		}
		guard
			let http = URL(string: "http://example.com"),
			let https = URL(string: "https://example.com")
		else { return nil }
		var identifiers = Set<String>()
		for web in [http, https] {
			for url in NSWorkspace.shared.urlsForApplications(toOpen: web) {
				if let id = Bundle(url: url)?.bundleIdentifier?.lowercased() {
				identifiers.insert(id)
				}
			}
		}
		browserHandlerLock.lock()
		cachedBrowserHandlers = (identifiers, Date())
		browserHandlerLock.unlock()
		return identifiers
	}

	static func isBrowser(bundleID: String) -> Bool {
		let knownBrowsers: Set<String> = [
			"com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome",
			"com.google.chrome.canary", "org.mozilla.firefox", "org.mozilla.nightly",
			"com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera",
			"com.vivaldi.vivaldi", "company.thebrowser.browser", "company.thebrowser.dia",
		]
		if knownBrowsers.contains(bundleID.lowercased()) { return true }
		guard let handlers = browserHandlerIdentifiers() else { return true }
		return handlers.contains(bundleID.lowercased())
	}
}
