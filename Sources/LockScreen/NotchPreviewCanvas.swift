import AppKit
import SwiftUI

struct NotchPreviewCanvas: View {
	let model: NotchCapsuleModel
	var widthAdjust: Double = 0
	var heightAdjust: Double = 0
	var wallpaper: NSImage?
	var background: Color = Color(nsColor: .underPageBackgroundColor)
	/// Where the panel view really sits in the canvas, measured, so its glass crop lines up.
	@State private var panelFrame: CGRect = .zero

	private var panelSize: CGSize {
		CGSize(width: 278 + widthAdjust, height: (model.shape == .island ? 244 : 128) + heightAdjust)
	}

	var body: some View {
		let hasNotch = NSScreen.main.map { NotchMetrics.hasNotch(on: $0) } ?? true
		return GeometryReader { geometry in
			ZStack(alignment: .top) {
				background
				if let wallpaper {
					Image(nsImage: wallpaper)
						.resizable()
						.scaledToFill()
						.frame(width: geometry.size.width, height: geometry.size.height)
						.clipped()
				}
				NotchCapsule(model: model, width: panelSize.width,
					height: panelSize.height,
					notchInset: 32, cutoutWidth: 180, hasNotch: hasNotch)
					.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("notchPreview")) } action: {
						panelFrame = $0
					}
				if hasNotch {
					UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
						.fill(.black)
						.frame(width: 180, height: 32)
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
			.clipped()
			.coordinateSpace(.named("notchPreview"))
			// The lock screen draws its glass from the wallpaper (WallpaperGlass); give the
			// preview the same backdrop, cut from the wallpaper shown here, so it matches.
			.task(id: "\(geometry.size)|\(panelFrame)|\(wallpaper.map { ObjectIdentifier($0).hashValue } ?? 0)") {
				model.backdrop = panelFrame.isEmpty ? nil : Self.backdrop(wallpaper, canvas: geometry.size, panel: panelFrame)
			}
		}
	}

	private static func backdrop(_ wallpaper: NSImage?, canvas: CGSize, panel: CGRect) -> GlassBackdrop? {
		guard let wallpaper, let image = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else { return nil }
		return GlassBackdrop.make(from: image, canvas: canvas, rect: panel)
	}
}
