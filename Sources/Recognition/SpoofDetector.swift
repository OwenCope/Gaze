import CoreML
import CoreVideo
import Foundation
import Vision

/// Face-crop classification anti-spoof.
///
/// Runs the Roboflow-trained classifier (`scripts/train_spoof.swift`) on the face crop and
/// reports how confidently it sees a *spoof* — a held phone, a screen, a printed photo.
/// From that dataset, class `"1"` is a spoof and `"0"` is a live face.
///
/// This is a different signal from the passive texture model (`CoreMLLiveness`): it judges
/// the face region itself rather than the face's texture, so it catches the held-photo
/// attack that texture can't. Runs on the `contextCrop` (face plus margin) rather than the
/// whole frame, so background clutter outside the face can't sway the verdict — while the
/// margin keeps the tells at the edges (a bezel, a screen edge, paper border) in frame.
/// `@unchecked` because `VNCoreMLModel` is not marked `Sendable`, though running a request
/// against it is thread-safe — same reason as `CoreMLEmbedder` and `CoreMLLiveness`.
struct SpoofDetector: @unchecked Sendable {

	/// The dataset's spoof class. `"0"` is a live face.
	static let spoofLabel = "1"

	/// Shared instance: loading the model is expensive and was previously done per scan.
	static let shared: SpoofDetector? = SpoofDetector()

	private let slot: ModelSlot<VNCoreMLModel>
	private let side: Int
	/// The shipped `Spoof.mlmodel` is still the Roboflow *object detector* (boxes plus
	/// labels, trained on whole frames). Reading it as a classifier returned nil on every
	/// frame, so each matched face was refused as "anti-spoof unavailable" and unlocking
	/// failed instantly. Detected from the model's outputs, so swapping in a classifier
	/// later needs no code change.
	private let isDetector: Bool

	init?() {
		guard
			let url = Bundle.main.url(forResource: "Spoof", withExtension: "mlmodelc"),
			let ml = try? MLModel(contentsOf: url),
			let vn = try? VNCoreMLModel(for: ml)
		else { return nil }
		self.slot = ModelSlot(
			load: {
				guard let ml = try? MLModel(contentsOf: url),
					let vn = try? VNCoreMLModel(for: ml)
				else { return nil }
				return vn
			},
			initial: vn)
		self.side = ml.modelDescription.inputDescriptionsByName.values.first(where: {
			$0.type == .image
		})?.imageConstraint?.pixelsWide ?? 224
		self.isDetector = ml.modelDescription.outputDescriptionsByName["coordinates"] != nil
	}

	static var isAvailable: Bool {
		Bundle.main.url(forResource: "Spoof", withExtension: "mlmodelc") != nil
	}

	/// "Spoof" classification confidence for the face crop, 0…1 (nil when unevaluable).
	/// Runs one throwaway request so the first matched frame doesn't pay for loading the model.
	func warmUp() {
		slot.preload()
		guard let model = slot.withModel({ $0 }) else { return }
		var buffer: CVPixelBuffer?
		guard CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
			let buffer else { return }
		let request = VNCoreMLRequest(model: model)
		request.imageCropAndScaleOption = .scaleFill
		try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
	}

	func spoofConfidence(_ sample: FaceSample) -> Float? {
		if isDetector { return detectedSpoofConfidence(sample) }
		guard let model = slot.withModel({ $0 }) else { return nil }
		guard let crop = FaceAligner.contextCrop(sample, side: side) else { return nil }
		let request = VNCoreMLRequest(model: model)
		request.imageCropAndScaleOption = .scaleFill
		let handler = VNImageRequestHandler(cvPixelBuffer: crop, options: [:])
		do { try handler.perform([request]) } catch { return nil }
		guard let classes = request.results as? [VNClassificationObservation] else { return nil }
		guard let spoof = classes.first(where: { $0.identifier == Self.spoofLabel }) else { return nil }
		guard spoof.confidence.isFinite, (0...1).contains(spoof.confidence) else { return nil }
		return spoof.confidence
	}

	/// Strongest "spoof" detection in the whole frame, 0…1 (0 when nothing spoof-like is
	/// seen). Full frame because that is what the detector was trained and measured on
	/// (see `AntiSpoofGate.spoofRejectThreshold`), and the tell usually sits outside the face.
	private func detectedSpoofConfidence(_ sample: FaceSample) -> Float? {
		guard let model = slot.withModel({ $0 }) else { return nil }
		let request = VNCoreMLRequest(model: model)
		request.imageCropAndScaleOption = .scaleFill
		let handler = VNImageRequestHandler(cvPixelBuffer: sample.pixelBuffer, options: [:])
		do { try handler.perform([request]) } catch { return nil }
		guard let objects = request.results as? [VNRecognizedObjectObservation] else { return nil }
		var best: Float = 0
		for object in objects {
			guard let top = object.labels.first else { continue }
			guard top.confidence.isFinite, (0...1).contains(top.confidence) else { return nil }
			if top.identifier == Self.spoofLabel { best = max(best, top.confidence) }
		}
		return best
	}
}
