// Adapted from Glance by Jonathan Zhou (MIT License), https://github.com/jonnyoo/glance
// Catches glossy screen glare: near-white, low-chroma pixels concentrated in one blob
// rather than scattered like skin shine. False-reject risk: bright reflections on glasses.

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// Passive screen-glare deny cue.
///
/// Counts near-white, low-chroma pixels inside the face region of the anti-spoof
/// context crop. The fraction alone would fire on a shiny forehead, so it is gated by
/// concentration — the densest 8x8 cell's share of the glare pixels — which is what
/// distinguishes one flat glass blob from many small scattered highlights. Deny-only:
/// firing rejects the frame; a low reading never helps a frame pass.
///
/// Counting is cumulative across the scan (3 qualifying frames fire, latched); frames
/// where the face is too small to judge abstain instead of voting either way.
///
/// Deliberately free of `FaceSample`: the cue measures a crop plus a face rect so the
/// regression suite can drive it with synthetic buffers.
struct GlareCue: Sendable {

	/// Level that counts a frame. Glance uses 0.04 (`glossLevel`).
	/// Tuned against a real lock-screen false reject: a genuine face, lit by the bright
	/// lock screen and analysed at about 60 px, scored 0.11 and was turned away at 0.04.
	/// A false reject here punishes the owner, so the cue now needs a strong reading on a
	/// face big enough to judge, and otherwise abstains.
	static let fireLevel: Float = 0.3
	static let minimumConfidence: Float = 0.6
	/// Qualifying frames within the scan that fire the cue (Glance `glossFrames`).
	static let fireFrames = 3
	/// Analysis width cap: the crop is downsampled to at most this before counting,
	/// which keeps the per-frame cost to a few thousand pixel visits.
	static let maxAnalysisWidth: CGFloat = 224
	/// Below this analyzed face width there is not enough detail to tell a glare blob
	/// from a bright patch, so the cue abstains; full trust by `trustedFaceWidth`.
	static let abstainFaceWidth: Float = 50
	static let trustedFaceWidth: Float = 130
	/// Below this mean face brightness the face is screen-lit in a dark room, where bright reflections read as glare — so the cue abstains.
	static let minimumFaceLuma: Float = 0.3

	private(set) var framesCounted = 0
	private(set) var fired = false
	/// Latest reading. Reported as the spoof score on the log line.
	private(set) var level: Float = 0
	/// Latest confidence, 0…1. Zero is an abstention, never a vote.
	private(set) var confidence: Float = 0

	mutating func reset() {
		framesCounted = 0
		fired = false
		level = 0
		confidence = 0
	}

	/// Measure one frame and count it toward firing. `crop` is the anti-spoof context
	/// crop; `faceRect` is the face box in crop pixels (any consistent origin — only
	/// the face region is sampled). Returns whether the cue has fired (latched).
	mutating func record(frame crop: CVPixelBuffer, faceRect: CGRect) -> Bool {
		let reading = Self.measure(crop: crop, faceRect: faceRect)
		level = reading.level
		confidence = reading.confidence
		if confidence >= Self.minimumConfidence, level >= Self.fireLevel {
			framesCounted += 1
			if framesCounted >= Self.fireFrames { fired = true }
		}
		return fired
	}

	/// Level/confidence for one crop, without touching per-scan state.
	static func measure(crop: CVPixelBuffer, faceRect: CGRect) -> (level: Float, confidence: Float) {
		let width = CVPixelBufferGetWidth(crop)
		let height = CVPixelBufferGetHeight(crop)
		guard width > 0, height > 0 else { return (0, 0) }
		let scale = min(1, maxAnalysisWidth / CGFloat(width))
		let ci = CIImage(cvPixelBuffer: crop)
		guard ci.extent.width > 0, ci.extent.height > 0,
			let full = renderContext.createCGImage(ci, from: ci.extent),
			let pixels = downsampledRGBA(full, scale: scale)
		else { return (0, 0) }
		let face = CGRect(
			x: faceRect.minX * scale, y: faceRect.minY * scale,
			width: faceRect.width * scale, height: faceRect.height * scale)
			.intersection(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
		guard !face.isNull, !face.isEmpty else { return (0, 0) }
		// Confidence is measured on what is actually analyzed: below ~50 px of face
		// the cue abstains, ramping to full trust by ~130 px.
		let confidence = ramp(Float(face.width), floor: abstainFaceWidth, ceiling: trustedFaceWidth)
		let minX = Int(face.minX), maxX = Int(face.maxX)
		let minY = Int(face.minY), maxY = Int(face.maxY)
		guard maxX > minX, maxY > minY else { return (0, 0) }
		let grid = 8
		var cells = [Int](repeating: 0, count: grid * grid)
		var glareTotal = 0
		var lumaSum: Float = 0
		let facePixels = (maxX - minX) * (maxY - minY)
		pixels.data.withUnsafeBufferPointer { bytes in
			for y in minY..<maxY {
				let gy = min(grid - 1, (y - minY) * grid / (maxY - minY))
				for x in minX..<maxX {
					let offset = (y * pixels.width + x) * 4
					let r = Float(bytes[offset])
					let g = Float(bytes[offset + 1])
					let b = Float(bytes[offset + 2])
					let luma = 0.299 * r + 0.587 * g + 0.114 * b
					lumaSum += luma / 255
					guard luma >= 235 else { continue }
					guard max(r, max(g, b)) - min(r, min(g, b)) <= 10 else { continue }
					glareTotal += 1
					let gx = min(grid - 1, (x - minX) * grid / (maxX - minX))
					cells[gy * grid + gx] += 1
				}
			}
		}
		guard lumaSum / Float(facePixels) >= Self.minimumFaceLuma else { return (0, 0) }
		guard glareTotal > 0 else { return (0, confidence) }
		let fraction = Float(glareTotal) / Float(facePixels)
		let cluster = Float(cells.max() ?? 0) / Float(glareTotal)
		let level = ramp(fraction, floor: 0.01, ceiling: 0.08) * ramp(cluster, floor: 0.3, ceiling: 1.0)
		return (level, confidence)
	}

	private static func ramp(_ value: Float, floor: Float, ceiling: Float) -> Float {
		min(max((value - floor) / max(ceiling - floor, 0.0001), 0), 1)
	}

	private static let renderContext = CIContext(options: nil)

	private struct RGBAImage {
		let width: Int
		let height: Int
		let data: [UInt8]
	}

	/// Renders `image` scaled by `scale` into an RGBA byte array. One render per frame;
	/// at the 160 px cap that is ~25k pixels, well under a millisecond of pixel work.
	private static func downsampledRGBA(_ image: CGImage, scale: CGFloat) -> RGBAImage? {
		let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
		let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
		guard width > 0, height > 0 else { return nil }
		// CIImage has no direct CGImage downscale; go through a bitmap context so the
		// byte order is exactly RGBA regardless of the camera buffer's layout.
		guard let context = CGContext(
			data: nil, width: width, height: height,
			bitsPerComponent: 8, bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
				| CGBitmapInfo.byteOrder32Big.rawValue)
		else { return nil }
		context.interpolationQuality = .medium
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		guard let data = context.data else { return nil }
		let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
		return RGBAImage(
			width: width, height: height,
			data: Array(UnsafeBufferPointer(start: bytes, count: width * height * 4)))
	}
}
