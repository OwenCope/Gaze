import Accelerate
import Foundation

/// Immutable enrollment index, prepared once per scan. Learned vectors are normalized
/// once and compared with Accelerate; geometry keeps its own distance metric.
struct FaceTemplateMatcher: Sendable {
	enum Failure: Error { case invalidCandidate, invalidEnrollment, invalidSimilarity }
	struct Match: Sendable {
		let index: Int
		/// Second-best score within one face, or the only score for a legacy single print.
		let score: Float
	}

	private let embedder: any FaceEmbedder
	private let templates: [[Faceprint]]
	private let usesCosine: Bool
	private let isValid: Bool

	init(templates: [[Faceprint]], embedder: any FaceEmbedder) {
		self.embedder = embedder
		usesCosine = embedder.usesCosineSimilarity
		var valid = true
		self.templates = templates.map { prints in
			guard !prints.isEmpty, prints.count <= 128 else { valid = false; return [] }
			let dimension = prints[0].values.count
			return prints.compactMap { print in
				guard print.source == embedder.identifier,
					(1...4096).contains(dimension), print.values.count == dimension,
					let normalized = Faceprint.normalized(print.values, source: print.source)
				else { valid = false; return nil }
				return embedder.usesCosineSimilarity ? normalized : print
			}
		}
		isValid = valid
	}

	func bestMatch(to candidate: Faceprint) throws -> Match? {
		guard isValid else { throw Failure.invalidEnrollment }
		guard candidate.source == embedder.identifier,
			(1...4096).contains(candidate.values.count),
			let normalized = Faceprint.normalized(candidate.values, source: candidate.source)
		else { throw Failure.invalidCandidate }
		var best: Match?
		for (index, prints) in templates.enumerated() {
			guard prints.first?.values.count == candidate.values.count else {
				throw Failure.invalidEnrollment
			}
			var first: Float = -1
			var second: Float = -1
			for print in prints {
				let score: Float
				if usesCosine {
					var dot: Float = 0
					vDSP_dotpr(print.values, 1, normalized.values, 1, &dot,
						vDSP_Length(normalized.values.count))
					score = dot
				} else {
					score = embedder.similarity(print, candidate)
				}
				guard score.isFinite, (-1.000001...1.000001).contains(score) else {
					throw Failure.invalidSimilarity
				}
				let bounded = min(1, max(-1, score))
				if bounded > first { second = first; first = bounded }
				else if bounded > second { second = bounded }
			}
			// A single unusually high template cannot authorize a multi-print enrollment.
			// Never pool support across different enrolled identities.
			let supported = prints.count > 1 ? second : first
			if supported > (best?.score ?? -2) {
				best = Match(index: index, score: max(0, supported))
			}
		}
		return best
	}
}
