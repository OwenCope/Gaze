import CoreML
import Foundation

/// Optional anti-spoof check, off by default.
///
/// What it catches: someone holding a printed photo or a phone screen up to the camera.
/// The models in this family (MiniFASNet and relatives, trained on CelebA-Spoof) score
/// *capture artefacts* — moiré from a display, paper grain, print edges, the flatness of
/// a reflected highlight.
///
/// What it does not catch: frame injection. A virtual camera feeding a recording produces
/// no capture artefacts, because nothing was filmed, and these models happily call it
/// genuine. `CameraDevice` is what defends against that, and it is on by default while
/// this is not.
protocol LivenessDetector: Sendable {
	var identifier: String { get }
	/// Score above which a frame is treated as a real face in front of the lens.
	var threshold: Float { get }
	func score(_ sample: FaceSample) -> Float?
}

enum Liveness {
	/// The detector to use, or nil when none is available.
	///
	/// Nil is the normal state: no model ships with the app, since Sapphire's `MiniFAS`
	/// weights come from a GPL-3.0 repository we are not copying from. Drop a compatible
	/// model at `Resources/Liveness.mlpackage` to enable the feature.
	static func detector() -> LivenessDetector? {
		CoreMLLiveness()
	}

	static var isAvailable: Bool { detector() != nil }
}

/// Wraps a bundled anti-spoof model: one image input, one score output.
struct CoreMLLiveness: LivenessDetector, @unchecked Sendable {
	let identifier: String
	/// The conventional operating point for this model family — the same cut-off
	/// Sapphire uses. Lower admits more spoofs; higher rejects more real faces.
	let threshold: Float = 0.85

	private let model: MLModel
	private let inputName: String
	private let side: Int

	init?() {
		guard
			let url = Bundle.main.url(forResource: "Liveness", withExtension: "mlmodelc"),
			let model = try? MLModel(contentsOf: url),
			let image = model.modelDescription.inputDescriptionsByName
				.first(where: { $0.value.type == .image })?.value,
			let constraint = image.imageConstraint
		else { return nil }

		self.model = model
		self.inputName = image.name
		self.side = constraint.pixelsWide
		self.identifier = "coreml-liveness:\(constraint.pixelsWide)"
	}

	func score(_ sample: FaceSample) -> Float? {
		// Deliberately a looser crop than recognition uses: the tell-tales live at the
		// edges — a screen bezel, the border of a sheet of paper — so cropping tightly
		// to the face throws away the evidence.
		guard
			let crop = FaceAligner.alignedCrop(sample, side: side),
			let output = try? model.prediction(
				from: try MLDictionaryFeatureProvider(
					dictionary: [inputName: MLFeatureValue(pixelBuffer: crop)])),
			let name = output.featureNames.first(where: {
				output.featureValue(for: $0)?.multiArrayValue != nil
			}),
			let array = output.featureValue(for: name)?.multiArrayValue,
			array.count > 0
		else { return nil }

		// Two-class models put the genuine score at index 1; single-output models put it
		// at index 0.
		return array.count >= 2 ? array[1].floatValue : array[0].floatValue
	}
}
