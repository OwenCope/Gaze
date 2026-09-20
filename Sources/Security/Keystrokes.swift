import AppKit
import CoreGraphics

enum Keystrokes {
	enum PreparationError: LocalizedError {
		case emptyPassword, unsupportedControlCharacter, eventUnavailable, incompletePayload

		var errorDescription: String? {
			switch self {
			case .emptyPassword: "The saved account password is empty. Save it again in Settings."
			case .unsupportedControlCharacter:
				"This password contains a control character that Gaze cannot safely type. Use macOS authentication."
			case .eventUnavailable: "Gaze could not prepare keyboard input. No password was submitted."
			case .incompletePayload: "The keyboard event could not hold the full password. Use macOS authentication."
			}
		}
	}

	static func passwordEvents(
		_ password: String,
		makeSource: () -> CGEventSource? = { CGEventSource(stateID: .privateState) },
		makeEvent: (CGEventSource, CGKeyCode, Bool) -> CGEvent? = {
			CGEvent(keyboardEventSource: $0, virtualKey: $1, keyDown: $2)
		}
	) throws -> [CGEvent] {
		guard !password.isEmpty else { throw PreparationError.emptyPassword }
		guard !password.unicodeScalars.contains(where: {
			$0.value < 0x20 || (0x7F...0x9F).contains($0.value)
		}) else { throw PreparationError.unsupportedControlCharacter }
		guard let source = makeSource(),
			let textDown = makeEvent(source, 0, true),
			let textUp = makeEvent(source, 0, false),
			let returnDown = makeEvent(source, 36, true),
			let returnUp = makeEvent(source, 36, false)
		else { throw PreparationError.eventUnavailable }

		let events = [textDown, textUp, returnDown, returnUp]
		for event in events {
			event.flags = []
			event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
		}
		var characters = Array(password.utf16)
		textDown.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
		var copied = [UniChar](repeating: 0, count: characters.count)
		var copiedCount = 0
		textDown.keyboardGetUnicodeString(
			maxStringLength: copied.count, actualStringLength: &copiedCount, unicodeString: &copied)
		guard copiedCount == characters.count, copied == characters else {
			throw PreparationError.incompletePayload
		}
		return events
	}
}
