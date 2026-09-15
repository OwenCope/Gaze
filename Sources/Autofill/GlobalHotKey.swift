import AppKit
import Carbon.HIToolbox
import os

/// A shortcut that fires while another app is frontmost.
///
/// Carbon, in 2026, and on purpose. The alternatives do not do this job:
/// `NSEvent.addGlobalMonitorForEvents` observes keys without consuming them, so the
/// shortcut would also reach the app underneath — pressing it in an editor would fill the
/// password *and* type a character. A `CGEventTap` can swallow the key but needs
/// Accessibility to exist at all and taps the entire keyboard to catch one combination,
/// which is a great deal of access for one shortcut.
///
/// `RegisterEventHotKey` is the API macOS actually provides for this: the shortcut is
/// registered with the window server, it consumes the event, and no other keystroke is
/// ever visible to this process. It is old and it is not deprecated.
@MainActor
final class GlobalHotKey {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "HotKey")

	/// `⌥⌘G`. Not configurable yet, and chosen to avoid collisions: `⌘G` is Find Again
	/// almost everywhere, and adding Option is a combination very little else claims.
	static let defaultKeyCode = UInt32(kVK_ANSI_G)
	static let defaultModifiers = UInt32(optionKey | cmdKey)

	/// The handler for the one hot key this class registers.
	///
	/// A global because the Carbon callback is a C function pointer: it cannot capture
	/// context, and the `userData` pointer it does offer would mean handing an unmanaged
	/// pointer to self across a boundary that has no way to tell us when it is done with
	/// it. One process registers one autofill shortcut, so one slot is enough.
	private static var action: (() -> Void)?

	private var hotKeyRef: EventHotKeyRef?
	private var handlerRef: EventHandlerRef?

	/// Whether the shortcut is actually held right now.
	///
	/// Surfaced in Settings rather than only logged. Registration fails for reasons the
	/// user can act on — another app holding ⌥⌘G is the common one — and a shortcut that
	/// quietly did not take is indistinguishable from a broken feature. It cost an evening
	/// to find that out the slow way once.
	private(set) var isRegistered = false

	/// Registers the shortcut. Replacing an existing registration is safe.
	func register(
		keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
		modifiers: UInt32 = GlobalHotKey.defaultModifiers,
		action: @escaping () -> Void
	) {
		unregister()
		Self.action = action

		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

		let handlerStatus = InstallEventHandler(
			GetApplicationEventTarget(),
			{ _, event, _ -> OSStatus in
				// Confirm it is ours before acting. The handler is installed on the
				// application event target, which other hot keys could also reach.
				var id = EventHotKeyID()
				let status = GetEventParameter(
					event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
					nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
				guard status == noErr, id.signature == GlobalHotKey.signature else { return noErr }

				// Carbon calls back on the main thread, but it does not know that in the
				// way the compiler needs, so the hop is stated.
				DispatchQueue.main.async { GlobalHotKey.action?() }
				return noErr
			},
			1, &eventType, nil, &handlerRef)

		guard handlerStatus == noErr else {
			Self.logger.error("Could not install the hot key handler (\(handlerStatus)).")
			return
		}

		let id = EventHotKeyID(signature: Self.signature, id: 1)
		let status = RegisterEventHotKey(
			keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)

		if status == noErr {
			isRegistered = true
			Self.logger.notice("Registered the autofill shortcut.")
		} else {
			// The usual cause is another app holding the same combination. Worth saying
			// out loud rather than leaving a shortcut that silently does nothing.
			Self.logger.error("Could not register the autofill shortcut (\(status)).")
		}
	}

	func unregister() {
		if let hotKeyRef {
			UnregisterEventHotKey(hotKeyRef)
			self.hotKeyRef = nil
		}
		if let handlerRef {
			RemoveEventHandler(handlerRef)
			self.handlerRef = nil
		}
		Self.action = nil
		isRegistered = false
	}

	/// `GAZE`, as a four-character code.
	private static let signature: OSType = 0x47415A45
}
