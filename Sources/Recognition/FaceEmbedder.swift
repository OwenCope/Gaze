import Accelerate
import CoreML
import CoreVideo
import Foundation
import Vision

/// A fixed-length numeric description of a face, comparable by cosine similarity.
struct Faceprint: Codable, Sendable, Equatable {
	var values: [Float]
	/// Which embedder produced it. Prints from different embedders are never comparable.
	var source: String

	static func normalized(_ values: [Float], source: String) -> Faceprint? {
		guard !source.isEmpty, !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
		var energy: Float = 0
		vDSP_svesq(values, 1, &energy, vDSP_Length(values.count))
		guard energy.isFinite, energy > 0 else { return nil }
		var norm = sqrt(energy)
		var normalized = [Float](repeating: 0, count: values.count)
		vDSP_vsdiv(values, 1, &norm, &normalized, 1, vDSP_Length(values.count))
		return Faceprint(values: normalized, source: source)
	}

	/// Cosine similarity, 0...1 for learned embeddings (all produce non-negative prints
	/// or are L2-normalised, so negative similarity means the inputs are unrelated).
	///
	/// Do not call this directly on landmark prints: cosine is wrong for them (nearly
	/// identical canonical positions score ~1.0 for anyone). Use
	/// `FaceEmbedder.similarity(_:_:)` via dynamic dispatch instead.
	func similarity(to other: Faceprint) -> Float {
		if source.hasPrefix("landmark") || other.source.hasPrefix("landmark") {
			assertionFailure("Use FaceEmbedder.similarity(_:_:) via dynamic dispatch — Faceprint.similarity(to:) is cosine-only and wrong for landmark prints.")
			return 0
		}
		guard !source.isEmpty, source == other.source, !values.isEmpty,
			values.count == other.values.count else { return 0 }
		var dot: Float = 0, a: Float = 0, b: Float = 0
		for i in values.indices {
			dot += values[i] * other.values[i]
			a += values[i] * values[i]
			b += other.values[i] * other.values[i]
		}
		guard dot.isFinite, a.isFinite, b.isFinite, a > 0, b > 0 else { return 0 }
		let score = dot / (sqrt(a) * sqrt(b))
		return score.isFinite ? score : 0
	}
}

protocol FaceEmbedder: Sendable {
	var identifier: String { get }
	/// Opts into normalized vector matching. Custom metrics default to dynamic dispatch.
	var usesCosineSimilarity: Bool { get }
	/// The similarity above which two prints are considered the same person.
	var matchThreshold: Float { get }
	func embed(_ sample: FaceSample) -> Faceprint?
	/// How alike two prints are, 0...1.
	///
	/// Part of the embedder rather than of `Faceprint` because the right metric depends
	/// entirely on what the numbers mean. Learned embeddings are trained so that angle
	/// carries identity, and cosine is correct for them. Raw coordinates are not: see
	/// `LandmarkEmbedder`.
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float
}

extension FaceEmbedder {
	var usesCosineSimilarity: Bool { false }
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float { a.similarity(to: b) }
}

// MARK: - Selection

enum Embedders {
	/// The Core ML embedder when a model is bundled, otherwise the geometry fallback.
	///
	/// Local weights at `Resources/FaceEmbedding.mlpackage` are compiled by build.sh.
	/// Their distribution rights are tracked separately in NOTICE.md; a source-code
	/// license does not establish the license of a weight file. The geometry fallback
	/// remains available for practice, but UnlockGuard refuses it for Mac unlocking.
	// The signed app bundle is immutable for the lifetime of this process. Reuse the
	// model for enrollment, scans and readiness checks; a new build needs a relaunch.
	private static let selected: any FaceEmbedder = CoreMLEmbedder() ?? LandmarkEmbedder()

	static func best() -> FaceEmbedder {
		selected
	}
}

// MARK: - Landmark geometry (no model required)

/// Describes a face by the *shape* of its landmarks, in a pose-normalised frame.
///
/// This is the honest floor of what is achievable with zero model weights. It encodes
/// bone geometry — eye spacing, nose width, jaw outline — which is stable, but it
/// throws away skin, texture and colour, which is most of what separates two people
/// with similar face shapes. Expect it to distinguish you from a stranger and to
/// struggle with siblings. Treat it as convenience-grade until a model is dropped in.
struct LandmarkEmbedder: FaceEmbedder {
	let identifier = "landmark-geometry-v2"
	let matchThreshold: Float = 0.55

	/// Distance between corresponding landmarks, not the angle between the vectors.
	///
	/// Cosine similarity was measurably wrong here — it scored a completely different
	/// person at 1.000. After normalisation every face has its eyes, nose and mouth in
	/// nearly the same canonical positions, so the vectors are dominated by that shared
	/// template and come out parallel no matter whose face it is. Identity lives in the
	/// small residual displacement, which is exactly what an angle discards.
	///
	/// So: root-mean-square displacement, in interocular widths, mapped to 0...1. Same
	/// person lands around 0.02–0.04 RMS; different people are several times that.
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float {
		guard !a.source.isEmpty, a.source == b.source, a.values.count == b.values.count,
			!a.values.isEmpty, a.values.count.isMultiple(of: 2)
		else { return 0 }

		var sumSquares: Float = 0
		vDSP_distancesq(a.values, 1, b.values, 1, &sumSquares, vDSP_Length(a.values.count))
		guard sumSquares.isFinite else { return 0 }
		// Two coordinates per landmark, so halve the count to get per-point displacement.
		let rms = sqrt(sumSquares / Float(a.values.count / 2))

		// 0.12 interocular widths of average displacement is treated as "unrelated".
		// Tuned against real measurements from the Test Recognition screen rather than
		// guessed — check both a matching and a non-matching face after changing it.
		return max(0, 1 - rms / 0.12)
	}

	func embed(_ sample: FaceSample) -> Faceprint? {
		let lm = sample.landmarks

		// Anchor on the pupils. Everything is expressed relative to them, which cancels
		// out distance from the camera, head tilt and where the face sits in frame.
		guard
			let leftPupil = lm.leftPupil?.normalizedPoints.first,
			let rightPupil = lm.rightPupil?.normalizedPoints.first
		else { return nil }

		let origin = CGPoint(
			x: (leftPupil.x + rightPupil.x) / 2,
			y: (leftPupil.y + rightPupil.y) / 2)
		let axis = CGVector(dx: rightPupil.x - leftPupil.x, dy: rightPupil.y - leftPupil.y)
		let interocular = hypot(axis.dx, axis.dy)
		guard interocular > 0.01 else { return nil }

		// Rotate so the eye line is horizontal, scale so the eyes are one unit apart.
		let cosT = axis.dx / interocular
		let sinT = axis.dy / interocular

		func canonical(_ p: CGPoint) -> (Float, Float) {
			let dx = (p.x - origin.x) / interocular
			let dy = (p.y - origin.y) / interocular
			return (Float(dx * cosT + dy * sinT), Float(-dx * sinT + dy * cosT))
		}

		// Ordered so the same index always means the same facial position.
		let regions: [VNFaceLandmarkRegion2D?] = [
			lm.faceContour, lm.leftEye, lm.rightEye, lm.leftEyebrow, lm.rightEyebrow,
			lm.nose, lm.noseCrest, lm.medianLine, lm.outerLips, lm.innerLips,
		]

		var values: [Float] = []
		values.reserveCapacity(160)
		for region in regions {
			guard let region else { return nil }
			for point in region.normalizedPoints {
				let (x, y) = canonical(point)
				values.append(x)
				values.append(y)
			}
		}

		guard values.count >= 40 else { return nil }
		return Faceprint(values: values, source: identifier)
	}
}

// MARK: - Core ML

/// Wraps the bundled embedding model: one square NCHW RGB tensor input and one
/// multi-array output. Models with a different preprocessing contract are rejected.
///
/// `@unchecked` because `MLModel` is not marked `Sendable`. Copies share a lock
/// that serializes predictions; each caller owns its crop and input tensor.
struct CoreMLEmbedder: FaceEmbedder, @unchecked Sendable {
	let identifier: String
	let usesCosineSimilarity = true
	/// Historical operating point, not a calibrated false-accept guarantee. Repeated
	/// webcam frames are correlated; holding a match cannot make a weak threshold safe.
	/// Template agreement and movement checks supplement this threshold. Population
	/// and low-light validation are still required with the actual bundled weights.
	let matchThreshold: Float = 0.45

	private let model: MLModel
	private let predictionLock = NSLock()
	private let inputName: String
	private let outputName: String
	private let side: Int

	/// Bump whenever the bundled model file changes. It becomes part of the print's
	/// `source`, and prints with different sources never compare (similarity returns 0).
	/// So swapping models can't silently mis-match faceprints from the old embedding
	/// space against the new one — it invalidates old enrolments and forces a re-enrol.
	static let modelTag = "arcface-2.73"

	init?() {
		guard
			let url = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc"),
			let model = try? MLModel(contentsOf: url)
		else { return nil }

		// Models in this family take a planar [1, 3, S, S] tensor rather than an image
		// feature, so accept a multi-array input and read the side length from its shape.
		let inputs = model.modelDescription.inputDescriptionsByName
		let outputs = model.modelDescription.outputDescriptionsByName
		guard
			inputs.count == 1, let input = inputs.values.first,
			let constraint = input.multiArrayConstraint,
			constraint.shape.count == 4,
			constraint.shape[0].intValue == 1, constraint.shape[1].intValue == 3,
			constraint.shape[2] == constraint.shape[3],
			(16...1024).contains(constraint.shape[3].intValue),
			outputs.count == 1, let output = outputs.values.first,
			output.multiArrayConstraint != nil
		else { return nil }

		self.model = model
		self.inputName = input.name
		self.outputName = output.name
		self.side = constraint.shape[3].intValue
		// Version the identifier so swapping models invalidates old enrolments rather
		// than silently comparing prints from different feature spaces.
		self.identifier = "coreml:\(self.side)x\(self.side):\(Self.modelTag)"
	}

	func embed(_ sample: FaceSample) -> Faceprint? {
		guard
			let crop = FaceAligner.alignedCrop(sample, side: side),
			let tensor = Self.tensor(from: crop, side: side),
			let output = predictionLock.withLock({
				try? model.prediction(from: try MLDictionaryFeatureProvider(
					dictionary: [inputName: MLFeatureValue(multiArray: tensor)]))
			}),
			let array = output.featureValue(for: outputName)?.multiArrayValue,
			(1...4096).contains(array.count)
		else { return nil }

		// L2-normalise. These embeddings are trained so identity lives in direction, not
		// magnitude, so normalising makes cosine similarity a plain dot product and keeps
		// scores comparable across lighting.
		var values = [Float](repeating: 0, count: array.count)
		for i in 0..<array.count {
			let v = array[i].floatValue
			values[i] = v
		}
		return Faceprint.normalized(values, source: identifier)
	}

	/// Converts a BGRA crop into the planar RGB tensor the model expects.
	///
	/// Two conversions matter and both are easy to get subtly wrong: the buffer is BGRA
	/// and interleaved, while the model wants RGB in separate channel planes; and pixels
	/// must be scaled to [-1, 1] rather than [0, 1], which is the convention this model
	/// family is trained with. Getting either wrong yields embeddings that look valid but
	/// match nobody.
	private static func tensor(from buffer: CVPixelBuffer, side: Int) -> MLMultiArray? {
		guard
			let array = try? MLMultiArray(
				shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
		else { return nil }

		guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
			CVPixelBufferGetWidth(buffer) == side, CVPixelBufferGetHeight(buffer) == side,
			CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
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
				out[i] = (r - 127.5) / 128.0
				out[plane + i] = (g - 127.5) / 128.0
				out[2 * plane + i] = (b - 127.5) / 128.0
			}
		}

		return array
	}
}
