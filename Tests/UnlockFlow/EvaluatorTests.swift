import CoreVideo
import Foundation
import Vision

struct FaceSample: @unchecked Sendable {
	// Zero-filled buffer: black, so the passive deny cues (which now run inside the
	// real evaluator on live verdicts) measure nothing on fixture frames.
	var pixelBuffer: CVPixelBuffer = FaceSample.makeBuffer()
	var boundingBox = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
	// Never populated on fixtures: alignedCrop must not be called on these (only the
	// context-crop path runs here). IUO so the member access in FaceAligner compiles.
	var landmarks: VNFaceLandmarks2D! = nil
	static func makeBuffer() -> CVPixelBuffer {
		var buffer: CVPixelBuffer?
		precondition(
			CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
				== kCVReturnSuccess && buffer != nil, "synthetic buffer must allocate")
		let locked = buffer!
		CVPixelBufferLockBaseAddress(locked, [])
		defer { CVPixelBufferUnlockBaseAddress(locked, []) }
		memset(CVPixelBufferGetBaseAddress(locked), 0,
			CVPixelBufferGetBytesPerRow(locked) * CVPixelBufferGetHeight(locked))
		return locked
	}
}
struct Faceprint: Sendable { let value: Float }
protocol FaceEmbedder: Sendable {
	var matchThreshold: Float { get }
	func embed(_ sample: FaceSample) -> Faceprint?
}
struct FaceEnrollment: Sendable {
	let id: UUID
	func bestSimilarity(to candidate: Faceprint, using embedder: any FaceEmbedder) -> Float { candidate.value }
}
struct AntiSpoofGate: Sendable {
	enum Decision: Equatable, Sendable { case live, unavailable, spoof(reason: String, score: Float) }
	let result: Decision
	func evaluate(_ sample: FaceSample) -> Decision { result }
}
struct TestEmbedder: FaceEmbedder {
	var matchThreshold: Float = 0.45
	var value: Float? = 0.8
	func embed(_ sample: FaceSample) -> Faceprint? {
		guard !Thread.isMainThread else { return Faceprint(value: .nan) }
		return value.map { Faceprint(value: $0) }
	}
}

final class ControlledEmbedder: FaceEmbedder, @unchecked Sendable {
	let matchThreshold: Float = 0.45
	let began = DispatchSemaphore(value: 0)
	let resume = DispatchSemaphore(value: 0)
	func embed(_ sample: FaceSample) -> Faceprint? {
		began.signal()
		guard resume.wait(timeout: .now() + 3) == .success else { return nil }
		return Faceprint(value: 0.8)
	}
}

@main @MainActor
enum EvaluatorTests {
	static func main() async {
		let face = FaceEnrollment(id: UUID())
		let evaluator = UnlockFrameEvaluator(embedder: TestEmbedder(), faces: [face], antiSpoof: AntiSpoofGate(result: .live))
		let accepted = await evaluator.evaluate(FaceSample())
		precondition(accepted.matched && accepted.face?.id == face.id && accepted.spoofDecision == .live)
		var checks = 1
		for matched in [false, true] {
			for hasFace in [false, true] {
				for decision: AntiSpoofGate.Decision? in [nil, .live, .unavailable, .spoof(reason: "fixture", score: 0.9)] {
					let fixture = UnlockFrameEvaluator.Result(matched: matched, score: 0.8,
						face: hasFace ? face : nil, spoofDecision: decision)
					for required in [false, true] {
						let expected = matched && hasFace && (decision == .live || (!required && decision == nil))
						precondition(fixture.permitsMatchHold(requiresAntiSpoof: required) == expected)
						checks += 1
					}
				}
			}
		}
		for value: Float in [.nan, .infinity, -.infinity, 1.1, -1.1, 0.2] {
			let result = await UnlockFrameEvaluator(embedder: TestEmbedder(value: value), faces: [face], antiSpoof: nil).evaluate(FaceSample())
			precondition(!result.matched && result.face == nil)
			checks += 1
		}
		for threshold: Float in [.nan, .infinity, -1, 0, 1.01] {
			let result = await UnlockFrameEvaluator(embedder: TestEmbedder(matchThreshold: threshold), faces: [face], antiSpoof: nil).evaluate(FaceSample())
			precondition(!result.matched)
			checks += 1
		}
		for decision in [AntiSpoofGate.Decision.unavailable, .spoof(reason: "fixture", score: 0.9)] {
			let result = await UnlockFrameEvaluator(embedder: TestEmbedder(), faces: [face], antiSpoof: AntiSpoofGate(result: decision)).evaluate(FaceSample())
			precondition(result.spoofDecision == decision)
			checks += 1
		}
		let missing = await UnlockFrameEvaluator(embedder: TestEmbedder(value: nil), faces: [face], antiSpoof: nil).evaluate(FaceSample())
		precondition(!missing.matched && !missing.comparedIdentity)
		precondition(missing.failure == .embeddingUnavailable)
		let mismatch = await UnlockFrameEvaluator(embedder: TestEmbedder(value: 0.2), faces: [face], antiSpoof: nil).evaluate(FaceSample())
		precondition(mismatch.comparedIdentity && !mismatch.matched && !mismatch.permitsMatchHold(requiresAntiSpoof: false))
		precondition(mismatch.failure == nil)
		// Scores recorded during the owner's left-turn resets on 2026-09-14.
		// These are successful comparisons, not missing embeddings. Replaying the
		// scalar results protects the distinction; it does not reproduce camera/model accuracy.
		for score: Float in [0.405143, 0.357456, 0.274778, 0.149604] {
			for requiresAntiSpoof in [false, true] {
				let worker = UnlockFrameEvaluator(embedder: TestEmbedder(value: score),
					faces: [face], antiSpoof: requiresAntiSpoof ? AntiSpoofGate(result: .live) : nil)
				let result = await worker.evaluate(FaceSample())
				precondition(result.comparedIdentity && result.failure == nil && result.score == score)
				precondition(!result.matched && result.face == nil && result.spoofDecision == nil)
				precondition(!result.permitsMatchHold(requiresAntiSpoof: requiresAntiSpoof))
				checks += 1
			}
		}
		let unverified = UnlockFrameEvaluator.Result(matched: true, score: 0.8, face: face,
			spoofDecision: .live, comparedIdentity: false)
		precondition(!unverified.permitsMatchHold(requiresAntiSpoof: true))
		checks += 2
		for failure in [UnlockFrameEvaluator.Failure.cancelled, .invalidConfiguration,
			.embeddingUnavailable, .invalidSimilarity, .noEnrollment] {
			let rejected = UnlockFrameEvaluator.Result.rejected(failure)
			precondition(!rejected.comparedIdentity && !rejected.matched && rejected.face == nil
				&& rejected.failure == failure && !rejected.permitsMatchHold(requiresAntiSpoof: false))
			checks += 1
		}
		let invalidScore = await UnlockFrameEvaluator(embedder: TestEmbedder(value: .nan), faces: [face], antiSpoof: nil).evaluate(FaceSample())
		precondition(invalidScore.failure == .invalidSimilarity)
		let invalidThreshold = await UnlockFrameEvaluator(embedder: TestEmbedder(matchThreshold: 0), faces: [face], antiSpoof: nil).evaluate(FaceSample())
		precondition(invalidThreshold.failure == .invalidConfiguration)
		checks += 4
		let empty = await UnlockFrameEvaluator(embedder: TestEmbedder(), faces: [], antiSpoof: nil).evaluate(FaceSample())
		precondition(!empty.matched)
		let cancelled = Task { await evaluator.evaluate(FaceSample()) }
		cancelled.cancel()
		let result = await cancelled.value
		precondition(!result.matched)
		checks += 3
		for interruption in ["none", "lostFace", "recoveredFace", "restart", "cancelled"] {
			let controlled = ControlledEmbedder()
			let worker = UnlockFrameEvaluator(embedder: controlled, faces: [face], antiSpoof: AntiSpoofGate(result: .live))
			var stream = CameraEvidenceContinuity()
			let capturedAt = ContinuousClock.now
			stream.record(usable: true, capturedAt: capturedAt)
			let revision = stream.revision
			let evaluation = Task.detached { await worker.evaluate(FaceSample()) }
			precondition(controlled.began.wait(timeout: .now() + 2) == .success)
			switch interruption {
			case "lostFace", "recoveredFace":
				stream.record(usable: false, capturedAt: capturedAt.advanced(by: .milliseconds(1)))
				if interruption == "recoveredFace" {
					stream.record(usable: true, capturedAt: capturedAt.advanced(by: .milliseconds(2)))
				}
			case "restart": stream.invalidate()
			case "cancelled": evaluation.cancel()
			default: break
			}
			controlled.resume.signal()
			let decision = await evaluation.value
			let admitted = decision.permitsMatchHold(requiresAntiSpoof: true)
				&& stream.permits(revision, at: capturedAt.advanced(by: .milliseconds(10)))
			precondition(admitted == (interruption == "none"), "Intervening \(interruption) must invalidate completed work")
			checks += 1
		}
		print("PASS: \(checks) evaluator checks, including off-main inference, cancellation, invalid scores and PAD failure propagation; synthetic inputs only.")
	}
}
