import Foundation
import Observation
import os

/// The enrolled identity: a set of faceprints captured across head angles, plus the
/// camera they were captured on.
struct FaceEnrollment: Codable, Sendable {
	/// Several prints, not one. A single frontal print fails the moment the user tilts
	/// their head or the light changes; matching against the best of a spread is what
	/// makes recognition hold up in normal use.
	var prints: [Faceprint]
	/// Which embedder produced these. Changing models invalidates the enrolment.
	var embedder: String
	/// `uniqueID` of the camera used at enrolment, re-checked at every unlock.
	var cameraID: String
	var enrolledAt: Date

	/// The best similarity between `candidate` and any enrolled print, as judged by the
	/// embedder that produced them.
	func bestSimilarity(to candidate: Faceprint, using embedder: FaceEmbedder) -> Float {
		prints.reduce(0) { max($0, embedder.similarity($1, candidate)) }
	}
}

/// Loads, saves and matches against the enrolled face.
@Observable
@MainActor
final class FaceEnrollmentStore {

	private static let account = "face-enrollment"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Enrollment")

	private(set) var enrollment: FaceEnrollment?
	/// Set when a record exists but will not decrypt — enrolment is unusable and the UI
	/// should say so rather than silently offering to enrol again.
	private(set) var isCorrupted = false
	/// Set when a pre-0.4 install has protected records waiting for an explicit import.
	private(set) var legacyDataAvailable = false

	let embedder: FaceEmbedder = Embedders.best()

	var isEnrolled: Bool { enrollment != nil }

	init() {
		load()
		legacyDataAvailable = SecureVault.legacyDataAvailable
	}

	private func load() {
		isCorrupted = false
		do {
			let stored = try SecureVault.load(FaceEnrollment.self, from: Self.account)
			// A record made by a different embedder is not comparable, so treat it as
			// no enrolment rather than matching prints from another feature space.
			if let stored, stored.embedder != embedder.identifier {
				Self.logger.notice("Enrolment was made with \(stored.embedder); ignoring.")
				enrollment = nil
			} else {
				enrollment = stored
			}
		} catch {
			Self.logger.error("Enrolment failed to open: \(error)")
			isCorrupted = true
		}
	}

	/// Restores data written by a pre-0.4 build. The call is intentionally explicit because
	/// reading those old Keychain values can show Apple's login-keychain authorization sheet.
	@discardableResult
	func restoreLegacyData() throws -> Int {
		let count = try SecureVault.migrateLegacy() ?? 0
		load()
		legacyDataAvailable = SecureVault.legacyDataAvailable
		return count
	}

	func save(prints: [Faceprint], cameraID: String) throws {
		let record = FaceEnrollment(
			prints: prints,
			embedder: embedder.identifier,
			cameraID: cameraID,
			enrolledAt: Date())
		try SecureVault.store(record, as: Self.account)
		enrollment = record
		isCorrupted = false
		Self.logger.notice("Enrolled \(prints.count) faceprint(s).")
	}

	func removeEnrollment() {
		SecureVault.remove(Self.account)
		enrollment = nil
		isCorrupted = false
	}

	/// Whether a live sample matches the enrolled face.
	///
	/// This is only half of an authentication decision — the caller must also clear
	/// liveness and the lockout counter before acting on it.
	func matches(_ sample: FaceSample) -> (matched: Bool, score: Float) {
		guard let enrollment, let candidate = embedder.embed(sample) else {
			return (false, 0)
		}
		let score = enrollment.bestSimilarity(to: candidate, using: embedder)
		return (score >= embedder.matchThreshold, score)
	}
}
