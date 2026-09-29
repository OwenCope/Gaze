import CoreVideo
import Foundation
import Vision

/// Pixel-based pupil locator. Vision's pupil landmark is too coarse for the
/// look-left/look-right challenge, so the dark pupil mass is found directly
/// from the frame's pixels inside each eye outline.
enum PupilLocator {

	/// Both axes from MediaPipe Iris when it is loaded; otherwise only x, from the pixel search.
	static func gaze(_ sample: FaceSample) -> (x: Double, y: Double?)? {
		if let iris = IrisLocator.gaze(sample) { return (iris.x, iris.y) }
		return horizontalOffset(sample).map { ($0, nil) }
	}

	/// MediaPipe Iris when its model is bundled, else the pixel search below.
	static func horizontalOffset(_ sample: FaceSample) -> Double? {
		IrisLocator.horizontalOffset(sample) ?? horizontalOffset(pixelBuffer: sample.pixelBuffer, faceBox: sample.boundingBox,
			landmarks: sample.landmarks)
	}

	static func horizontalOffset(pixelBuffer: CVPixelBuffer, faceBox: CGRect,
		landmarks: VNFaceLandmarks2D) -> Double? {
		let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
			height: CVPixelBufferGetHeight(pixelBuffer))
		guard size.width > 0, size.height > 0 else { return nil }
		let eyes = [landmarks.leftEye?.normalizedPoints, landmarks.rightEye?.normalizedPoints]
			.compactMap { $0 }
		let offsets = eyes.compactMap { outline -> Double? in
			guard outline.count >= 3 else { return nil }
			return offset(inEye: outline.map { Self.pixelPoint($0, faceBox: faceBox, size: size) },
				pixelBuffer: pixelBuffer)
		}
		guard !offsets.isEmpty else { return nil }
		return offsets.reduce(0, +) / Double(offsets.count)
	}

	/// Pupil shift within one eye outline, as (centroid.x - boxMid.x) / boxWidth.
	/// Positive is toward image +x — the same polarity as `LivenessChallenge.gazeOffset`.
	static func offset(inEye outline: [CGPoint], pixelBuffer: CVPixelBuffer) -> Double? {
		guard outline.count >= 3 else { return nil }
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
		var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
		for p in outline {
			minX = min(minX, p.x); maxX = max(maxX, p.x)
			minY = min(minY, p.y); maxY = max(maxY, p.y)
		}
		// Shrink vertically: lid rows and lashes are dark and would pull the centroid.
		let midY = (minY + maxY) / 2
		let halfH = (maxY - minY) / 2 * 0.85
		let boxMinX = minX, boxMaxX = maxX
		let boxMinY = midY - halfH, boxMaxY = midY + halfH
		guard boxMaxX - boxMinX >= 12 else { return nil }
		let x0 = max(0, Int(boxMinX.rounded(.down))), x1 = min(width - 1, Int(boxMaxX.rounded(.up)))
		let y0 = max(0, Int(boxMinY.rounded(.down))), y1 = min(height - 1, Int(boxMaxY.rounded(.up)))
		guard x1 >= x0, y1 >= y0 else { return nil }

		CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
		guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
		let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

		func luminance(x: Int, y: Int) -> Int {
			let pixel = base.advanced(by: y * rowBytes + x * 4).assumingMemoryBound(to: UInt8.self)
			return (29 * Int(pixel[0]) + 150 * Int(pixel[1]) + 77 * Int(pixel[2])) >> 8
		}
		// First pass: histogram the outline's pixels to find the pupil darkness cutoff.
		var histogram = [Int](repeating: 0, count: 256)
		var count = 0
		for y in y0...y1 {
			for x in x0...x1 where Self.inside(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), outline) {
				histogram[luminance(x: x, y: y)] += 1
				count += 1
			}
		}
		guard count >= 20 else { return nil }
		var cumulative = 0
		let target = max(1, count * 18 / 100)
		var threshold = 255
		for lum in 0..<256 {
			cumulative += histogram[lum]
			if cumulative >= target { threshold = lum; break }
		}
		// Second pass: weighted centroid of the dark pixels, darker weighing more.
		var sumX = 0.0, sumW = 0.0
		for y in y0...y1 {
			for x in x0...x1 where Self.inside(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), outline) {
				let lum = luminance(x: x, y: y)
				guard lum <= threshold else { continue }
				let w = Double(threshold - lum + 1)
				sumX += Double(x) * w
				sumW += w
			}
		}
		guard sumW > 0 else { return nil }
		let midX = (boxMinX + boxMaxX) / 2
		return (sumX / sumW - midX) / (boxMaxX - boxMinX)
	}

	/// Vision normalized point (relative to faceBox, origin bottom-left) to pixel
	/// coords (top-left origin).
	private static func pixelPoint(_ p: CGPoint, faceBox: CGRect, size: CGSize) -> CGPoint {
		CGPoint(x: (faceBox.minX + p.x * faceBox.width) * size.width,
			y: (1 - (faceBox.minY + p.y * faceBox.height)) * size.height)
	}

	/// Even-odd point-in-polygon over the outline.
	private static func inside(_ p: CGPoint, _ outline: [CGPoint]) -> Bool {
		var odd = false
		var j = outline.count - 1
		for i in 0..<outline.count {
			let a = outline[i], b = outline[j]
			if (a.y > p.y) != (b.y > p.y),
				p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
				odd.toggle()
			}
			j = i
		}
		return odd
	}
}
