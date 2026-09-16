// StudioRenderer.swift — Hank 3 (Droppy Code Hydra head)
//
// Reproducible offline renderer for clean Gaze panel preview videos.
// Reuses the production views directly: PreviewPreferences (style model),
// Theme, GazeFaceMark, NotchCapsule, NotchPanelShape, and the Companion
// Metal renderer via the CompanionCapture offscreen pattern (synthetic
// NSHostingView + real renderer pixels; never touches the desktop, the
// camera, the lock, the Keychain, enrolment, or live preferences).
//
// Every model/preferences instance here is synthetic: a fresh
// NotchCapsuleModel with hardcoded values mirroring what
// NotchCapsuleController.show() captures from Preferences on a light
// wallpaper (style per variant, attached, centred, transparency 0.3,
// prefersOpaque true).
//
// Presentation states are simulated panel previews, not a security test
// and not a real unlock recording.
//
// Usage: studio-render <framesDir> <styleRawValue> <tag> [startFrame] [frameCount]
// Renders 240 frames (960x600, 30 fps, 8 s) of the fixed choreography.
// Diagnostics go to stderr (unbuffered) so a trap cannot swallow them.
import AppKit
import SwiftUI

// MARK: - Studio stage

/// Quiet light neutral studio stage: a soft vertical greyscale gradient
/// with the current production capsule centred at the top, roughly 400px
/// wide for legibility. No clock, weather, menu bar, Dock, names, files,
/// cursor, or wallpaper.
struct StudioStage: View {
	@Bindable var model: NotchCapsuleModel

	var body: some View {
		VStack(spacing: 0) {
			NotchCapsule(
				model: model,
				width: StudioRenderer.capsuleWidth,
				height: StudioRenderer.capsuleHeight,
				notchInset: StudioRenderer.notchInset,
				cutoutWidth: StudioRenderer.cutoutWidth
			)
			.frame(
				width: StudioRenderer.capsuleWidth,
				height: StudioRenderer.capsuleHeight,
				alignment: .top)
			Spacer(minLength: 0)
		}
		.frame(width: StudioRenderer.stageWidth, height: StudioRenderer.stageHeight)
		.background(
			LinearGradient(
				stops: [
					.init(color: Color(white: 0.965), location: 0),
					.init(color: Color(white: 0.925), location: 0.55),
					.init(color: Color(white: 0.895), location: 1),
				],
				startPoint: .top, endPoint: .bottom))
	}
}

// MARK: - Renderer

@main
enum StudioRenderer {
	static let stageWidth: CGFloat = 960
	static let stageHeight: CGFloat = 600
	// Production capsule is ~280pt across on a 179pt cutout; widened here
	// for legibility per the brief (380-420px), keeping the production
	// cutout/inset so the shape stays the production shape.
	static let capsuleWidth: CGFloat = 400
	static let capsuleHeight: CGFloat = 190
	static let notchInset: CGFloat = 32
	static let cutoutWidth: CGFloat = 180

	static let fps = 30
	static let totalFrames = 240 // 8 seconds at 30 fps

	@MainActor static func main() throws {
		let args = CommandLine.arguments
		guard args.count >= 4, let style = Preferences.NotchStyle(rawValue: args[2]) else {
			fatalError("usage: studio-render <framesDir> <normal|semiLiquidGlass|liquidGlass> <tag> [startFrame] [frameCount]")
		}
		let framesDir = URL(fileURLWithPath: args[1], isDirectory: true)
		let tag = args[3]
		let startFrame = args.count > 4 ? Int(args[4]) ?? 0 : 0
		let frameCount = args.count > 5 ? Int(args[5]) ?? totalFrames : totalFrames
		try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

		let model = NotchCapsuleModel()
		model.style = style
		model.shape = .attached
		model.glyphPlacement = .centred
		model.transparency = 0.3 // Preferences' default when no value is stored
		model.prefersOpaque = true // what the controller sets on a light wallpaper
		model.phase = .locked
		model.isExpanded = false
		// A partial range starts from the schedule state it would have had.
		if startFrame > 0 {
			for boundary in [0, 4, 21, 60, 99, 120, 156, 189, 213] where boundary <= startFrame {
				step(frame: boundary, model: model)
			}
		}

		let host = NSHostingView(rootView: StudioStage(model: model))
		host.frame = CGRect(x: 0, y: 0, width: stageWidth, height: stageHeight)
		// Deliberately never ordered front: this window must never appear on
		// the user's desktop. cacheDisplay renders it offscreen.
		let window = NSWindow(
			contentRect: host.frame, styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.backgroundColor = .clear
		window.isOpaque = false
		window.contentView = host
		host.layoutSubtreeIfNeeded()
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
		host.layoutSubtreeIfNeeded()
		withExtendedLifetime(window) {
			do {
				try renderLoop(
					host: host, model: model, framesDir: framesDir, tag: tag,
					startFrame: startFrame, frameCount: frameCount)
			} catch {
				fatalError("studio render failed: \(error)")
			}
		}
		log("STUDIO-DONE tag=\(tag) start=\(startFrame) count=\(frameCount)")
	}

	static func log(_ line: String) {
		FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
	}

	// MARK: - Choreography (simulated presentation states, not a security test)

	@MainActor static func step(frame: Int, model: NotchCapsuleModel) {
		switch frame {
		case 0:
			model.phase = .locked
			model.isExpanded = false
		case 4: // ~0.13s: grow out of the notch, sampled for real
			model.isExpanded = true
		case 21: // 0.7s
			model.phase = .scanning
		case 60: // 2.0s
			model.phase = .challenge(
				prompt: NotchCapsuleModel.Phase.outwardPrompt(
					"Turn slightly left", completedActions: 0, requiredActions: 2),
				symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
		case 99: // 3.3s: animated return; caption hidden by design
			// Production prompt/symbol for the return path; the capsule keeps
			// the caption hidden while isReturningToRest (animated mode).
			model.phase = .challenge(
				prompt: "Return to your starting position",
				symbol: "viewfinder", hintX: 0, hintY: 0, pulses: false,
				isReturningToRest: true)
		case 120: // 4.0s
			// "eye.fill": the brief's "(eye, pulses true)". The bare "eye"
			// symbol would map to resting motion instead of the blink
			// demonstration; MovementProgressTests uses "eye.fill" too.
			model.phase = .challenge(
				prompt: NotchCapsuleModel.Phase.outwardPrompt(
					"Blink", completedActions: 1, requiredActions: 2),
				symbol: "eye.fill", hintX: 0, hintY: 0, pulses: true)
		case 156: // 5.2s
			model.phase = .pending
		case 189: // 6.3s
			model.phase = .unlocked
		case 213: // 7.1s
			model.phase = .locked
		default:
			break
		}
	}

	// MARK: - Frame loop

	@MainActor static func renderLoop(
		host: NSHostingView<StudioStage>, model: NotchCapsuleModel,
		framesDir: URL, tag: String, startFrame: Int, frameCount: Int
	) throws {
		for frame in startFrame..<(startFrame + frameCount) {
			try autoreleasepool {
				step(frame: frame, model: model)
				// Capture/write overhead adds to this wait. Output phase timing
				// comes from frame counts, not measured on-screen frame cadence.
				// Gesture microtiming is illustrative.
				RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / Double(fps)))
				// The offscreen Metal overlay does not inherit SwiftUI's
				// transition opacity. Fade it in after the panel opens and
				// omit it while compact so it cannot float below the bar.
				let glyphOpacity = model.phase.isCompact ? 0 : min(1, max(0, Double(frame - 33) / 6))
				let bitmap = try capture(host: host, glyphOpacity: glyphOpacity)
				if frame == startFrame {
					log("STUDIO-GEOMETRY tag=\(tag) pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
				}
				try verify(frame: frame, bitmap: bitmap, host: host, tag: tag)
				guard let png = bitmap.representation(using: .png, properties: [:]) else {
					throw SoftFaceError.textureUnavailable
				}
				try png.write(to: framesDir.appendingPathComponent(String(format: "frame-%04d.png", frame)))
			}
			if frame % 60 == 0 { log("STUDIO-PROGRESS tag=\(tag) frame=\(frame)") }
		}
	}

	/// Offscreen capture following CompanionCapture.snapshot: cacheDisplay
	/// of the synthetic host plus real Metal renderer pixels overlaid.
	@MainActor static func capture(host: NSHostingView<StudioStage>, glyphOpacity: Double) throws -> NSBitmapImageRep {
		host.layoutSubtreeIfNeeded()
		let surfaces = CompanionCapture.surfaces(in: host)
		guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds),
			let context = NSGraphicsContext(bitmapImageRep: bitmap)
		else { throw SoftFaceError.textureUnavailable }
		host.cacheDisplay(in: host.bounds, to: bitmap)
		if !surfaces.isEmpty && glyphOpacity > 0 {
			NSGraphicsContext.saveGraphicsState()
			defer { NSGraphicsContext.restoreGraphicsState() }
			NSGraphicsContext.current = context
			let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
			for surface in surfaces {
				guard let gpu = surface.renderer.gpu, let sample = surface.renderer.pose else {
					throw SoftFaceError.unavailable
				}
				var rect = surface.view.convert(surface.view.bounds, to: host)
				if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
				let image = try CompanionCapture.frame(
					gpu: gpu, pose: sample(Date.timeIntervalSinceReferenceDate),
					size: CGSize(width: rect.width * scale, height: rect.height * scale),
					material: surface.renderer.material, opacity: surface.renderer.opacity)
				image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: glyphOpacity)
			}
		}
		return bitmap
	}

	// MARK: - In-render verification (face presence)

	// Caption legibility is verified post-render with a standalone Vision
	// probe (ocr-probe2): in-process accurate OCR proved flaky under Metal
	// contention (e5rtError), while the same requests succeed reliably from
	// a separate process over the saved frames.
	@MainActor static func verify(
		frame: Int, bitmap _: NSBitmapImageRep,
		host: NSHostingView<StudioStage>, tag: String
	) throws {
		// The Metal face must be mounted whenever the drop is showing.
		let surfaces = CompanionCapture.surfaces(in: host)
		if [70, 130, 170].contains(frame) {
			precondition(
				surfaces.count == 1,
				"tag=\(tag) frame=\(frame): expected exactly one Metal face, found \(surfaces.count)")
		}
	}
}
