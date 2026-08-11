import AppKit
import Foundation
import os

enum UnlockBackendKind: String, CaseIterable, Sendable {
	/// Recognition runs, but nothing is unlocked. The safe default and a usable way to
	/// test enrolment without touching system authentication at all.
	case none
	/// Kept only so an existing installation can read its saved preference and keep the
	/// recovery path alive. This backend is deliberately absent from `selectableCases`:
	/// routing the lock screen through it can leave the user with no way back in.
	case authPlugin
	/// The stored password is replayed into the login window as keystrokes.
	case keystroke

	/// Backends that are safe to offer in Settings.
	static let selectableCases: [UnlockBackendKind] = [.none, .keystroke]

	var title: String {
		switch self {
		case .none: return "Don't unlock (recognition only)"
		case .authPlugin: return "Authorization plugin"
		case .keystroke: return "Password replay"
		}
	}

	var detail: String {
		switch self {
		case .none:
			return "Recognise faces and report the result, but never unlock the Mac."
		case .authPlugin:
			// Corrected: the earlier wording said macOS "cannot run third-party plugins",
			// which is wrong — the plugin loads fine on a stock, SIP-enabled Mac with an
			// ordinary Development signature. What is mutually exclusive is Apple's
			// *modern* lock-screen UI and third-party plugins, and that is what costs
			// Touch ID.
			return """
				The system performs the unlock itself, so your password is never stored or \
				typed. Costs Touch ID and Apple Watch unlock on the lock screen: macOS \
				won't run its modern lock-screen UI and a third-party plugin at once.
				"""
		case .keystroke:
			return """
				Stores your account password and types it into the login window. Keeps \
				Touch ID working, but there is no custom lock-screen UI and your password \
				sits on disk in recoverable form.
				"""
		}
	}
}

protocol UnlockBackend: Sendable {
	var kind: UnlockBackendKind { get }
	/// Whether this backend can actually run right now.
	@MainActor func readiness() -> BackendReadiness
	/// Unlock the Mac. Only called after a match, a liveness pass and a lockout check.
	@MainActor func unlock() async throws
}

/// Refuses to let an embedder that cannot tell people apart drive real authentication.
///
/// Added after measurement, not theory: the first landmark embedder scored a completely
/// different person at 1.000, meaning it would have unlocked the Mac for anyone. A
/// recognition system that cannot reject is worse than no recognition system, because it
/// looks like security while providing none. Any embedder that hasn't demonstrated it can
/// discriminate is confined to recognition-only mode.
enum UnlockGuard {

	/// Embedders trusted to gate a real unlock.
	///
	/// Deliberately an allow-list. A new embedder is untrusted until someone has actually
	/// measured its false-accept behaviour on this machine and added it here.
	private static let trustedPrefixes = ["coreml:"]

	@MainActor
	static func embedderBlocker() -> BackendReadiness? {
		let identifier = Embedders.best().identifier
		guard !trustedPrefixes.contains(where: identifier.hasPrefix) else { return nil }
		return .unavailable(
			"“\(identifier)” can't reliably tell people apart, so it isn't allowed to unlock "
				+ "your Mac. Install a recognition model at Resources/FaceEmbedding.mlpackage.")
	}
}

enum BackendReadiness: Equatable {
	case ready
	/// Usable once the user does something — grant a permission, set a password.
	case needsSetup(String)
	/// Cannot work on this machine or is not built yet.
	case unavailable(String)
}

// MARK: - No-op

struct NoUnlockBackend: UnlockBackend {
	let kind = UnlockBackendKind.none
	@MainActor func readiness() -> BackendReadiness { .ready }
	@MainActor func unlock() async throws {}
}

// MARK: - Password replay

/// Types the stored account password into the login window.
///
/// This is what Sapphire does, and it is the weaker of the two paths: the password must
/// be recoverable by this process to be typed, so anything that can run as this user and
/// read the vault can recover it. It is here because it works without modifying system
/// authentication, and because it keeps Touch ID intact.
struct KeystrokeUnlockBackend: UnlockBackend {
	let kind = UnlockBackendKind.keystroke

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "Keystroke")

	@MainActor func readiness() -> BackendReadiness {
		if let blocker = UnlockGuard.embedderBlocker() { return blocker }
		guard PasswordVault.hasPassword else {
			return .needsSetup("Face ID needs your account password to unlock the Mac.")
		}
		guard AXIsProcessTrusted() else {
			return .needsSetup("Face ID needs Accessibility access to type your password.")
		}
		return .ready
	}

	@MainActor func unlock() async throws {
		guard let password = try PasswordVault.password() else {
			throw UnlockError.noPassword
		}
		guard let source = CGEventSource(stateID: .hidSystemState) else {
			throw UnlockError.eventSourceUnavailable
		}

		// The whole string goes in one Unicode packet rather than key-by-key: it is
		// faster, and it avoids interleaving with anything else reaching the field.
		var characters = Array(password.utf16)
		guard
			let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
			let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
		else {
			throw UnlockError.eventSourceUnavailable
		}
		keyDown.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
		keyUp.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
		keyDown.post(tap: .cghidEventTap)
		keyUp.post(tap: .cghidEventTap)

		// Return, to submit the field.
		CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
		CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)

		Self.logger.notice("Submitted password to the login window.")
	}
}

// MARK: - Authorization plugin

/// Authorises the unlock through a SecurityAgent plugin.
///
/// The plugin is a bundle in `/Library/Security/SecurityAgentPlugins/` that macOS loads
/// into the SecurityAgent process at the lock screen. It is the only sanctioned way to
/// put our own UI there and to have the *system* perform the unlock rather than us
/// replaying a password.
///
/// Installing it requires rewriting the `system.login.screensaver` authorization rule
/// from `use-login-window-ui` to `authenticate-session-owner-or-admin`, which drops the
/// lock screen onto the legacy code path. That is what costs Touch ID and Apple Watch
/// unlock — Apple's modern path does not load third-party plugins.
struct AuthPluginUnlockBackend: UnlockBackend {
	let kind = UnlockBackendKind.authPlugin

	static let pluginPath = "/Library/Security/SecurityAgentPlugins/FaceID.bundle"

	@MainActor func readiness() -> BackendReadiness {
		if let blocker = UnlockGuard.embedderBlocker() { return blocker }
		guard FileManager.default.fileExists(atPath: Self.pluginPath) else {
			return .needsSetup(
				"The Face ID authorization plugin isn't installed yet. Installing it needs "
					+ "administrator authentication and disables Touch ID on the lock screen.")
		}
		guard AuthorizationRules.screensaverUsesPlugins() else {
			return .needsSetup(
				"The plugin is installed but macOS isn't routing the lock screen through it.")
		}
		return .ready
	}

	@MainActor func unlock() async throws {
		// Nothing to do from this side. The plugin is already running inside
		// SecurityAgent and completes the authorization itself; this process only tells
		// it whether the face matched, over the XPC channel the plugin listens on.
		throw UnlockError.pluginNotBuilt
	}
}

enum UnlockError: LocalizedError {
	case noPassword
	case eventSourceUnavailable
	case pluginNotBuilt

	var errorDescription: String? {
		switch self {
		case .noPassword:
			return "No account password is stored."
		case .eventSourceUnavailable:
			return "Could not post keyboard events. Check Accessibility access."
		case .pluginNotBuilt:
			return "The authorization plugin isn't built yet — see Plugin/README.md."
		}
	}
}

// MARK: - Authorization database

enum AuthorizationRules {
	/// True when the lock screen still uses Apple's built-in UI, which excludes
	/// third-party plugins.
	static func screensaverUsesPlugins() -> Bool {
		var rights: CFDictionary?
		let status = "system.login.screensaver".withCString { name in
			AuthorizationRightGet(name, &rights)
		}
		guard status == errAuthorizationSuccess, let dict = rights as? [String: Any] else {
			return false
		}

		if let rule = dict["rule"] as? [String] {
			return !rule.contains("use-login-window-ui")
		}
		return false
	}
}
