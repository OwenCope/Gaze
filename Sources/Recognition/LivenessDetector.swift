import CoreML
import Foundation

/// Legacy texture-liveness path; not used.
///
/// The anti-spoof check that runs is `SpoofDetector` via `AntiSpoofGate`: an object
/// detector that spots a held phone, screen or printed photo in frame.
///
/// What this path caught: someone holding a printed photo or a phone screen up to the
/// camera. Texture models score *capture artefacts* — moiré from a display, paper
/// grain, print edges, the flatness of a reflected highlight.
///
/// What it does not catch: frame injection. A virtual camera feeding a recording produces
/// no capture artefacts, because nothing was filmed, and these models happily call it
/// genuine. `CameraDevice` is what defends against that.
protocol LivenessDetector: Sendable {
	var identifier: String { get }
	/// Score above which a frame is treated as a real face in front of the lens.
	var threshold: Float { get }
	func score(_ sample: FaceSample) -> Float?
}

enum Liveness {
	/// How much of the scene around the face the anti-spoof model is shown, in
	/// face-widths. Stated once, because the capture tool and the detector must
	/// agree exactly — a model trained on one framing and served another is worse
	/// than no model, since it is confidently wrong rather than absent.
	static let cropMargin: CGFloat = 2.7

	/// The detector to use, or nil when none is available.
	///
	/// Legacy path only: this detector is not consulted by the unlock loop, which
	/// runs `SpoofDetector` via `AntiSpoofGate` instead.
	static func detector() -> LivenessDetector? {
		CoreMLLiveness()
	}

	static var isAvailable: Bool { detector() != nil }
}

/// Wraps a legacy texture-liveness model. Not used by the unlock loop, which runs
/// `SpoofDetector` via `AntiSpoofGate`. Kept for reference; handles two shapes of
/// model, because the two texture models worth trying take their input differently:
///
///  - **Image input** — the model declares an image feature. Fed a `contextCrop`
///    (face + margin, so screen bezels and paper edges stay in frame) as a pixel
///    buffer. This is the drop-in path for a typical CoreML anti-spoof export.
///  - **Multi-array input** `[1,3,S,S]` — the MiniFAS family. Fed the frame's centre
///    square scaled to S, RGB, `/255`. Its output is `[realLogit, spoofLogit]`, so
///    the genuine score is `softmax(...)[0]`.
///
/// Getting the serving wrong here is worse than having no model — a mis-fed model is
/// confidently wrong rather than absent — so each path mirrors its model's training
/// convention rather than sharing one.
struct CoreMLLiveness: LivenessDetector, @unchecked Sendable {
	let identifier: String
	let threshold: Float

	private let slot: ModelSlot<MLModel>
	private let inputName: String
	private let side: Int
	private let imageInput: Bool

	init?() {
		guard let url = Bundle.main.url(forResource: "Liveness", withExtension: "mlmodelc") else { return nil }
		let slot = ModelSlot<MLModel> { try? MLModel(contentsOf: url) }
		// Validate from this first load; the instance stays resident in the slot.
		guard let model = slot.withModel({ $0 }) else { return nil }

		let inputs = model.modelDescription.inputDescriptionsByName

		if let image = inputs.first(where: { $0.value.type == .image })?.value,
			let constraint = image.imageConstraint {
			self.slot = slot
			self.inputName = image.name
			self.side = constraint.pixelsWide
			self.imageInput = true
			self.threshold = 0.85
			self.identifier = "coreml-liveness-img:\(constraint.pixelsWide)"
		} else if let arr = inputs.first(where: { $0.value.multiArrayConstraint != nil })?.value,
			let constraint = arr.multiArrayConstraint, constraint.shape.count == 4 {
			// Legacy MiniFAS-family path (unused): [1, 3, S, S].
			self.slot = slot
			self.inputName = arr.name
			self.side = constraint.shape[3].intValue
			self.imageInput = false
			// Empirically (serving-finder, 2026-08-19): with the 2.7 face crop + (x-127.5)/128
			// normalisation, class 1 is "real" and it separates cleanly — a live face ≈ 1.0,
			// a photo ≈ 0.0. 0.5 sits in the middle of that gap with room for lighting.
			self.threshold = 0.5
			self.identifier = "coreml-liveness-arr:\(self.side):v2"
		} else {
			return nil
		}
	}

	func score(_ sample: FaceSample) -> Float? {
		guard let model = slot.withModel({ $0 }) else { return nil }
		if imageInput {
			guard
				let crop = FaceAligner.contextCrop(sample, side: side, margin: Liveness.cropMargin),
				let out = try? model.prediction(
					from: try MLDictionaryFeatureProvider(
						dictionary: [inputName: MLFeatureValue(pixelBuffer: crop)])),
				let array = firstMultiArray(out), array.count > 0
			else { return nil }
			// Two-class image exports put genuine at index 1; single-output at index 0.
			return array.count >= 2 ? array[1].floatValue : array[0].floatValue
		}

		// Legacy multi-array path (unused): the MiniFASNet family is trained on a face
		// crop scaled by the number in its name (2.7), NOT the whole frame. Fed a full
		// frame it stops discriminating and calls everything real (a photo scored 1.000).
		// The 2.7 context crop is that training framing. RGB, /255, softmax[0].
		guard
			let crop = FaceAligner.contextCrop(sample, side: side, margin: Liveness.cropMargin),
			let tensor = Self.tensor(from: crop, side: side),
			let out = try? model.prediction(
				from: try MLDictionaryFeatureProvider(
					dictionary: [inputName: MLFeatureValue(multiArray: tensor)])),
			let array = firstMultiArray(out), array.count >= 2
		else { return nil }

		// Class 1 is "real" for this model at this serving (see serving-finder note above).
		let real = array[1].floatValue
		let spoof = array[0].floatValue
		let m = max(real, spoof)
		let er = exp(real - m), es = exp(spoof - m)
		return er / (er + es)
	}

	private func firstMultiArray(_ out: MLFeatureProvider) -> MLMultiArray? {
		guard let name = out.featureNames.first(where: {
			out.featureValue(for: $0)?.multiArrayValue != nil
		}) else { return nil }
		return out.featureValue(for: name)?.multiArrayValue
	}

	/// BGRA crop → planar RGB `[1,3,side,side]`, `(x - 127.5) / 128` — the serving
	/// convention this model separates on (see the threshold note in `init`).
	private static func tensor(from buffer: CVPixelBuffer, side: Int) -> MLMultiArray? {
		guard
			let array = try? MLMultiArray(
				shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
		else { return nil }

		CVPixelBufferLockBaseAddress(buffer, .readOnly)
		defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
		guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

		let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
		let pixels = base.assumingMemoryBound(to: UInt8.self)
		let out = array.dataPointer.assumingMemoryBound(to: Float32.self)
		let plane = side * side

		for y in 0..<side {
			let row = pixels + y * rowBytes
			for x in 0..<side {
				let px = row + x * 4  // BGRA
				let b = Float32(px[0]), g = Float32(px[1]), r = Float32(px[2])
				let i = y * side + x
				out[i] = (r - 127.5) / 128
				out[plane + i] = (g - 127.5) / 128
				out[2 * plane + i] = (b - 127.5) / 128
			}
		}
		return array
	}
}
