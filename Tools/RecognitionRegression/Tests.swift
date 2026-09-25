import CoreVideo
import Foundation
import Vision

// No camera, model weights, credentials or enrolled user data. Production matching,
// preprocessing, quality, enrollment and evaluator code is compiled above unchanged.
struct FaceSample: @unchecked Sendable {
	var boundingBox = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
	var pose = FacePose.zero
	var quality: Float = 0.8
	var hasQualityMeasurement = true
	let pixelBuffer: CVPixelBuffer
	var candidate: Faceprint?
	var landmarks: VNFaceLandmarks2D { fatalError("Synthetic tests do not fabricate Vision landmarks") }
}

struct FaceEnrollment: Sendable {
	var id = UUID()
	var prints: [Faceprint]
}

struct FixtureEmbedder: FaceEmbedder {
	var identifier = "coreml:test"
	let usesCosineSimilarity = true
	var matchThreshold: Float = 0.45
	func embed(_ sample: FaceSample) -> Faceprint? { sample.candidate }
}

@main
enum RecognitionTests {
	static var checks = 0
	static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
		precondition(condition(), message)
		checks += 1
	}
	static func printAt(_ cosine: Float, source: String = "coreml:test") -> Faceprint {
		Faceprint(values: [cosine, sqrt(max(0, 1 - cosine * cosine))], source: source)
	}
	static func rejects(_ matcher: FaceTemplateMatcher, _ candidate: Faceprint) -> Bool {
		do { _ = try matcher.bestMatch(to: candidate); return false } catch { return true }
	}
	static func buffer(width: Int = 640, height: Int = 480) -> CVPixelBuffer {
		var result: CVPixelBuffer?
		precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
			kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess)
		return result!
	}

	@MainActor
	static func main() async throws {
		let embedder = FixtureEmbedder()
		let candidate = printAt(1)
		func index(_ prints: [[Faceprint]]) -> FaceTemplateMatcher {
			FaceTemplateMatcher(templates: prints, embedder: embedder)
		}
		check(Faceprint.normalized([0, 0], source: "test") == nil, "Zero vectors rejected")
		check(Faceprint.normalized([.nan, 1], source: "test") == nil, "NaN rejected")
		check(Faceprint.normalized([.infinity, 1], source: "test") == nil, "Infinity rejected")
		check(Faceprint.normalized([1], source: "") == nil, "Empty source rejected")
		let singleton = try index([[candidate]]).bestMatch(to: candidate)
		check(singleton?.score == 1, "Legacy single print remains usable")
		let isolated = try index([[candidate, printAt(0.2), printAt(0.1)]]).bestMatch(to: candidate)
		check(abs(isolated!.score - 0.2) < 0.00001, "Isolated high score cannot dominate")
		let supported = try index([[printAt(0.9), printAt(0.8), printAt(0.1)]]).bestMatch(to: candidate)
		check(abs(supported!.score - 0.8) < 0.00001, "Two supporting poses pass")
		let separate = try index([[candidate, printAt(0.1)], [candidate, printAt(0.2)]]).bestMatch(to: candidate)
		check(separate!.score < embedder.matchThreshold, "Support never pooled across identities")
		let selected = try index([[candidate, printAt(0.1)], [printAt(0.8), printAt(0.7)]]).bestMatch(to: candidate)
		check(selected?.index == 1, "Select face with supported score, not highest outlier")
		check(rejects(index([[candidate]]), printAt(1, source: "wrong")), "Cross-model candidate rejected")
		check(rejects(index([[printAt(1, source: "wrong")]]), candidate), "Cross-model template rejected")
		check(rejects(index([[Faceprint(values: [1, .nan], source: embedder.identifier)]]), candidate), "Corrupt template rejected")
		check(rejects(index([[Faceprint(values: [1], source: embedder.identifier)]]), candidate), "Wrong dimension rejected")
		check(rejects(index([[]]), candidate), "Empty enrollment rejected")
		check(rejects(index([[candidate]]), Faceprint(values: [0, 0], source: embedder.identifier)), "Zero candidate rejected")

		// Optimized cosine agrees with the scalar reference across non-normalized inputs.
		for seed in 1...100 {
			let vectors = (0..<8).map { row in Faceprint(values: (0..<128).map { column in
				Float(sin(Double(seed * 131 + row * 17 + column)))
			}, source: embedder.identifier) }
			let query = vectors[seed % vectors.count]
			let expected = vectors.map { $0.similarity(to: query) }.sorted(by: >)[1]
			let actual = try index([vectors]).bestMatch(to: query)!.score
			check(abs(actual - max(0, expected)) < 0.00001, "Accelerated score agrees with scalar cosine")
		}
		let geometry = LandmarkEmbedder()
		let geometryPrint = Faceprint(values: [0.1, 0.2, 0.4, 0.6], source: geometry.identifier)
		let geometryMatch = try FaceTemplateMatcher(templates: [[geometryPrint]], embedder: geometry).bestMatch(to: geometryPrint)
		check(geometryMatch?.score == 1, "Landmark distance dispatch is preserved")
		let shifted = Faceprint(values: [0.13, 0.2, 0.43, 0.6], source: geometry.identifier)
		check(abs(geometry.similarity(geometryPrint, shifted) - 0.75) < 0.00001,
			"Accelerated geometry preserves per-point RMS distance")
		let invalidGeometry = Faceprint(values: [.nan, 0.2, 0.4, 0.6], source: geometry.identifier)
		check(geometry.similarity(geometryPrint, invalidGeometry) == 0, "Nonfinite geometry rejected")

		var sample = FaceSample(pixelBuffer: buffer(), candidate: candidate)
		check(FrameQuality.isUsable(sample), "Good frame usable")
		sample.quality = 0
		check(FrameQuality.rejection(sample) == .tooBlurred, "Measured zero rejected")
		sample.hasQualityMeasurement = false
		check(FrameQuality.isUsable(sample), "Absent quality distinguished from zero")
		sample.quality = .nan
		check(FrameQuality.rejection(sample) == .invalidMeasurements, "Nonfinite quality rejected")
		sample.quality = 0.8
		sample.hasQualityMeasurement = true
		let evaluator = UnlockFrameEvaluator(embedder: embedder,
			faces: [FaceEnrollment(prints: [candidate, printAt(0.8)])], antiSpoof: nil)
		let good = await evaluator.evaluate(sample)
		check(good.matched && good.permitsMatchHold(requiresAntiSpoof: false), "Evaluator uses prepared agreement")
		check(!good.permitsMatchHold(requiresAntiSpoof: true), "Identity cannot bypass required anti-spoof")
		sample.quality = 0
		let bad = await evaluator.evaluate(sample)
		check(bad.failure == .unusableFrame && !bad.comparedIdentity, "Quality rejects before inference")
		sample.quality = 0.8

		let enrollment = EnrollmentModel(embedder: embedder)
		sample.pose = FacePose(yaw: .nan, pitch: 0, roll: 0)
		enrollment.consume(sample)
		check(enrollment.captureStatus == .invalidMeasurements, "Invalid pose cannot reach ring indexing")
		sample.pose = .zero
		for _ in 0..<9 { enrollment.consume(sample) }
		check(enrollment.prints.count == 1, "Frontal anchor captured")
		sample.pose = FacePose(yaw: 0.2, pitch: 0, roll: 0)
		sample.candidate = printAt(0.1)
		enrollment.consume(sample)
		check(enrollment.prints.count == 1 && enrollment.progress == 0, "Identity switch saves no print or coverage")
		check(enrollment.captureStatus == .inconsistentFace, "Identity mismatch reported")
		sample.candidate = printAt(0.8)
		enrollment.consume(sample)
		check(enrollment.prints.count == 2 && enrollment.progress > 0, "Consistent turned face accepted")

		// A crop larger than the source's short side must still fill every output row.
		let source = sample.pixelBuffer
		CVPixelBufferLockBaseAddress(source, [])
		memset(CVPixelBufferGetBaseAddress(source), 255, CVPixelBufferGetDataSize(source))
		CVPixelBufferUnlockBaseAddress(source, [])
		sample.boundingBox = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
		let crop = FaceAligner.contextCrop(sample, side: 80)!
		CVPixelBufferLockBaseAddress(crop, .readOnly)
		let pixels = CVPixelBufferGetBaseAddress(crop)!.assumingMemoryBound(to: UInt8.self)
		let stride = CVPixelBufferGetBytesPerRow(crop)
		check((0..<80).allSatisfy { pixels[$0 * stride + 40 * 4 + 3] > 250 }, "Oversized crop has no transparent bands")
		CVPixelBufferUnlockBaseAddress(crop, .readOnly)
		check(FaceAligner.contextCrop(sample, side: 80, margin: .nan) == nil, "Nonfinite margin rejected")
		benchmark(embedder: embedder)
		Swift.print("Recognition regression: \(checks) checks passed")
	}

	static func benchmark(embedder: FixtureEmbedder) {
		let vectors = (0..<64).map { row in Faceprint(values: (0..<512).map { column in
			Float(sin(Double(row * 17 + column)))
		}, source: embedder.identifier) }
		let query = vectors[0]
		let matcher = FaceTemplateMatcher(templates: [vectors], embedder: embedder)
		let iterations = 2000
		var checksum: Float = 0
		let scalarStart = ContinuousClock.now
		for _ in 0..<iterations {
			checksum += vectors.reduce(Float(0)) { max($0, $1.similarity(to: query)) }
		}
		let scalar = scalarStart.duration(to: .now)
		let preparedStart = ContinuousClock.now
		for _ in 0..<iterations { checksum += (try! matcher.bestMatch(to: query))!.score }
		let prepared = preparedStart.duration(to: .now)
		Swift.print("Synthetic 64 × 512 matching, \(iterations) queries: scalar best-only \(scalar), prepared two-template agreement \(prepared); checksum \(checksum)")
	}
}
