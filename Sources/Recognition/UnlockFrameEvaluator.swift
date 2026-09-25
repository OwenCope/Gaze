import Foundation

actor UnlockFrameEvaluator {
	enum Failure: String, Sendable {
		case cancelled, invalidConfiguration, embeddingUnavailable, invalidSimilarity, noEnrollment, unusableFrame
	}

	struct Result: Sendable {
		let matched: Bool
		let score: Float
		let face: FaceEnrollment?
		let spoofDecision: AntiSpoofGate.Decision?
		var comparedIdentity = true
		var failure: Failure?

		func permitsMatchHold(requiresAntiSpoof: Bool) -> Bool {
			failure == nil && comparedIdentity && matched && face != nil && (requiresAntiSpoof ? spoofDecision == .live : spoofDecision == nil || spoofDecision == .live)
		}

		static func rejected(_ failure: Failure) -> Self {
			Self(matched: false, score: 0, face: nil, spoofDecision: nil,
				comparedIdentity: false, failure: failure)
		}
	}

	private let embedder: any FaceEmbedder
	private let faces: [FaceEnrollment]
	private let antiSpoof: AntiSpoofGate?
	private let matcher: FaceTemplateMatcher

	init(embedder: any FaceEmbedder, faces: [FaceEnrollment], antiSpoof: AntiSpoofGate?) {
		self.embedder = embedder
		self.faces = faces
		self.antiSpoof = antiSpoof
		self.matcher = FaceTemplateMatcher(templates: faces.map(\.prints), embedder: embedder)
	}

	func evaluate(_ sample: FaceSample) -> Result {
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		guard !faces.isEmpty else { return .rejected(.noEnrollment) }
		guard FrameQuality.isUsable(sample) else { return .rejected(.unusableFrame) }
		guard embedder.matchThreshold.isFinite,
			(0...1).contains(embedder.matchThreshold), embedder.matchThreshold > 0 else {
			return .rejected(.invalidConfiguration)
		}
		guard let candidate = embedder.embed(sample) else { return .rejected(.embeddingUnavailable) }
		let best: FaceTemplateMatcher.Match?
		do { best = try matcher.bestMatch(to: candidate) }
		catch { return .rejected(.invalidSimilarity) }
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		guard let best else { return .rejected(.noEnrollment) }
		let matched = best.score >= embedder.matchThreshold
		let decision = matched ? antiSpoof?.evaluate(sample) : nil
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		return Result(matched: matched, score: best.score, face: matched ? faces[best.index] : nil, spoofDecision: decision)
	}
}
