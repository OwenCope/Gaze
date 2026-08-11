import AppKit
import SwiftUI
import os

/// Owns the lock screen capsule window.
///
/// The window is created when the screen locks and destroyed when it unlocks, rather than
/// kept around hidden. That matches how the space adoption works — a window has to exist
/// and be on screen before it can be moved into the lock screen space, since SkyLight
/// addresses it by window number.
@MainActor
final class NotchCapsuleController {

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "NotchCapsule")

	private var window: NSWindow?
	private var host: NSHostingView<AnyView>?
	private var contentSize: CGSize = .zero
	/// Height of the region hidden behind the physical cutout, so the glyph can be
	/// centred in the visible part rather than in the whole window.
	private var notchInset: CGFloat = 0

	/// One model for the panel's whole lifetime. Mutating it animates; replacing the
	/// hosting view's root would reset the view's state and animate nothing.
	private let model = NotchCapsuleModel()

	/// Refuses focus, which keeps it out of the lock screen's input path entirely.
	private final class UnfocusableWindow: NSWindow {
		override var canBecomeKey: Bool { false }
		override var canBecomeMain: Bool { false }
	}

	// MARK: - Presentation

	func show(phase: NotchCapsuleModel.Phase = .scanning) {
		model.phase = phase

		if let screen = NSScreen.main {
			model.prefersOpaque = WallpaperBrightness.isLight(on: screen)
		}

		if window == nil {
			build()
		}

		guard let window else { return }
		window.alphaValue = 1
		window.orderFrontRegardless()
		// After ordering in, never before: the window number does not exist until then.
		LockScreenSpace.shared.adopt(window)

		// The window itself does not fade — the panel grows out of the notch instead.
		// Fading the window would make the part behind the cutout briefly visible as a
		// ghost over the menu bar.
		// Expanded on a short delay, not on the next runloop turn.
		//
		// `DispatchQueue.main.async` fired before the hosting view had mounted, so the
		// change landed with nothing observing it and the panel stayed collapsed. The view
		// needs to exist and be on screen first; a frame or two is enough.
		model.isExpanded = false
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
			self?.model.isExpanded = true
		}
	}

	func update(phase: NotchCapsuleModel.Phase) {
		guard window != nil else { return }
		model.phase = phase
	}

	func hide(after delay: TimeInterval = 0) {
		guard let window else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
			guard let self else { return }

			// Retract into the notch, then tear the window down once it is out of sight.
			// The delay matches the spring in `NotchCapsule`; closing sooner would clip
			// the animation and the panel would vanish mid-retract.
			self.model.isExpanded = false

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				LockScreenSpace.shared.release(window)
				window.orderOut(nil)
				self?.window = nil
				self?.host = nil
			}
		}
	}

	// MARK: - Construction

	private func build() {
		guard let screen = NSScreen.main else { return }

		// Match the cutout exactly and hang directly off its bottom edge, so the panel
		// reads as the notch extending rather than a pill floating beneath it.
		// Falls back to a sensible pill on a screen with no notch.
		let notchHeight = NotchMetrics.height(on: screen)

		// Wider than the physical cutout on purpose.
		//
		// Matching the cutout exactly seemed right, but notch apps — Dynamic Lake among
		// them — draw a wider bar over that area, and a panel at the true cutout width
		// steps in narrower underneath it. The mismatch is what reads as wrong. This
		// matches the island those apps present rather than the hardware behind it.
		// Measured off Dynamic Lake's own panel: ~280pt across on a 179pt cutout.
		let notchWidth = (NotchMetrics.width(on: screen) ?? 180) * 1.56

		// The window spans the notch as well as the area below it, so the black runs
		// continuously from the physical cutout into the panel.
		//
		// Sitting it directly *below* the notch left a seam along the top edge: the
		// cutout is true black, the wallpaper behind the menu bar usually is not, and the
		// join between them read as a border. Overlapping removes the join entirely — the
		// part behind the cutout is simply never seen.
		// Also measured: the panel hangs ~66pt below the menu bar, not the 38 I guessed.
		// The short drop was what made it read as a stub rather than a panel.
		let dropHeight: CGFloat = 66
		let size = CGSize(width: notchWidth, height: notchHeight + dropHeight)

		let frame = NSRect(
			x: screen.frame.midX - size.width / 2,
			y: screen.frame.maxY - size.height,
			width: size.width,
			height: size.height)
		self.contentSize = size
		self.notchInset = notchHeight

		let window = UnfocusableWindow(
			contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.ignoresMouseEvents = true
		window.level = .mainMenu + 2
		window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		window.hidesOnDeactivate = false

		let host = NSHostingView(
			rootView: AnyView(
				NotchCapsule(
					model: model, width: size.width, height: size.height,
					notchInset: notchHeight)))
		host.frame = NSRect(origin: .zero, size: size)
		window.contentView = host

		self.window = window
		self.host = host

		if !LockScreenSpace.shared.isAvailable {
			Self.logger.notice("No lock screen space; capsule will only show when unlocked.")
		}
	}

	// No render(): the model drives the view, so there is nothing to rebuild.
}
