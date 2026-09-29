import AppKit
import SwiftUI

/// The edge light the look challenge asks the person to look at.
///
/// The notch panel sits right under the camera, so a dot drawn inside it is
/// almost the same as looking at the camera and the pupils barely move. This
/// window puts the target far from the camera instead: a small glowing light
/// centred vertically on the screen, just inside the prompted edge. It only
/// renders; NotchCapsuleController decides when a look prompt is up.
@MainActor
final class LookTargetOverlay {

	static let shared = LookTargetOverlay()

	private final class UnfocusableWindow: NSWindow {
		override var canBecomeKey: Bool { false }
		override var canBecomeMain: Bool { false }
	}

	/// The light itself: a white core with a soft radial glow, breathing gently.
	/// Steady under Reduce Motion.
	private struct Target: View {
		private static let glowDiameter: CGFloat = 44
		private static let coreDiameter: CGFloat = 18

		@State private var breathing = false

		private var reduceMotion: Bool {
			NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		}

		var body: some View {
			ZStack {
				Circle()
					.fill(
						RadialGradient(
							colors: [.white.opacity(0.55), .white.opacity(0)],
							center: .center, startRadius: 0, endRadius: Self.glowDiameter / 2)
					)
					.frame(width: Self.glowDiameter, height: Self.glowDiameter)
				Circle()
					.fill(.white)
					.frame(width: Self.coreDiameter, height: Self.coreDiameter)
			}
			.scaleEffect(breathing && !reduceMotion ? 1.1 : (reduceMotion ? 1 : 0.9))
			.animation(
				reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
				value: breathing
			)
			.accessibilityHidden(true)
			.onAppear { breathing = true }
			.onDisappear { breathing = false }
		}
	}

	private var window: NSWindow?
	private var host: NSHostingView<AnyView>?
	private var side: HorizontalEdge = .leading
	private(set) var isShowing = false

	private var reduceMotion: Bool {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	/// The screen with the notch when there is one, else the main screen.
	private static func targetScreen() -> NSScreen? {
		NSScreen.screens.first(where: { NotchMetrics.hasNotch(on: $0) }) ?? NSScreen.main
	}

	/// A full-screen clear view carrying the light along the pursuit path: it rests at
	/// the centre, glides to 56pt inside the prompted edge, and glides back, on the
	/// same clock `LivenessChallenge` scores the eyes against.
	private func content(size: CGSize, side: HorizontalEdge) -> some View {
		// Each pass starts at the centre and heads for the screen's edge in the pass's own
		// direction, so the ellipse of reach follows the screen's shape.
		let reachX = max(0, size.width / 2 - 56 - 22)
		let reachY = max(0, size.height / 2 - 56 - 22)
		return TimelineView(.animation) { _ in
			let now = ProcessInfo.processInfo.systemUptime
			let elapsed = max(0, now - (LivenessChallenge.lookOrigin ?? now))
			let position = LivenessChallenge.lookTargetPosition(elapsed: elapsed)
			let angle = LivenessChallenge.lookAngle(
				cycle: Int(elapsed / LivenessChallenge.lookPeriod), seed: LivenessChallenge.lookSeed ?? 0)
			Target()
				.offset(x: cos(angle) * reachX * position, y: -sin(angle) * reachY * position)
		}
		.frame(width: size.width, height: size.height)
		.background(.clear)
	}

	private func build(on screen: NSScreen) {
		let window = UnfocusableWindow(
			contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.ignoresMouseEvents = true
		// Beside the edge glow (overlay + 3): the light must never cover the capsule.
		window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 4)  // Above the dark-room edge light, which may be showing too.
		window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		window.hidesOnDeactivate = false

		// The window is the screen's own frame, never .zero, so the backing
		// scale is right and the light stays crisp on Retina.
		let host = NSHostingView(
			rootView: AnyView(content(size: screen.frame.size, side: side)))
		host.frame = NSRect(origin: .zero, size: screen.frame.size)
		host.autoresizingMask = [.width, .height]
		window.contentView = host
		window.alphaValue = 0
		self.window = window
		self.host = host
	}

	private func refreshContent(on screen: NSScreen) {
		host?.rootView = AnyView(content(size: screen.frame.size, side: side))
	}

	/// Fades the light in over 0.2 s, or shows it instantly under Reduce Motion.
	func show(side: HorizontalEdge) {
		let wasShowing = isShowing
		isShowing = true
		guard let screen = Self.targetScreen() else { return }
		// A new prompt, or the other side, starts the path from the centre again.
		// The light waits at the centre until the eyes are being read: the challenge
		// starts its clock on the first steady frame, so the first pass is never half
		// over before scoring begins (which wasted it and made every unlock two passes).
		if !wasShowing || side != self.side {
			LivenessChallenge.lookOrigin = nil
			LivenessChallenge.lookSeed = UInt64.random(in: .min ... .max)
			LivenessChallenge.lookOverlayWaiting = true
		}
		self.side = side
		if window == nil {
			build(on: screen)
		} else {
			refreshContent(on: screen)
		}
		guard let window else { return }
		window.orderFrontRegardless()
		// After ordering in, never before: the window number does not exist until then.
		LockScreenSpace.shared.adopt(window)
		fade(window, to: 1, duration: 0.2)
	}

	/// Fades the light out and removes the window.
	func hide() {
		isShowing = false
		LivenessChallenge.lookOrigin = nil
		LivenessChallenge.lookOverlayWaiting = false
		LivenessChallenge.lookSeed = nil
		guard let window else { return }
		if reduceMotion {
			remove(window)
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.15
			window.animator().alphaValue = 0
		} completionHandler: {
			MainActor.assumeIsolated {
				if !self.isShowing { self.remove(window) }
			}
		}
	}

	/// Out of the lock screen space and off screen, and forgotten, the way the
	/// notch capsule tears its window down: a window left adopted lingers.
	private func remove(_ window: NSWindow) {
		LockScreenSpace.shared.release(window)
		window.orderOut(nil)
		if self.window === window {
			self.window = nil
			self.host = nil
		}
	}

	private func fade(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval) {
		if reduceMotion {
			window.alphaValue = alpha
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = duration
			window.animator().alphaValue = alpha
		}
	}
}
