import CoreVideo
import os

/// The latest scene brightness from the camera, face or no face.
///
/// Written on the capture queue for every few frames, read by the unlock loop. In a
/// truly dark room Vision finds no face at all, so a brightness read only from face
/// samples never saw the dark it was meant to light.
enum SceneBrightness {
	private static let latest = OSAllocatedUnfairLock<(value: Float, at: ContinuousClock.Instant)?>(initialState: nil)
	private static let counter = OSAllocatedUnfairLock(initialState: 0)

	/// Samples every fourth frame; each read touches a few thousand bytes.
	static func record(_ buffer: CVPixelBuffer, at time: ContinuousClock.Instant) {
		let due = counter.withLock { count -> Bool in
			count &+= 1
			return count % 4 == 1
		}
		guard due, let value = FrameBrightness.mean(buffer) else { return }
		latest.withLock { $0 = (value, time) }
	}

	/// The most recent reading, if it is no older than a second.
	static func current(now: ContinuousClock.Instant = .now) -> Float? {
		latest.withLock { reading in
			guard let reading, reading.at <= now, reading.at.duration(to: now) <= .seconds(1) else { return nil }
			return reading.value
		}
	}

	static func reset() { latest.withLock { $0 = nil } }
}

/// Mean brightness of a camera frame, 0 (black) to 1 (white).
///
/// The unlock loop samples this before the expensive embed to decide whether the
/// scene is dark enough to need the edge light. Gaze's camera delivers 32BGRA,
/// which has no luma plane, so both shapes are handled: planar formats read
/// plane 0, packed formats average the colour channels. Either way the buffer is
/// read strided — a 1080p frame touches a few thousand bytes, not two million.
public enum FrameBrightness {

	public static func mean(_ pixelBuffer: CVPixelBuffer) -> Float? {
		guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
			return nil
		}
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
		if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
			return meanOfPlane0(pixelBuffer)
		}
		return meanOfPacked(pixelBuffer)
	}

	private static func meanOfPlane0(_ pixelBuffer: CVPixelBuffer) -> Float? {
		guard
			let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
			CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) > 0,
			CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) > 0
		else { return nil }

		let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
		let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
		let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

		let rowStride = max(1, height / 64)
		let columnStride = max(1, width / 64)
		var sum: UInt64 = 0
		var count: UInt64 = 0
		for row in stride(from: 0, to: height, by: rowStride) {
			let rowBase = base.advanced(by: row * rowBytes)
			for column in stride(from: 0, to: width, by: columnStride) {
				sum += UInt64(rowBase.load(fromByteOffset: column, as: UInt8.self))
				count += 1
			}
		}
		guard count > 0 else { return nil }
		return Float(sum) / Float(count) / 255
	}

	/// 32BGRA and other packed formats: average the colour bytes of sampled pixels.
	private static func meanOfPacked(_ pixelBuffer: CVPixelBuffer) -> Float? {
		guard
			let base = CVPixelBufferGetBaseAddress(pixelBuffer),
			CVPixelBufferGetWidth(pixelBuffer) > 0,
			CVPixelBufferGetHeight(pixelBuffer) > 0
		else { return nil }

		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
		// `CVPixelBufferGetBytesPerPixel` is a C macro and is not imported; the
		// row stride over a full-width row is the same number for the tight-packed
		// camera formats this path exists for.
		let bytesPerPixel = rowBytes / width
		guard bytesPerPixel >= 3 else { return nil }

		let rowStride = max(1, height / 64)
		let columnStride = max(1, width / 64)
		var sum: UInt64 = 0
		var count: UInt64 = 0
		for row in stride(from: 0, to: height, by: rowStride) {
			let rowBase = base.advanced(by: row * rowBytes)
			for column in stride(from: 0, to: width, by: columnStride) {
				let pixel = rowBase.advanced(by: column * bytesPerPixel)
				for channel in 0..<3 {
					sum += UInt64(pixel.load(fromByteOffset: channel, as: UInt8.self))
					count += 1
				}
			}
		}
		guard count > 0 else { return nil }
		return Float(sum) / Float(count) / 255
	}
}
