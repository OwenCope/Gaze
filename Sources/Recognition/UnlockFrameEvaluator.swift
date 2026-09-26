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
	/// Passive deny cues (device bezel, screen glare), adapted from Glance. Owned
	/// here — on this actor, off the main thread — rather than in `AntiSpoofGate` so
	/// the gate stays a stateless per-frame verdict and the hardening suite's stubs
	/// keep compiling against it untouched. Counts accumulate across the scan and
	/// reset per unlock attempt (fresh evaluator) or on an explicit `resetSpoofCues`.
	private var bezelCue = DeviceBezelGate()
	private var glareCue = GlareCue()

	init(embedder: any FaceEmbedder, faces: [FaceEnrollment], antiSpoof: AntiSpoofGate?) {
		self.embedder = embedder
		self.faces = faces
		self.antiSpoof = antiSpoof
	}

	/// Clears the deny cues' per-scan counts, so the next look after a spoof
	/// rejection starts from a clean slate like every other per-try state.
	func resetSpoofCues() {
		bezelCue.reset()
		glareCue.reset()
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
		let decision = matched ? denyChecked(sample) : nil
		guard !Task.isCancelled else { return .rejected(.cancelled) }
		return Result(matched: matched, score: best.0, face: matched ? best.1 : nil, spoofDecision: decision)
	}

	/// The classifier verdict plus the passive deny cues. The cues run only on frames
	/// the classifier already calls live, with anti-spoof always on, and can only turn
	/// a live frame into a spoof rejection — never the reverse.
	private func denyChecked(_ sample: FaceSample) -> AntiSpoofGate.Decision? {
		guard let decision = antiSpoof?.evaluate(sample) else { return nil }
		guard case .live = decision else { return decision }
		// Same 2.7x context crop the learned detector sees (224 px, the Spoof
		// model's input side); the face box is mapped from the same geometry.
		let side = 224
		guard let crop = FaceAligner.contextCrop(sample, side: side),
			let faceRect = FaceAligner.contextFaceRect(sample, side: side)
		else { return decision }
		if bezelCue.record(frame: crop, faceRect: faceRect) {
			return .spoof(
				reason: "device-bezel cue fired (face coverage \(bezelCue.level))",
				score: bezelCue.level)
		}
		if glareCue.record(frame: crop, faceRect: faceRect) {
			return .spoof(
				reason: "glare cue fired (level \(glareCue.level))",
				score: glareCue.level)
		}
		return decision
	}
}
