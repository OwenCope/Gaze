import AppKit
import SwiftUI
import os

/// Setup, hanging out of the notch instead of in a window.
///
/// The argument for putting it here is not that it looks good, though it does. **The camera
/// is in the notch.** Enrolment in a window at the middle of the screen asks someone to
/// look at the middle of the screen while a lens six inches above photographs the top of
/// their head. Putting the panel directly under the lens means the thing you are looking at
/// and the thing looking at you are in the same place, and the captures come out framed the
/// way the unlock will see you.
///
/// Two things make this different from `NotchCapsuleController`, and both are why it is a
/// separate class rather than another phase of that one:
///
///   - **It takes keyboard input.** The capsule's window is deliberately unfocusable and
///     ignores the mouse; it is a status indicator that must never steal a click. This one
///     has buttons and a password field, so it has to become key.
///   - **It is much larger.** The capsule is sized to a status glyph. Setup needs room for
///     a camera preview, and the panel drops far enough to hold one.
///
/// The shape is the same `NotchPanelShape` the capsule uses, so the two read as the same
/// object doing different jobs rather than as two panels that happen to live in the notch.
@MainActor
final class SetupNotchController {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "SetupNotch")

	/// Wide enough for a camera preview and a line of prose at a comfortable measure.
	/// Much wider and the panel stops reading as something the notch produced.
	private static let panelWidth: CGFloat = 460
	private static let panelHeight: CGFloat = 440

	/// Unlike the capsule's window, this one can be focused — otherwise the password step
	/// would be a text field nobody can type into. `borderless` windows refuse key status
	/// by default, so it has to be said explicitly.
	private final class FocusableNotchWindow: NSWindow {
		override var canBecomeKey: Bool { true }
		override var canBecomeMain: Bool { true }
	}

	private var window: NSWindow?
	private var host: NSHostingView<AnyView>?
	private let store: FaceEnrollmentStore

	init(store: FaceEnrollmentStore) {
		self.store = store
	}

	var isShowing: Bool { window != nil }

	// MARK: - Presentation

	func show() {
		if window != nil {
			window?.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		guard let screen = NSScreen.main ?? NSScreen.screens.first else {
			Self.logger.error("No screen to hang setup from.")
			return
		}

		// The physical cutout's height, so the panel starts hidden behind it and grows
		// down — the same trick the capsule uses. On a Mac with no notch this is zero and
		// the panel simply drops from the top edge, which is the right fallback.
		let notchInset = screen.safeAreaInsets.top

		let size = CGSize(width: Self.panelWidth, height: Self.panelHeight + notchInset)
		let frame = NSRect(
			x: screen.frame.midX - size.width / 2,
			y: screen.frame.maxY - size.height,
			width: size.width,
			height: size.height)

		let window = FocusableNotchWindow(
			contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.level = .floating
		window.collectionBehavior = [.canJoinAllSpaces, .stationary]
		window.isReleasedWhenClosed = false

		let host = NSHostingView(
			rootView: AnyView(
				SetupNotchPanel(
					store: store,
					notchInset: notchInset,
					onFinish: { [weak self] in self?.hide() })))
		window.contentView = host

		self.window = window
		self.host = host

		window.makeKeyAndOrderFront(nil)
		// Without this the panel appears behind whatever the user was doing and cannot be
		// typed into, because an accessory app is not active until it says so.
		NSApp.activate(ignoringOtherApps: true)

		Self.logger.notice("Setup panel shown under the notch.")
	}

	func hide() {
		window?.orderOut(nil)
		window = nil
		host = nil
		Self.logger.notice("Setup panel dismissed.")
	}
}

/// What the panel actually draws: the existing setup flow, on the notch shape.
///
/// The flow itself is untouched. It was already a self-contained view with its own step
/// plan and its own progress row — the only thing that changes here is the container it
/// sits in, which is the point. A setup flow that had to be rewritten to move house would
/// have been the wrong shape to begin with.
private struct SetupNotchPanel: View {

	let store: FaceEnrollmentStore
	let notchInset: CGFloat
	let onFinish: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			// The band behind the physical cutout. Nothing is drawn in it — it exists so
			// the content below starts under the notch rather than behind it.
			Color.clear.frame(height: notchInset)

			SetupFlow(store: store, onFinish: onFinish)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background {
			NotchPanelShape(topRadius: 17, bottomRadius: 26)
				.fill(.black)
				.overlay {
					NotchPanelShape(topRadius: 17, bottomRadius: 26)
						.fill(.ultraThinMaterial)
						.opacity(0.35)
				}
		}
		.ignoresSafeArea()
	}
}
