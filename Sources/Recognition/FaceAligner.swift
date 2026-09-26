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
			(16...1024).contains(side),
			let leftEye = sample.landmarks.leftPupil?.normalizedPoints.first,
			let rightEye = sample.landmarks.rightPupil?.normalizedPoints.first,
			[leftEye.x, leftEye.y, rightEye.x, rightEye.y].allSatisfy({ $0.isFinite && (0...1).contains($0) })
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
		guard srcLength.isFinite, srcLength > 1 else { return nil }

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

	/// A square crop around the face with room to spare, for the anti-spoof model.
	///
	/// Deliberately not `alignedCrop`. That warps the pupils onto two fixed pixels,
	/// which is right for recognition — pose is noise there — and wrong here: what
	/// gives a spoof away is at the *edges*. A phone's bezel, the border of a sheet
	/// of paper, the rectangle of glare across a screen, the hand holding it. Warp
	/// tightly to the eyes and every one of those is cropped out of frame, leaving
	/// the model to judge liveness from a face that looks, by construction, exactly
	/// like a face.
	///
	/// `margin` is how many face-widths across the crop is: 1 is the bounding box
	/// itself, 2.7 is the legacy operating point the MiniFASNet family was trained at,
	/// kept because the shipped Spoof model is served the same framing.
	///
	/// No rotation either. A held phone is often slightly tilted, and that tilt is
	/// evidence — straightening it throws the evidence away.
	static func contextCrop(_ sample: FaceSample, side: Int, margin: CGFloat = 2.7) -> CVPixelBuffer? {
		guard (16...1024).contains(side), margin.isFinite, margin > 0 else { return nil }
		let image = CIImage(cvPixelBuffer: sample.pixelBuffer)
		guard let (crop, _) = contextWindow(sample, margin: margin) else { return nil }

		let scale = CGFloat(side) / crop.width
		let rendered = image
			.cropped(to: crop)
			.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
			.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
			.cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
		guard !rendered.extent.isEmpty else { return nil }

		var buffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			] as CFDictionary,
			&buffer)
		guard status == kCVReturnSuccess, let buffer else { return nil }

		context.render(rendered, to: buffer)
		return buffer
	}

	/// The square image window `contextCrop` renders, plus the face box inside it, in
	/// image pixels. Shared so the passive deny cues measure the face at exactly the
	/// position the crop put it — duplicating this math beside `contextCrop` would let
	/// the two drift apart and the bezel overlap fraction would be measured against
	/// the wrong box.
	private static func contextWindow(_ sample: FaceSample, margin: CGFloat) -> (crop: CGRect, face: CGRect)? {
		let image = CIImage(cvPixelBuffer: sample.pixelBuffer)
		let extent = image.extent
		guard extent.width > 0, extent.height > 0 else { return nil }

		let box = sample.boundingBox
		let faceRect = CGRect(
			x: box.minX * extent.width + extent.minX,
			y: box.minY * extent.height + extent.minY,
			width: box.width * extent.width,
			height: box.height * extent.height)
		guard [faceRect.minX, faceRect.minY, faceRect.width, faceRect.height].allSatisfy(\.isFinite),
			faceRect.width > 1, faceRect.height > 1 else { return nil }

		// Square, so the model never sees the aspect ratio stretched — a stretched
		// pixel grid is itself a moiré-like artefact and would be learned as one.
		let wanted = min(max(faceRect.width, faceRect.height) * margin, min(extent.width, extent.height))
		var crop = CGRect(
			x: faceRect.midX - wanted / 2,
			y: faceRect.midY - wanted / 2,
			width: wanted, height: wanted)

		// Slide back inside the frame rather than clamping the size, which would
		// change the scale and make crops from faces near an edge incomparable with
		// the rest of the set.
		crop.origin.x = min(max(crop.minX, extent.minX), extent.maxX - crop.width)
		crop.origin.y = min(max(crop.minY, extent.minY), extent.maxY - crop.height)
		crop = crop.intersection(extent)
		guard crop.width > 1, crop.height > 1 else { return nil }
		return (crop, faceRect)
	}

	/// The face box in the `side`×`side` context crop's pixel space, lower-left
	/// origin to match Vision's normalized coordinates.
	///
	/// Same geometry as `contextCrop(_:side:margin:)` by construction — both go
	/// through `contextWindow` — so the rectangle the bezel cue overlaps against the
	/// face is the face as the crop actually rendered it, including the edge slide.
	static func contextFaceRect(_ sample: FaceSample, side: Int, margin: CGFloat = 2.7) -> CGRect? {
		guard let (crop, face) = contextWindow(sample, margin: margin) else { return nil }
		let scale = CGFloat(side) / crop.width
		return CGRect(
			x: (face.minX - crop.minX) * scale,
			y: (face.minY - crop.minY) * scale,
			width: face.width * scale,
			height: face.height * scale)
	}
}
