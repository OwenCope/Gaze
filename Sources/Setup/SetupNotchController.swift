import AppKit
import SwiftUI
import os

/// Setup, hanging out of the notch.
///
/// The argument for putting it here is not that it looks good, though it does. **The camera
/// is in the notch.** Enrolment in a window at the middle of the screen asks someone to look
/// at the middle of the screen while a lens six inches above photographs the top of their
/// head. Directly under the lens, the thing you look at and the thing looking at you are in
/// the same place, and the captures come out framed the way the unlock will see you.
///
/// **The panel is sized per step, and that is the whole design.** The first attempt put the
/// window flow in a fixed box, which is not the same idea at a smaller size — every step got
/// a rectangle sized for the largest of them, so the intro sat in a mostly empty panel and
/// the capture was cramped in the same one. It also let the content dictate the window,
/// grew past the screen, and had no close control, which is how it became a trap.
///
/// Here the window springs between `SetupNotchStep.height` values as the step changes: 196
/// for the intro, 348 for enrolment, 158 for done. Coming out of the capture the panel
/// shrinks to a checkmark less than half the height it just was, and that shrink is most of
/// what makes it read as part of the notch rather than as a window near the top of the
/// screen.
@MainActor
final class SetupNotchController {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "SetupNotch")

	/// Matches `SetupNotchMetrics.resize` closely enough that the window and its contents
	/// look like one movement. It is a curve rather than a real spring — `NSWindow` frame
	/// animation has no spring — so the content's spring does the settling and this only
	/// has to not disagree with it.
	private static let resizeDuration: TimeInterval = 0.42

	/// A borderless window has no traffic lights, so Escape is the only way out. Without it
	/// this panel is a trap, which it was once already.
	private final class SetupPanelWindow: NSWindow {
		override var canBecomeKey: Bool { true }
		override var canBecomeMain: Bool { true }

		var onEscape: (() -> Void)?

		override func cancelOperation(_ sender: Any?) { onEscape?() }

		override func keyDown(with event: NSEvent) {
			if event.keyCode == 53 {
				onEscape?()
				return
			}
			super.keyDown(with: event)
		}
	}

	private var window: SetupPanelWindow?
	private var host: NSHostingView<AnyView>?
	private var model: SetupNotchModel?
	private var notchInset: CGFloat = 0

	private let store: FaceEnrollmentStore

	init(store: FaceEnrollmentStore) {
		self.store = store
	}

	var isShowing: Bool { window != nil }

	// MARK: - Presentation

	func show() {
		if let window {
			window.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		guard let screen = NSScreen.main ?? NSScreen.screens.first else {
			Self.logger.error("No screen to hang setup from.")
			return
		}

		// The physical cutout's height, so the panel starts behind it and grows downward.
		// Zero on a Mac without a notch, where it simply drops from the top edge — which is
		// the right fallback rather than a special case.
		notchInset = screen.safeAreaInsets.top

		let model = SetupNotchModel()
		self.model = model

		let window = SetupPanelWindow(
			contentRect: frame(for: model.step, on: screen),
			styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.level = .floating
		window.collectionBehavior = [.canJoinAllSpaces, .stationary]
		window.isReleasedWhenClosed = false
		window.onEscape = { [weak self] in self?.hide() }

		let host = NSHostingView(
			rootView: AnyView(
				SetupNotchPanel(
					store: store,
					model: model,
					notchInset: notchInset,
					onFinish: { [weak self] in self?.hide() })))
		// The content does not get to decide how big the window is. `SetupFlow`-era views
		// carry large intrinsic sizes, and `NSHostingView` publishes those through Auto
		// Layout — which is what grew the first version of this panel past the screen.
		host.translatesAutoresizingMaskIntoConstraints = true
		host.autoresizingMask = [.width, .height]
		host.frame = NSRect(origin: .zero, size: window.frame.size)
		window.contentView = host

		self.window = window
		self.host = host

		// Set after the window exists, so the first resize has something to move.
		model.onStepChange = { [weak self] step in
			self?.resize(to: step)
		}

		window.makeKeyAndOrderFront(nil)
		// An accessory app is not active until it says so, and an inactive app's window
		// cannot be typed into — which the password step needs.
		NSApp.activate(ignoringOtherApps: true)

		Self.logger.notice("Setup panel shown, step \(model.step.rawValue, privacy: .public).")
	}

	func hide() {
		window?.orderOut(nil)
		window = nil
		host = nil
		model = nil
		Self.logger.notice("Setup panel dismissed.")
	}

	// MARK: - Geometry

	/// Pinned to the top of the screen, centred, and as tall as the step needs.
	///
	/// The top edge never moves: `origin.y` falls as the height grows, so the panel appears
	/// to extend downward out of the notch rather than to slide up and down the screen.
	private func frame(for step: SetupNotchStep, on screen: NSScreen) -> NSRect {
		let height = step.height + notchInset
		return NSRect(
			x: screen.frame.midX - SetupNotchMetrics.width / 2,
			y: screen.frame.maxY - height,
			width: SetupNotchMetrics.width,
			height: height)
	}

	private func resize(to step: SetupNotchStep) {
		guard let window, let screen = window.screen ?? NSScreen.main else { return }
		let target = frame(for: step, on: screen)
		guard target != window.frame else { return }

		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.resizeDuration
			// Leaves quickly and arrives slowly, which is what makes the panel look like it
			// is settling into a size rather than being dragged to one.
			context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
			context.allowsImplicitAnimation = true
			window.animator().setFrame(target, display: true)
		}
	}
}

/// The panel's chrome: the notch shape, and the current step inside it.
private struct SetupNotchPanel: View {

	let store: FaceEnrollmentStore
	let model: SetupNotchModel
	let notchInset: CGFloat
	let onFinish: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			// The band behind the physical cutout. Deliberately empty — it exists so the
			// content starts below the notch rather than behind it.
			Color.clear.frame(height: notchInset)

			SetupNotchContent(store: store, model: model, onFinish: onFinish)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background {
			// The same shape the unlock capsule uses, so the two read as one object doing
			// two jobs rather than as two panels that both happen to live in the notch.
			NotchPanelShape(topRadius: 17, bottomRadius: 26)
				.fill(.black)
				.overlay {
					NotchPanelShape(topRadius: 17, bottomRadius: 26)
						.fill(.ultraThinMaterial)
						.opacity(0.3)
				}
		}
		.ignoresSafeArea()
	}
}
