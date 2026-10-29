import AppKit
import SwiftUI

/// Renders the lock screen panel offscreen over a real wallpaper, to a PNG, and exits.
///
/// `--preview-lockscreen-panel=<out.png>` with optional `--preview-wallpaper=<image>`
/// (defaults to the current desktop picture), `--preview-appearance=light|dark`,
/// `--preview-style=liquid|semi|normal` and `--preview-shape=island|attached`. For looking
/// at the glass without installing Gaze or locking the screen.
@MainActor
enum LockPanelPreview {

	/// Set while rendering, so the face mark draws in 2D where a snapshot can see it.
	static private(set) var isRendering = false

	static func runIfRequested() {
		guard let out = value(for: "--preview-lockscreen-panel=") else { return }
		isRendering = true
		let wallpaperURL = value(for: "--preview-wallpaper=").map(URL.init(fileURLWithPath:))
			?? NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
		guard let wallpaperURL, let wallpaper = GlassBackdrop.loadImage(wallpaperURL) else {
			FileHandle.standardError.write(Data("No wallpaper image to render over.\n".utf8))
			Darwin.exit(1)
		}
		let light = value(for: "--preview-appearance=") == "light"

		// A 14" MacBook Pro's screen, showing the top-centre region around the notch.
		let screen = CGSize(width: 1512, height: 982)
		let cutout: CGFloat = 185
		let notchHeight: CGFloat = 32
		let canvas = CGRect(x: (screen.width - 640) / 2, y: 0, width: 640, height: 330)

		let model = NotchCapsuleModel()
		model.style = switch value(for: "--preview-style=") {
		case "semi": .semiLiquidGlass
		case "normal": .normal
		default: .liquidGlass
		}
		model.shape = value(for: "--preview-shape=") == "attached" ? .attached : .island
		model.phase = .scanning
		model.isExpanded = true
		model.lightBehind = light
		// The glass resolves positions in the root's coordinates, so the crop covers the canvas.
		model.backdrop = GlassBackdrop.make(from: wallpaper, canvas: screen, rect: canvas)

		let panelWidth = cutout * 1.56
		let panelHeight = notchHeight
			+ (model.shape == .island ? IslandMetrics.dropHeight(cutoutWidth: cutout) : 96)
		let view = ZStack(alignment: .top) {
			Image(decorative: wallpaper, scale: 1)
				.resizable()
				.scaledToFill()
				.frame(width: screen.width, height: screen.height)
				.offset(x: -canvas.minX, y: -canvas.minY)
				.frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
				.clipped()
			NotchCapsule(
				model: model, width: panelWidth, height: panelHeight,
				notchInset: notchHeight, cutoutWidth: cutout, hasNotch: true)
				.frame(width: panelWidth, height: panelHeight)
			UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
				.fill(.black)
				.frame(width: cutout, height: notchHeight)
		}
		.frame(width: canvas.width, height: canvas.height, alignment: .top)
		.environment(\.colorScheme, light ? .light : .dark)
		.environment(\.notchReduceMotion, true)

		let renderer = ImageRenderer(content: view)
		renderer.scale = 2
		guard let image = renderer.cgImage,
			let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
		else {
			FileHandle.standardError.write(Data("Render failed.\n".utf8))
			Darwin.exit(1)
		}
		do {
			try png.write(to: URL(fileURLWithPath: out))
		} catch {
			FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
			Darwin.exit(1)
		}
		Darwin.exit(0)
	}

	private static func value(for prefix: String) -> String? {
		CommandLine.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
	}
}
