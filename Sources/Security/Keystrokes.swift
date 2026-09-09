import AppKit
import CoreGraphics

/// Synthesised keyboard input.
///
/// Extracted from `KeystrokeUnlockBackend`, which had the only copy. Autofill needs the
/// same thing — put a secret into whatever field has focus — and two separately maintained
/// implementations of "type a password" is not a duplication worth having: a fix to one
/// (a modifier left stuck down, a string that needs splitting) would silently not reach
/// the other.
///
/// Every function here needs Accessibility. Callers check `AXIsProcessTrusted()` and say
/// something useful; these just post.
enum Keystrokes {

	/// Virtual key codes. Positional, so they mean the same thing on any keyboard layout —
	/// which matters, because the character a key produces does not.
	enum Key: CGKeyCode {
		case tab = 48
		case ret = 36
	}

	/// Types a string in one packet.
	///
	/// The whole string goes in a single Unicode event rather than key by key. It is
	/// faster, and — the reason it is done this way — nothing can interleave with it. A
	/// per-character loop leaves gaps that another event source can post into, which for a
	/// password field means characters landing out of order or somewhere else entirely.
	static func type(_ string: String) {
		guard !string.isEmpty, let source = CGEventSource(stateID: .hidSystemState) else { return }
		var characters = Array(string.utf16)
		guard
			let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
			let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
		else { return }

		down.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
		up.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
		down.post(tap: .cghidEventTap)
		up.post(tap: .cghidEventTap)
	}

	/// Presses and releases one key.
	static func press(_ key: Key) {
		guard let source = CGEventSource(stateID: .hidSystemState) else { return }
		CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)?
			.post(tap: .cghidEventTap)
		CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)?
			.post(tap: .cghidEventTap)
	}
}
