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

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "NotchCapsule")
	private static let horizontalInset: CGFloat = 20

	/// Asked of the window server rather than remembered, for the diagnostic line below.
	private static func screenIsLocked() -> Bool {
		guard
			let session = CGSessionCopyCurrentDictionary() as? [String: Any],
			let locked = session["CGSSessionScreenIsLocked"] as? Bool
		else { return false }
		return locked
	}

	private var window: NSWindow?
	private var host: NSHostingView<AnyView>?
	private var expansionTask: Task<Void, Never>?
	private var dismissalTask: Task<Void, Never>?
	private var contentSize: CGSize = .zero
	private var builtChallengeRoom: CGFloat = 0
	/// Height of the region hidden behind the physical cutout, so the glyph can be
	/// centred in the visible part rather than in the whole window.
	private var notchInset: CGFloat = 0

	/// One model for the panel's whole lifetime. Mutating it animates; replacing the
	/// hosting view's root would reset the view's state and animate nothing.
	private let model = NotchCapsuleModel()

	/// Last build outcome, so the missing-space state is readable from Settings diagnostics rather than the log alone.
	private(set) static var lastBuildOutcome: (message: String, at: Date)?

	/// Refuses focus, which keeps it out of the lock screen's input path entirely.
	private final class UnfocusableWindow: NSWindow {
		override var canBecomeKey: Bool { false }
		override var canBecomeMain: Bool { false }
	}

	// MARK: - Presentation

	func show(phase: NotchCapsuleModel.Phase = .scanning) {
		dismissalTask?.cancel()
		model.phase = phase

		if let screen = NSScreen.main {
			model.prefersOpaque = WallpaperBrightness.isLight(on: screen)
		}
		model.style = Preferences.shared.notchStyle
		model.shape = Preferences.shared.panelShape
		model.glyphPlacement = Preferences.shared.glyphPlacement
		model.transparency = Preferences.shared.notchTransparency
		model.showsCaptions = Preferences.shared.showNotchCaptions

		let needsMount = window == nil
		if needsMount {
			model.isExpanded = false
			build()
		}

		guard let window else { return }
		if !needsMount, let screen = NSScreen.main {
			let next = geometry(on: screen)
			if next.challengeRoom != builtChallengeRoom {
				window.setFrame(next.windowFrame, display: true)
				host?.frame = NSRect(origin: .zero, size: next.windowFrame.size)
				contentSize = next.contentSize
				notchInset = next.notchInset
				builtChallengeRoom = next.challengeRoom
			}
		}
		window.alphaValue = 1
		window.orderFrontRegardless()
		Self.logger.notice(
			"show: window \(window.windowNumber) level \(window.level.rawValue) visible \(window.isVisible) locked \(Self.screenIsLocked())"
		)
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
		if needsMount {
			expansionTask = Task { [weak self, weak window] in
				do {
					try await Task.sleep(for: .milliseconds(60))
				} catch { return }
				guard let self, let window, self.window === window else { return }
				self.model.isExpanded = true
				self.expansionTask = nil
			}
		} else if expansionTask == nil {
			model.isExpanded = true
		}
	}

	func update(phase: NotchCapsuleModel.Phase) {
		guard window != nil else { return }
		model.phase = phase
		model.showsCaptions = Preferences.shared.showNotchCaptions
	}

	var canPresentGuidance: Bool {
		window?.isVisible == true && model.isExpanded && LockScreenSpace.shared.isAvailable
	}

	func hide(after delay: TimeInterval = 0) {
		dismissalTask?.cancel()
		guard let window else { return }
		dismissalTask = Task { [weak self, weak window] in
			do {
				try await Task.sleep(for: .seconds(max(0, delay)))
			} catch { return }
			guard let self, let window, self.window === window else { return }

			self.expansionTask?.cancel()
			self.expansionTask = nil
			self.model.isExpanded = false

			let teardownDelay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
				? NotchAnimation.reducedDuration + 0.06 : NotchAnimation.teardownDelay
			do {
				try await Task.sleep(for: .seconds(teardownDelay))
			} catch { return }
			guard self.window === window else { return }
			LockScreenSpace.shared.release(window)
			window.orderOut(nil)
			self.window = nil
			self.host = nil
			self.dismissalTask = nil
		}
	}

	// MARK: - Construction

	private func geometry(on screen: NSScreen) -> (
		windowFrame: NSRect, contentSize: CGSize, notchInset: CGFloat, challengeRoom: CGFloat
	) {
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
			+ Preferences.shared.notchWidthAdjust

		// The window spans the notch as well as the area below it, so the black runs
		// continuously from the physical cutout into the panel.
		//
		// Sitting it directly *below* the notch left a seam along the top edge: the
		// cutout is true black, the wallpaper behind the menu bar usually is not, and the
		// join between them read as a border. Overlapping removes the join entirely — the
		// part behind the cutout is simply never seen.
		// Also measured: the panel hangs ~66pt below the menu bar, not the 38 I guessed.
		// The short drop was what made it read as a stub rather than a panel.
		// The island is a separate object below the housing, so the window has to carry the
		// gap and the island's own height on top of what an attached drop needs — plus room
		// underneath for its shadow.
		//
		// With the window ending exactly where the island ends, the shadow was clipped flat
		// against the bottom edge and drew a straight line across the wallpaper. That line is
		// precisely how you can tell a floating object is really a window. `islandSide` is
		// capped on width, so the extra height stays empty margin rather than making the
		// island taller.
		let hasNotch = NotchMetrics.hasNotch(on: screen)
		let isIsland = Preferences.shared.panelShape == .island
		let isDynamicIsland = Preferences.shared.panelShape == .dynamicIsland
		let isEarFlank =
			Preferences.shared.panelShape == .attached
			&& Preferences.shared.glyphPlacement == .ear && hasNotch
		let cutout = NotchMetrics.width(on: screen) ?? 180
		// Always reserved, captions or not. Tying this to the captions toggle made the
		// panel a third shorter for anyone who turned captions off, and the owner's
		// call is that the panel keeps its size — the toggle hides words, it does not
		// shrink the thing. Do not make this conditional again.
		//
		// The island, the dynamic island and the ear flank carry their captions inline,
		// so none reserves room below.
		let challengeRoom: CGFloat = (isIsland || isDynamicIsland || isEarFlank) ? 0 : 30
		// The dynamic island's expanded state is up to 340 x 44 below a 6pt gap, plus
		// shadow room underneath — mirrors DynamicIslandMetrics in NotchCapsule,
		// which this file cannot see (it is private to the view).
		let dropHeight =
			(isIsland ? IslandMetrics.dropHeight(cutoutWidth: cutout)
				: isDynamicIsland ? (6 + 44 + IslandMetrics.shadowRoom)
				: isEarFlank ? 8 : 66)
			+ challengeRoom
			+ Preferences.shared.notchHeightAdjust
		// The ear flank widens its face side to fit a caption (EarFlankMetrics in
		// NotchCapsule: 54pt flank, 6pt gap, up to 170pt of words, 4pt padding) and
		// stays centred on the cutout, so the window holds that on both sides. The
		// dynamic island morphs to a fixed 340pt when open.
		let contentWidth =
			isDynamicIsland ? max(notchWidth, 340)
			: isEarFlank ? max(notchWidth, cutout + 2 * (54 + 6 + 170 + 4)) : notchWidth
		let panelFrame = NotchMetrics.panelFrame(
			size: CGSize(width: contentWidth, height: notchHeight + dropHeight),
			screenFrame: screen.frame,
			scale: screen.backingScaleFactor)
		let size = panelFrame.size
		let frame = panelFrame.insetBy(dx: -Self.horizontalInset, dy: 0)
		return (frame, size, notchHeight, challengeRoom)
	}

	private func build() {
		guard let screen = NSScreen.main else { return }

		let next = geometry(on: screen)
		let notchHeight = next.notchInset
		let size = next.contentSize
		let frame = next.windowFrame
		let windowSize = frame.size
		self.contentSize = size
		self.notchInset = notchHeight
		self.builtChallengeRoom = next.challengeRoom

		let window = UnfocusableWindow(
			contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.ignoresMouseEvents = true
		// Above other notch apps, not below them.
		//
		// This was `.mainMenu + 2` — level 26 — while Dynamic Lake draws its bar at 104. On
		// the lock screen that put their bar over ours, which was survivable for the attached
		// panel and the island because both hang *below* the band and the part underneath
		// still showed. In ear mode nothing hangs below: the padlock and the mark both live
		// inside the menu bar band, so the whole indicator disappeared under their bar and
		// selecting "on the ear" looked like it did nothing at all.
		//
		// This window only exists while the screen is locked, and for those few seconds its
		// status is the thing worth seeing.
		window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 4)
		window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		window.hidesOnDeactivate = false

		let host = NSHostingView(
			rootView: AnyView(
				NotchCapsule(
					model: model, width: size.width, height: size.height,
					notchInset: notchHeight,
					cutoutWidth: NotchMetrics.width(on: screen) ?? 180,
					hasNotch: NotchMetrics.hasNotch(on: screen))
					.frame(width: windowSize.width, height: windowSize.height, alignment: .top)))
		host.frame = NSRect(origin: .zero, size: windowSize)
		window.contentView = host

		self.window = window
		self.host = host

		if !LockScreenSpace.shared.isAvailable {
			Self.lastBuildOutcome = ("No lock screen space; capsule will only show when unlocked.", Date())
			Self.logger.notice("No lock screen space; capsule will only show when unlocked.")
		} else {
			Self.lastBuildOutcome = nil
		}
	}

	// No render(): the model drives the view, so there is nothing to rebuild.
}
