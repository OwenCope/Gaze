import Foundation

actor UnlockFrameEvaluator {
	enum Failure: String, Sendable {
		case cancelled, invalidConfiguration, embeddingUnavailable, invalidSimilarity, noEnrollment
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

	init(embedder: any FaceEmbedder, faces: [FaceEnrollment], antiSpoof: AntiSpoofGate?) {
		self.embedder = embedder
		self.faces = faces
		self.antiSpoof = antiSpoof
	}

	func evaluate(_ sample: FaceSample) -> Result {
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		guard embedder.matchThreshold.isFinite,
			(0...1).contains(embedder.matchThreshold), embedder.matchThreshold > 0 else {
			return .rejected(.invalidConfiguration)
		}
		guard let candidate = embedder.embed(sample) else { return .rejected(.embeddingUnavailable) }
		var best: (Float, FaceEnrollment)?
		for face in faces {
			let score = face.bestSimilarity(to: candidate, using: embedder)
			guard score.isFinite, (-1...1.000001).contains(score) else { return .rejected(.invalidSimilarity) }
			if score > (best?.0 ?? -1) { best = (score, face) }
		}
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		guard let best else { return .rejected(.noEnrollment) }
		let matched = best.0 >= embedder.matchThreshold
		let decision = matched ? antiSpoof?.evaluate(sample) : nil
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		return Result(matched: matched, score: best.0, face: matched ? best.1 : nil, spoofDecision: decision)
	}
}
