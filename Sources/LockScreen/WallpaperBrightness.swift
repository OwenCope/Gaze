import AppKit
import CoreImage

/// How light the wallpaper is directly behind the notch.
///
/// The panel sits against whatever the wallpaper happens to be. On a dark picture the
/// black body reads as the notch continuing; on a light one it becomes an obvious slab.
/// Sampling lets the material adapt instead of picking one and being wrong half the time.
enum WallpaperBrightness {

	/// Average luminance, 0 (black) to 1 (white), of the wallpaper region under the notch.
	///
	/// Only the strip the panel actually covers is sampled — a photo can be dark overall
	/// and bright exactly where the panel lands, and the average of the whole image would
	/// hide that.
	static func underNotch(on screen: NSScreen) -> Double? {
		guard
			let url = NSWorkspace.shared.desktopImageURL(for: screen),
			let image = CIImage(contentsOf: url)
		else { return nil }

		let extent = image.extent
		guard extent.width > 0, extent.height > 0 else { return nil }

		// Top-centre strip, proportional to the notch's share of the screen.
		let notchFraction = (NotchMetrics.width(on: screen) ?? 180) / screen.frame.width
		let sampleWidth = extent.width * notchFraction * 1.6
		let sampleHeight = extent.height * 0.10

		let region = CGRect(
			x: extent.midX - sampleWidth / 2,
			y: extent.maxY - sampleHeight,
			width: sampleWidth,
			height: sampleHeight)

		guard
			let average = CIFilter(
				name: "CIAreaAverage",
				parameters: [
					kCIInputImageKey: image,
					kCIInputExtentKey: CIVector(cgRect: region),
				])?.outputImage
		else { return nil }

		var pixel = [UInt8](repeating: 0, count: 4)
		let context = CIContext(options: [.workingColorSpace: NSNull()])
		context.render(
			average,
			toBitmap: &pixel,
			rowBytes: 4,
			bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
			format: .RGBA8,
			colorSpace: CGColorSpaceCreateDeviceRGB())

		// Rec. 709 luma — perceptual weighting, so yellow reads as light and blue as dark
		// the way an eye would judge it.
		let r = Double(pixel[0]) / 255
		let g = Double(pixel[1]) / 255
		let b = Double(pixel[2]) / 255
		return 0.2126 * r + 0.7152 * g + 0.0722 * b
	}

	/// True when the wallpaper behind the notch is light enough that a plain black panel
	/// would read as a slab rather than as part of the hardware.
	static func isLight(on screen: NSScreen) -> Bool {
		guard let luminance = underNotch(on: screen) else { return false }
		return luminance > 0.5
	}
}
