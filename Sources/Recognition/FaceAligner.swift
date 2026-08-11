import CoreImage
import CoreVideo
import Foundation
import Vision

/// Turns a detected face into the square, eye-aligned crop that embedding models expect.
///
/// Models in the ArcFace family are trained on faces warped so the pupils always land on
/// the same two pixels. Feeding them a raw camera crop instead costs a lot of accuracy,
/// because the model then has to spend capacity on pose it was never asked to handle.
enum FaceAligner {

	/// Canonical pupil positions in the 112×112 frame these models are trained against,
	/// stated in Core Image's lower-left origin.
	private static let referenceSide: CGFloat = 112
	private static let referenceLeftEye = CGPoint(x: 38.29, y: 112 - 51.69)
	private static let referenceRightEye = CGPoint(x: 73.53, y: 112 - 51.69)

	private static let context = CIContext(options: [.useSoftwareRenderer: false])

	/// A `side`×`side` BGRA buffer containing the aligned face, or nil if the pupils
	/// weren't located.
	static func alignedCrop(_ sample: FaceSample, side: Int) -> CVPixelBuffer? {
		guard
			let leftEye = sample.landmarks.leftPupil?.normalizedPoints.first,
			let rightEye = sample.landmarks.rightPupil?.normalizedPoints.first
		else { return nil }

		let image = CIImage(cvPixelBuffer: sample.pixelBuffer)
		let extent = image.extent
		let box = sample.boundingBox

		// Landmarks are normalised to the bounding box; lift them into image space.
		// Vision and Core Image share a lower-left origin, so no flip is needed.
		func toImage(_ p: CGPoint) -> CGPoint {
			let boxX: CGFloat = box.minX + p.x * box.width
			let boxY: CGFloat = box.minY + p.y * box.height
			let x: CGFloat = boxX * extent.width + extent.minX
			let y: CGFloat = boxY * extent.height + extent.minY
			return CGPoint(x: x, y: y)
		}

		let srcLeft = toImage(leftEye)
		let srcRight = toImage(rightEye)

		let scaleToOutput = CGFloat(side) / referenceSide
		let dstLeft = CGPoint(
			x: referenceLeftEye.x * scaleToOutput, y: referenceLeftEye.y * scaleToOutput)
		let dstRight = CGPoint(
			x: referenceRightEye.x * scaleToOutput, y: referenceRightEye.y * scaleToOutput)

		let srcVector = CGVector(dx: srcRight.x - srcLeft.x, dy: srcRight.y - srcLeft.y)
		let dstVector = CGVector(dx: dstRight.x - dstLeft.x, dy: dstRight.y - dstLeft.y)
		let srcLength = hypot(srcVector.dx, srcVector.dy)
		guard srcLength > 1 else { return nil }

		let scale = hypot(dstVector.dx, dstVector.dy) / srcLength
		let rotation = atan2(dstVector.dy, dstVector.dx) - atan2(srcVector.dy, srcVector.dx)

		// Read right to left: move the left pupil to the origin, scale and rotate the eye
		// line onto the reference one, then drop it at the reference position.
		var transform = CGAffineTransform.identity
			.translatedBy(x: dstLeft.x, y: dstLeft.y)
			.rotated(by: rotation)
			.scaledBy(x: scale, y: scale)
		transform = transform.translatedBy(x: -srcLeft.x, y: -srcLeft.y)

		let warped = image.transformed(by: transform)
			.cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
		guard !warped.extent.isEmpty else { return nil }

		var buffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			] as CFDictionary,
			&buffer)
		guard status == kCVReturnSuccess, let buffer else { return nil }

		context.render(warped, to: buffer)
		return buffer
	}
}
