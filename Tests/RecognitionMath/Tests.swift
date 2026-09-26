import CoreVideo
import Foundation
import Vision

struct FaceSample {
	let landmarks: VNFaceLandmarks2D
	let boundingBox: CGRect
	let pixelBuffer: CVPixelBuffer
}

@main
enum RecognitionMathTests {
	static func main() {
		var checks = 0
		func check(_ condition: @autoclosure () -> Bool, _ message: String) {
			precondition(condition(), message)
			checks += 1
		}
		let source = "generated-math-fixture"
		let unit = Faceprint.normalized([3, 4], source: source)!
		check(unit.values == [0.6, 0.8], "Normalization keeps the existing numeric convention")
		check(abs(unit.similarity(to: unit) - 1) < 0.000001, "Unit vector matches itself")
		let opposite = Faceprint(values: unit.values.map { -$0 }, source: source)
		check(abs(unit.similarity(to: opposite) + 1) < 0.000001, "Cosine sign is preserved")
		check(unit.similarity(to: Faceprint(values: unit.values, source: "other")) == 0, "Different feature spaces cannot match")
		check(unit.similarity(to: Faceprint(values: [1], source: source)) == 0, "Dimension mismatch is denied")
		check(Faceprint.normalized([], source: source) == nil, "Empty vector is not an enrollment")
		check(Faceprint.normalized([0, 0], source: source) == nil, "Zero vector cannot normalize")
		check(Faceprint.normalized([1, 0], source: "") == nil, "A print needs a feature-space identifier")
		check(Faceprint(values: [1, 0], source: "").similarity(to: Faceprint(values: [1, 0], source: "")) == 0,
			"Unidentified feature spaces cannot match each other")
		let landmarks = LandmarkEmbedder()
		check(landmarks.similarity(Faceprint(values: [1], source: source), Faceprint(values: [1], source: source)) == 0,
			"Landmarks require complete coordinate pairs")
		for value: Float in [.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
			let invalid = Faceprint(values: [value, 1], source: source)
			check(Faceprint.normalized(invalid.values, source: source) == nil, "Invalid or overflowing model output is rejected")
			check(invalid.similarity(to: unit) == 0, "Bad reference cannot produce a match")
			check(unit.similarity(to: invalid) == 0, "Bad candidate cannot produce a match")
			check(landmarks.similarity(invalid, unit) == 0, "Bad coordinate distances cannot produce a match")
		}
		var state: UInt64 = 20260913
		func randomValue() -> Float {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Float(Double(state >> 32) / Double(UInt32.max) * 2 - 1)
		}
		for count in [2, 128, 512] {
			for _ in 0..<40 {
				let raw = (0..<count).map { _ in randomValue() }
				var oldNorm: Float = 0
				for value in raw { oldNorm += value * value }
				oldNorm = sqrt(oldNorm)
				let normalized = Faceprint.normalized(raw, source: source)!
				check(zip(normalized.values, raw.map { $0 / oldNorm }).allSatisfy { abs($0 - $1) <= 1e-6 }, "Valid model output normalization is unchanged")
				check(normalized.values.allSatisfy(\.isFinite), "Valid output remains finite")
				check(abs(normalized.similarity(to: normalized) - 1) < 0.00001, "Generated valid vectors preserve self-similarity")
			}
		}
		print("PASS: \(checks) recognition-math checks; generated vectors only, no camera, face data, models, credentials or thresholds changed.")
	}
}
