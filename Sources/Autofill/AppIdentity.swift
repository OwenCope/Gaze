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

	/// The designated requirement of the installed app with this bundle identifier.
	///
	/// Read from the copy on disk at the moment the user saves the place. Nil when the app
	/// is unsigned or cannot be found, and callers must treat that as "cannot be trusted"
	/// rather than "no constraint" — see `SavedApp.requirement`.
	static func designatedRequirement(forBundleID bundleID: String) -> String? {
		guard
			let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
		else {
			logger.notice("No installed app for \(bundleID, privacy: .public).")
			return nil
		}
		return designatedRequirement(forAppAt: url)
	}

	static func designatedRequirement(forAppAt url: URL) -> String? {
		var staticCode: SecStaticCode?
		guard
			SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
			let staticCode
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

		let status = SecCodeCheckValidity(code, [], parsed)
		if status != errSecSuccess {
			logger.error("Process \(pid) does not satisfy the saved requirement (\(status)).")
		}
		return status == errSecSuccess
	}

	/// Whether this app renders web content, and so cannot have a saved password bound to
	/// any particular website.
	///
	/// Asked of the system rather than kept as a list of names: the handlers registered for
	/// `https` are exactly the applications macOS is willing to open a web page in, which
	/// is the property that matters and stays right as browsers come and go.
	static func isBrowser(bundleID: String) -> Bool {
		browserBundleIDs.contains(bundleID.lowercased())
	}

	private static let browserBundleIDs: Set<String> = {
		guard let web = URL(string: "https://example.com") else { return [] }
		let handlers = NSWorkspace.shared.urlsForApplications(toOpen: web)
		return Set(
			handlers.compactMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() })
	}()
}
