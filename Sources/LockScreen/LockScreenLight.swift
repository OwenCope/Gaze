import AppKit
import CoreImage

/// A soft warm-white glow around the screen edges, modelled on macOS's Edge Light.
///
/// The camera needs some light on the face to unlock in a dark room, and the screen
/// itself is the only lamp available. This window paints that lamp: a quiet edge
/// gradient in warm white, nothing neon. It only renders and animates; the decision
/// of when the room is dark lives in the recognition layer, which drives `show()`
/// and `hide()`.
///
/// While the glow is up the built-in display is also ramped to full brightness, so
/// the lamp is at full strength, and restored to whatever it was on every way down.
@MainActor
final class LockScreenLight {

	static let shared = LockScreenLight()

	private final class UnfocusableWindow: NSWindow {
		override var canBecomeKey: Bool { false }
		override var canBecomeMain: Bool { false }
	}

	/// A wide band of light around the screen's real shape, bright at the glass and
	/// melting inwards, like macOS's Edge Light.
	///
	/// Rendered once into an image: the screen's outline stroked wide, then a Gaussian
	/// blur, so the falloff is smooth with no banding and the inner edge rounds itself.
	/// Two earlier versions failed at a glance: 72 stacked rectangles (square corners,
	/// stripes, drawn over the notch) and a stroke blurred by its own shadow (either a
	/// solid frame or a thin outline, never a glow).
	private final class EdgeGlowView: NSView {

		/// Warm white, about 5000 K.
		private static let tint = CGColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
		/// MacBook corners sit around here.
		private static let cornerRadius: CGFloat = 11

		/// The housing in view coordinates.
		private var notch: CGRect?
		private var renderedSize: CGSize = .zero

		init(frame: NSRect, screen: NSScreen) {
			notch = Self.notchRect(on: screen, in: frame.size)
			super.init(frame: frame)
			wantsLayer = true
			layer?.contentsGravity = .resize
			rebuild()
		}

		required init?(coder: NSCoder) { nil }

		override func layout() {
			super.layout()
			rebuild()
		}

		/// The camera housing, or nil on a screen without one.
		///
		/// Derived the same way NotchMetrics does, from the two menu bar fragments
		/// either side of the cutout: whatever lies between them is the notch.
		private static func notchRect(on screen: NSScreen, in size: CGSize) -> CGRect? {
			guard
				let left = screen.auxiliaryTopLeftArea,
				let right = screen.auxiliaryTopRightArea,
				right.minX - left.maxX > 0
			else { return nil }
			let height = NotchMetrics.height(on: screen)
			guard height > 0 else { return nil }
			let x0 = left.maxX - screen.frame.minX
			let x1 = right.minX - screen.frame.minX
			return CGRect(x: x0, y: size.height - height, width: x1 - x0, height: height)
		}

		private func rebuild() {
			guard bounds.width > 0, bounds.height > 0, bounds.size != renderedSize else { return }
			renderedSize = bounds.size
			let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
			layer?.contentsScale = scale
			layer?.contents = Self.render(size: bounds.size, scale: scale, notch: notch)
		}

		private static func render(size: CGSize, scale: CGFloat, notch: CGRect?) -> CGImage? {
			// The light reaches about seven percent of the short side inwards.
			let reach = min(size.width, size.height) * 0.07
			let width = Int(size.width * scale), height = Int(size.height * scale)
			guard width > 0, height > 0,
				let space = CGColorSpace(name: CGColorSpace.sRGB),
				let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
					bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { return nil }
			context.scaleBy(x: scale, y: scale)
			let rect = CGRect(origin: .zero, size: size)
			var bypass = notch
			if let raw = notch { bypass = raw.insetBy(dx: -2, dy: -2) }
			context.addPath(edgePath(in: rect, cornerRadius: cornerRadius, notch: bypass))
			context.setStrokeColor(tint)
			// Centred on the glass, so half the stroke is off screen and the blur below
			// turns the visible half into a soft falloff.
			context.setLineWidth(reach * 1.4)
			context.strokePath()
			guard let line = context.makeImage() else { return nil }

			let input = CIImage(cgImage: line)
			guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [
				kCIInputImageKey: input.clampedToExtent(),
				kCIInputRadiusKey: reach * 0.55 * scale,
			])?.outputImage?.cropped(to: input.extent) else { return line }
			return CIContext().createCGImage(blur, from: input.extent)
		}

		/// Fades in, or appears instantly under Reduce Motion. The window fades with it.
		func animateIn() {
			guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
			let fade = CABasicAnimation(keyPath: "opacity")
			fade.fromValue = 0
			fade.toValue = 1
			fade.duration = 0.4
			fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
			layer.add(fade, forKey: "fadeIn")
		}

		/// The screen's outline: rounded corners, and a top edge that dips below the
		/// housing instead of crossing it, so the glow never draws over the notch.
		private static func edgePath(in rect: CGRect, cornerRadius r: CGFloat, notch: CGRect?) -> CGPath {
			guard let notch, notch.width > 0, notch.minY > rect.minY else {
				return CGPath(
					roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
			}
			let nr: CGFloat = 6
			let path = CGMutablePath()
			path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
			path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
			path.addArc(
				tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
				tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
			path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
			path.addArc(
				tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
				tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
			path.addLine(to: CGPoint(x: notch.maxX, y: rect.maxY))
			path.addLine(to: CGPoint(x: notch.maxX, y: notch.minY + nr))
			path.addArc(
				tangent1End: CGPoint(x: notch.maxX, y: notch.minY),
				tangent2End: CGPoint(x: notch.maxX - nr, y: notch.minY), radius: nr)
			path.addLine(to: CGPoint(x: notch.minX + nr, y: notch.minY))
			path.addArc(
				tangent1End: CGPoint(x: notch.minX, y: notch.minY),
				tangent2End: CGPoint(x: notch.minX, y: notch.minY + nr), radius: nr)
			path.addLine(to: CGPoint(x: notch.minX, y: rect.maxY))
			path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
			path.addArc(
				tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
				tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
			path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
			path.addArc(
				tangent1End: CGPoint(x: rect.minX, y: rect.minY),
				tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
			path.closeSubpath()
			return path
		}

	}

	private var window: NSWindow?
	private(set) var isShowing = false

	private var reduceMotion: Bool {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	// MARK: - Display brightness boost

	/// The brightness keys use, resolved once and never again.
	private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
	private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Void

	private static var brightnessResolved = false
	private static var brightnessGet: GetBrightnessFn?
	private static var brightnessSet: SetBrightnessFn?

	/// Held while boosted so a quit mid-scan can still be recovered from, and cleared
	/// once the saved value is back on the display.
	private static let brightnessKey = "glowSavedBrightness"

	private var savedBrightness: Float?
	/// The value a restore ramp is heading back to. A show() that lands mid-restore saves
	/// this rather than the half-ramped brightness, which would otherwise become the
	/// "original" and leave the screen too bright or too dim afterwards.
	private var restoringTo: Float?
	private var rampTask: Task<Void, Never>?
	private var rampGeneration = 0

	private init() {
		// A quit mid-scan leaves the display maxed with nobody left to restore it.
		restoreStrandedBrightness()
	}

	/// The private API behind the brightness keys. Missing symbols mean silently
	/// skipping the brightness step and keeping the glow — never a crash, never an error.
	private static func brightnessFunctions() -> (get: GetBrightnessFn, set: SetBrightnessFn)? {
		if !brightnessResolved {
			brightnessResolved = true
			if
				let handle = dlopen(
					"/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
					RTLD_NOW),
				let get = dlsym(handle, "DisplayServicesGetBrightness"),
				let set = dlsym(handle, "DisplayServicesSetBrightness")
			{
				brightnessGet = unsafeBitCast(get, to: GetBrightnessFn.self)
				brightnessSet = unsafeBitCast(set, to: SetBrightnessFn.self)
			}
		}
		guard let get = brightnessGet, let set = brightnessSet else { return nil }
		return (get, set)
	}

	/// Saves the built-in display's brightness and ramps it to full. Built-in only —
	/// the main display is the lamp; external monitors are never touched. Never runs
	/// while the display is asleep.
	private func boostBrightness() {
		guard let fns = Self.brightnessFunctions() else { return }
		guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
		if savedBrightness == nil, let pending = restoringTo {
			savedBrightness = pending
			restoringTo = nil
			UserDefaults.standard.set(Double(pending), forKey: Self.brightnessKey)
		}
		if savedBrightness == nil {
			var current: Float = 0
			guard fns.get(CGMainDisplayID(), &current) == 0 else { return }
			// Already full: nothing to save and nothing to undo later.
			guard current < 1 else { return }
			savedBrightness = current
			UserDefaults.standard.set(Double(current), forKey: Self.brightnessKey)
		}
		if reduceMotion {
			fns.set(CGMainDisplayID(), 1)
		} else {
			startRamp(to: 1, clearingKeyOnCompletion: false)
		}
	}

	/// Ramps the built-in display back to the saved value. Safe to call twice: the
	/// second call finds nothing saved and does nothing.
	private func restoreBrightness() {
		let saved: Float? =
			savedBrightness ?? (UserDefaults.standard.object(forKey: Self.brightnessKey) as? NSNumber)?.floatValue
		guard let saved else { return }
		savedBrightness = nil
		guard let fns = Self.brightnessFunctions() else {
			UserDefaults.standard.removeObject(forKey: Self.brightnessKey)
			return
		}
		if reduceMotion {
			fns.set(CGMainDisplayID(), saved)
			UserDefaults.standard.removeObject(forKey: Self.brightnessKey)
		} else {
			restoringTo = saved
			startRamp(to: saved, clearingKeyOnCompletion: true)
		}
	}

	/// A dozen small steps over about 0.4 s, the way the keys feel.
	private func startRamp(to target: Float, clearingKeyOnCompletion: Bool) {
		guard let fns = Self.brightnessFunctions() else { return }
		rampTask?.cancel()
		rampGeneration += 1
		let generation = rampGeneration
		var start = target
		_ = fns.get(CGMainDisplayID(), &start)
		rampTask = Task { [weak self] in
			let steps = 12
			for step in 1...steps {
				try? await Task.sleep(for: .milliseconds(33))
				guard !Task.isCancelled else { return }
				let t = Float(step) / Float(steps)
				fns.set(CGMainDisplayID(), start + (target - start) * t)
			}
			guard !Task.isCancelled else { return }
			// Only the latest ramp clears the key: a show() that landed mid-restore
			// re-saved it, and clearing that would strand the new boost.
			if clearingKeyOnCompletion, self?.rampGeneration == generation {
				UserDefaults.standard.removeObject(forKey: Self.brightnessKey)
				self?.restoringTo = nil
			}
		}
	}

	/// Last launch ended boosted — put the saved value back before anything else runs.
	private func restoreStrandedBrightness() {
		guard
			let saved = UserDefaults.standard.object(forKey: Self.brightnessKey) as? NSNumber
		else { return }
		guard
			let fns = Self.brightnessFunctions(),
			CGDisplayIsAsleep(CGMainDisplayID()) == 0
		else { return }
		fns.set(CGMainDisplayID(), saved.floatValue)
		UserDefaults.standard.removeObject(forKey: Self.brightnessKey)
	}

	private func build(on screen: NSScreen) {
		let window = UnfocusableWindow(
			contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.ignoresMouseEvents = true
		// One step below the notch capsule (overlay + 4): the light must never cover it.
		window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 3)
		window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		window.hidesOnDeactivate = false

		let glow = EdgeGlowView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen)
		glow.autoresizingMask = [.width, .height]
		window.contentView = glow
		window.alphaValue = 0
		self.window = window
	}

	/// Fades and grows the glow in over 0.4 s, or appears instantly under Reduce Motion.
	func show() {
		isShowing = true
		guard let screen = NSScreen.main else { return }
		boostBrightness()
		if window == nil { build(on: screen) }
		guard let window, let glow = window.contentView as? EdgeGlowView else { return }
		window.orderFrontRegardless()
		// After ordering in, never before: the window number does not exist until then.
		LockScreenSpace.shared.adopt(window)
		glow.animateIn()
		fade(window, to: 1, duration: 0.4)
	}

	/// Fades the glow out, restores the display brightness, and removes the window.
	func hide() {
		isShowing = false
		restoreBrightness()
		guard let window else { return }
		if reduceMotion {
			remove(window)
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.3
			context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
			window.animator().alphaValue = 0
		} completionHandler: {
			MainActor.assumeIsolated {
				if !self.isShowing { self.remove(window) }
			}
		}
	}

	/// Out of the lock screen space and off screen, and forgotten, the way the notch
	/// capsule tears its window down: a window left adopted lingers into the next lock.
	private func remove(_ window: NSWindow) {
		// hide() already started the restore; this only covers a teardown that got
		// here another way, and no-ops when there is nothing saved.
		if savedBrightness != nil { restoreBrightness() }
		LockScreenSpace.shared.release(window)
		window.orderOut(nil)
		if self.window === window { self.window = nil }
	}

	private func fade(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval) {
		if reduceMotion {
			window.alphaValue = alpha
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = duration
			context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
			window.animator().alphaValue = alpha
		}
	}
}
