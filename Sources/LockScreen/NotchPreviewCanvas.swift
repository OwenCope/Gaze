import AppKit
import SwiftUI

struct NotchPreviewCanvas: View {
	let model: NotchCapsuleModel
	var widthAdjust: Double = 0
	var heightAdjust: Double = 0
	var wallpaper: NSImage?
	var background: Color = Color(nsColor: .underPageBackgroundColor)

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .top) {
				background
				if let wallpaper {
					Image(nsImage: wallpaper)
						.resizable()
						.scaledToFill()
						.frame(width: geometry.size.width, height: geometry.size.height)
						.clipped()
				}
				NotchCapsule(model: model, width: 278 + widthAdjust,
					height: (model.shape == .island ? 244 : 128) + heightAdjust,
					notchInset: 32, cutoutWidth: 180)
				UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
					.fill(.black)
					.frame(width: 180, height: 32)
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
			.clipped()
		}
	}
}
