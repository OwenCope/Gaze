import Foundation

/// Shifts the base embedder's match threshold by a sensitivity offset.
///
/// Prints stay in the base feature space: `identifier`, `usesCosineSimilarity`,
/// `embed` and `similarity` all forward untouched, so enrolments recorded under
/// the base identifier keep comparing. Only the acceptance line moves, clamped
/// to 0.3...0.7.
struct AdjustedThresholdEmbedder: FaceEmbedder, @unchecked Sendable {
	let base: any FaceEmbedder
	let offset: Float

	var identifier: String { base.identifier }
	var usesCosineSimilarity: Bool { base.usesCosineSimilarity }
	var matchThreshold: Float { min(0.7, max(0.3, base.matchThreshold + offset)) }

	func embed(_ sample: FaceSample) -> Faceprint? { base.embed(sample) }
	func embedUpperFace(_ sample: FaceSample) -> Faceprint? { base.embedUpperFace(sample) }
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float { base.similarity(a, b) }
	func warmUp() { base.warmUp() }
}
