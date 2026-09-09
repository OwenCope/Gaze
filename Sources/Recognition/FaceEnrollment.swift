import Foundation
import Observation
import os

/// One enrolled face: a set of faceprints captured across head angles, plus the
/// camera they were captured on.
struct FaceEnrollment: Codable, Sendable, Identifiable {
	var id: UUID
	/// What to call it in settings. Never shown on the lock screen.
	var name: String
	/// Several prints, not one. A single frontal print fails the moment the user tilts
	/// their head or the light changes; matching against the best of a spread is what
	/// makes recognition hold up in normal use.
	var prints: [Faceprint]
	/// Which embedder produced these. Changing models invalidates the enrolment.
	var embedder: String
	/// `uniqueID` of the camera used at enrolment, re-checked at every unlock.
	var cameraID: String
	var enrolledAt: Date

	init(
		id: UUID = UUID(),
		name: String,
		prints: [Faceprint],
		embedder: String,
		cameraID: String,
		enrolledAt: Date = Date()
	) {
		self.id = id
		self.name = name
		self.prints = prints
		self.embedder = embedder
		self.cameraID = cameraID
		self.enrolledAt = enrolledAt
	}

	/// Decoded with `id` and `name` optional.
	///
	/// Records written before this app held more than one face have neither. The
	/// synthesised decoder would throw on them, and a throw here reads as a corrupt
	/// vault — so an upgrade would tell the user their enrolment was damaged and
	/// offer to enrol again, having thrown away a perfectly good face.
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try container.decodeIfPresent(String.self, forKey: .name) ?? FaceEnrollment.defaultName(ordinal: 1)
		prints = try container.decode([Faceprint].self, forKey: .prints)
		embedder = try container.decode(String.self, forKey: .embedder)
		cameraID = try container.decode(String.self, forKey: .cameraID)
		enrolledAt = try container.decode(Date.self, forKey: .enrolledAt)
	}

	/// The name a newly enrolled face gets.
	///
	/// The first one takes the account's own name, because on most Macs the first
	/// face is the owner's and "Owen" beats "Face 1". Later ones are numbered,
	/// since the app has no way to know whose they are.
	static func defaultName(ordinal: Int) -> String {
		guard ordinal > 1 else {
			let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
			return full.isEmpty ? "Face 1" : full
		}
		return "Face \(ordinal)"
	}

	/// The best similarity between `candidate` and any print of this face.
	func bestSimilarity(to candidate: Faceprint, using embedder: FaceEmbedder) -> Float {
		prints.reduce(0) { max($0, embedder.similarity($1, candidate)) }
	}
}

/// Loads, saves and matches against the enrolled faces.
///
/// More than one face may be enrolled, and any of them opens the Mac. That is not
/// a multi-user feature and must not be presented as one: unlocking types *this
/// account's* password, so enrolling somebody else's face gives that person this
/// account, not one of their own.
@Observable
@MainActor
final class FaceEnrollmentStore {

	private static let account = "face-enrollment"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Enrollment")

	/// How many faces may be enrolled at once.
	///
	/// A limit rather than none. Every enrolled face is another way into the
	/// account and another set of prints to compare against on every frame, and a
	/// list that can grow without bound is a list nobody audits.
	static let maximumFaces = 5

	private(set) var faces: [FaceEnrollment] = []
	/// Set when a record exists but will not decrypt — enrolment is unusable and the UI
	/// should say so rather than silently offering to enrol again.
	private(set) var isCorrupted = false

	let embedder: FaceEmbedder = Embedders.best()

	var isEnrolled: Bool { !faces.isEmpty }
	var canAddFace: Bool { faces.count < Self.maximumFaces }

	/// The camera every enrolled face was taken on, when they agree.
	///
	/// Pinning the capture device is an anti-spoofing measure: a face enrolled on
	/// the built-in camera should not be matched against a stream from something
	/// plugged in afterwards. With several faces it only holds if they were all
	/// enrolled on the same camera — pinning to one of two would leave the other
	/// unable to unlock at all, which is a worse failure than not pinning.
	var pinnedCameraID: String? {
		guard let first = faces.first else { return nil }
		return faces.allSatisfy { $0.cameraID == first.cameraID } ? first.cameraID : nil
	}

	init() {
		load()
	}

	private func load() {
		do {
			if let stored = try SecureVault.load([FaceEnrollment].self, from: Self.account) {
				faces = usable(stored)
				return
			}
			// Nothing stored under the list format. Before falling back, check for a
			// single record from an older version and adopt it.
			if let single = try? SecureVault.load(FaceEnrollment.self, from: Self.account) {
				faces = usable([single])
				if !faces.isEmpty {
					Self.logger.notice("Migrated a single enrolment into the face list.")
					try? persist()
				}
				return
			}
			faces = []
		} catch {
			// A list decode fails on a record written as one face, which is an upgrade
			// rather than damage. Only report corruption when neither shape opens.
			if let single = try? SecureVault.load(FaceEnrollment.self, from: Self.account) {
				faces = usable([single])
				Self.logger.notice("Migrated a single enrolment into the face list.")
				try? persist()
				return
			}
			Self.logger.error("Enrolment failed to open: \(error)")
			isCorrupted = true
		}
	}

	/// Drops records this build cannot compare against.
	///
	/// Prints from another embedder live in a different feature space; matching
	/// across them produces a number that means nothing.
	private func usable(_ records: [FaceEnrollment]) -> [FaceEnrollment] {
		let keep = records.filter { $0.embedder == embedder.identifier }
		if keep.count != records.count {
			Self.logger.notice("Ignored \(records.count - keep.count) enrolment(s) from another embedder.")
		}
		return keep
	}

	private func persist() throws {
		try SecureVault.store(faces, as: Self.account)
		isCorrupted = false
	}

	/// Adds a newly captured face.
	@discardableResult
	func add(prints: [Faceprint], cameraID: String, name: String? = nil) throws -> FaceEnrollment {
		let record = FaceEnrollment(
			name: name ?? FaceEnrollment.defaultName(ordinal: faces.count + 1),
			prints: prints,
			embedder: embedder.identifier,
			cameraID: cameraID)
		faces.append(record)
		do {
			try persist()
		} catch {
			// Put the list back rather than leaving the app showing a face that is not
			// on disk and will vanish at the next launch.
			faces.removeLast()
			throw error
		}
		Self.logger.notice("Enrolled \(prints.count) faceprint(s) as a new face.")
		return record
	}

	func rename(_ id: UUID, to name: String) {
		guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		let previous = faces[index].name
		faces[index].name = trimmed
		do { try persist() } catch { faces[index].name = previous }
	}

	func remove(_ id: UUID) {
		let previous = faces
		faces.removeAll { $0.id == id }
		do { try persist() } catch { faces = previous }
	}

	func removeAll() {
		SecureVault.remove(Self.account)
		faces = []
		isCorrupted = false
	}

	/// Whether a live sample matches any enrolled face.
	///
	/// This is only half of an authentication decision — the caller must also clear
	/// liveness and the lockout counter before acting on it.
	func matches(_ sample: FaceSample) -> (matched: Bool, score: Float, face: FaceEnrollment?) {
		guard !faces.isEmpty, let candidate = embedder.embed(sample) else {
			return (false, 0, nil)
		}

		var best: (score: Float, face: FaceEnrollment)?
		for face in faces {
			let score = face.bestSimilarity(to: candidate, using: embedder)
			if score > (best?.score ?? -1) { best = (score, face) }
		}

		guard let best else { return (false, 0, nil) }
		let matched = best.score >= embedder.matchThreshold
		return (matched, best.score, matched ? best.face : nil)
	}
}
