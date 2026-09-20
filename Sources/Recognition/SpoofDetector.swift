import CoreML
import CoreVideo
import Foundation
import Vision

/// Object-detection anti-spoof.
///
/// Runs the Roboflow-trained detector (`scripts/train_spoof.swift`) on the whole frame and
/// reports how confidently it sees a *spoof* — a held phone, a screen, a printed photo.
/// From that dataset, class `"1"` is a spoof and `"0"` is a live face.
///
/// This is a different signal from the passive texture model (`CoreMLLiveness`): it looks
/// for the *device* in the scene rather than judging the face's texture, so it catches the
/// held-photo attack that texture can't. Runs on the full frame because the tell — a bezel,
/// a hand, a screen edge — usually sits outside the face box.
/// `@unchecked` because `VNCoreMLModel` is not marked `Sendable`, though running a request
/// against it is thread-safe — same reason as `CoreMLEmbedder` and `CoreMLLiveness`.
struct SpoofDetector: @unchecked Sendable {

	/// The dataset's spoof class. `"0"` is a live face.
	static let spoofLabel = "1"

	/// Confidence above which a spoof detection counts as a spoof.
	let threshold: Float = 0.5

	private let model: VNCoreMLModel

	init?() {
		guard
			let url = Bundle.main.url(forResource: "Spoof", withExtension: "mlmodelc"),
			let ml = try? MLModel(contentsOf: url),
			let vn = try? VNCoreMLModel(for: ml)
		else { return nil }
		self.model = vn
	}

	static var isAvailable: Bool {
		Bundle.main.url(forResource: "Spoof", withExtension: "mlmodelc") != nil
	}

	/// Strongest "spoof" detection in the frame, 0…1 (0 when nothing spoof-like is seen).
	func spoofConfidence(_ sample: FaceSample) -> Float? {
		let request = VNCoreMLRequest(model: model)
		request.imageCropAndScaleOption = .scaleFill
		let handler = VNImageRequestHandler(cvPixelBuffer: sample.pixelBuffer, options: [:])
		do { try handler.perform([request]) } catch { return nil }
		guard let objects = request.results as? [VNRecognizedObjectObservation] else { return nil }
		var best: Float = 0
		for object in objects {
			guard let top = object.labels.first else { continue }
			guard top.confidence.isFinite, (0...1).contains(top.confidence) else { return nil }
			if top.identifier == Self.spoofLabel {
				best = max(best, top.confidence)
			}
		}
		return best
	}
}
