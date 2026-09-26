import AppKit
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
	/// Switched off in Settings. Kept on disk, never matched against.
	var isEnabled: Bool

	init(
		id: UUID = UUID(),
		name: String,
		prints: [Faceprint],
		embedder: String,
		cameraID: String,
		enrolledAt: Date = Date(),
		isEnabled: Bool = true
	) {
		self.id = id
		self.name = name
		self.prints = prints
		self.embedder = embedder
		self.cameraID = cameraID
		self.enrolledAt = enrolledAt
		self.isEnabled = isEnabled
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
		// Absent on records written before the switch existed. Defaulting to
		// true keeps those faces working with no migration, the same way a
		// missing `id` or `name` above falls back instead of throwing.
		isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
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

/// The vault payload in either of its historical shapes.
///
/// Current writes are `[FaceEnrollment]`. Records written before the app held more
/// than one face are a single `FaceEnrollment`. Decoding both shapes from one
/// decrypted blob keeps startup to a single Keychain read and a single Secure
/// Enclave decryption, instead of retrying the vault once per shape.
struct StoredFaceEnrollments: Decodable, Sendable {
	var records: [FaceEnrollment]
	var wasSingleRecord: Bool

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let list = try? container.decode([FaceEnrollment].self) {
			records = list
			wasSingleRecord = false
			return
		}
		records = [try container.decode(FaceEnrollment.self)]
		wasSingleRecord = true
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

	#if PRODUCT_CAPTURE
	/// Capture tool only: shows one enrolled face without touching the vault or the
	/// Secure Enclave. Never compiled into the shipping app.
	func loadProductCaptureDemoFace() {
		faces = [FaceEnrollment(name: "You", prints: [], embedder: embedder.identifier, cameraID: "demo")]
	}
	#endif

	/// Bumped whenever a portrait is written or cleared.
	///
	/// Portraits live on disk rather than in `faces`, so changing one does not touch any
	/// observed property and the settings pane would keep drawing the old picture. This is
	/// the observable that says "look again".
	private(set) var portraitRevision: UInt64 = 0

	/// Decoded portraits, kept in memory.
	///
	/// This used to read straight from disk on every call, on the reasoning that holding
	/// images in memory was not worth it for a list at most five long. That was the wrong
	/// comparison. `portrait(for:)` is called from inside the settings pane's `ForEach`
	/// body, and SwiftUI re-evaluates a body on every hover, every animation frame and
	/// every state change — so the real trade was not "a little memory versus none", it was
	/// "a little memory versus a `stat` and a full PNG decode per face, per frame, on the
	/// main thread". That is what made choosing a picture judder.
	///
	/// The value is `NSImage?` rather than `NSImage` so a face with no portrait is cached
	/// as a known absence instead of retrying the filesystem forever.
	///
	/// `@ObservationIgnored` matters: this is filled during body evaluation, and mutating
	/// an observed property there is what turns a redraw into a redraw loop.
	@ObservationIgnored private var portraitCache: [UUID: NSImage?] = [:]
	/// Set when a record exists but will not decrypt — enrolment is unusable and the UI
	/// should say so rather than silently offering to enrol again.
	private(set) var isCorrupted = false
	private var isAddingFace = false

	let embedder: FaceEmbedder = Embedders.best()

	var isEnrolled: Bool { !faces.isEmpty }
	var canAddFace: Bool { faces.count < Self.maximumFaces }

	/// Whether any face is currently allowed to unlock.
	///
	/// The five-face limit counts disabled faces (`canAddFace` reads the whole
	/// list), so this is the check Settings uses to decide between "nothing
	/// enrolled" and "everything switched off".
	var anyEnabled: Bool { faces.contains(where: \.isEnabled) }

	/// The sentence shown wherever a miss needs explaining because every face
	/// is switched off. One string shared by `matches(_:)` and Settings, so
	/// the two cannot drift apart.
	static let allFacesOffMessage = "All faces are off, so Gaze won't unlock your Mac."

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
			// One vault read. `StoredFaceEnrollments` accepts both the list shape
			// and the legacy single record, so a second read is never needed to
			// tell an upgrade apart from damage.
			guard let stored = try SecureVault.load(StoredFaceEnrollments.self, from: Self.account) else {
				faces = []
				return
			}
			faces = usable(stored.records)
			if stored.wasSingleRecord, !faces.isEmpty {
				Self.logger.notice("Migrated a single enrolment into the face list.")
				try? persist()
			}
		} catch {
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
	func add(prints: [Faceprint], cameraID: String, name: String? = nil) async throws -> FaceEnrollment {
		try Task.checkCancellation()
		guard !isAddingFace else { throw EnrollmentError.busy }
		guard canAddFace else { throw EnrollmentError.full }
		isAddingFace = true
		defer { isAddingFace = false }
		guard await BiometricGate.require(.addEnrollment) else {
			throw EnrollmentError.notAuthorized
		}
		try Task.checkCancellation()
		guard canAddFace else { throw EnrollmentError.full }
		guard !prints.isEmpty, !cameraID.isEmpty else { throw EnrollmentError.invalidCapture }
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

	private enum EnrollmentError: LocalizedError {
		case notAuthorized
		case full
		case invalidCapture
		case busy

		var errorDescription: String? {
			switch self {
			case .notAuthorized: "Owner authentication is required to enroll a face."
			case .full: "Remove an enrolled face before adding another."
			case .invalidCapture: "The face capture is incomplete. Try again."
			case .busy: "An enrollment is already waiting for approval."
			}
		}
	}

	func rename(_ id: UUID, to name: String) {
		guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		let previous = faces[index].name
		faces[index].name = trimmed
		do { try persist() } catch { faces[index].name = previous }
	}

	/// Switches one face on or off, keeping the record on disk either way.
	///
	/// Authorisation, if any, happens at the call site: switching off only
	/// reduces who can unlock so it needs none, while switching on goes through
	/// the same `BiometricGate.authorize` check Settings uses for removing a face.
	func setEnabled(_ id: UUID, _ enabled: Bool) {
		guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
		guard faces[index].isEnabled != enabled else { return }
		let previous = faces[index].isEnabled
		faces[index].isEnabled = enabled
		do { try persist() } catch { faces[index].isEnabled = previous }
	}

	func remove(_ id: UUID) {
		let previous = faces
		faces.removeAll { $0.id == id }
		do {
			try persist()
			// The picture goes with the face. Leaving it behind orphaned a PNG in
			// Application Support for every face ever deleted, and it is someone's
			// photograph — deleting the enrolment should not quietly keep it.
			if let url = Self.portraitURL(for: id) {
				try? FileManager.default.removeItem(at: url)
			}
			portraitCache[id] = nil
		} catch {
			faces = previous
		}
	}

	func removeAll() throws {
		try SecureVault.remove(Self.account)
		for face in faces {
			if let url = Self.portraitURL(for: face.id) {
				try? FileManager.default.removeItem(at: url)
			}
		}
		portraitCache.removeAll()
		faces = []
		isCorrupted = false
	}

	/// Whether a live sample matches any enrolled face.
	///
	/// This is only half of an authentication decision — the caller must also clear
	/// liveness and the lockout counter before acting on it.
	///
	/// Only faces switched on are scored. When every face is off the result is a
	/// miss carrying `allFacesOffMessage`, so a caller with somewhere to show it
	/// (Settings, the recognition test) can say why instead of just failing.
	func matches(_ sample: FaceSample) -> (matched: Bool, score: Float, face: FaceEnrollment?, reason: String?) {
		let enabled = faces.filter(\.isEnabled)
		guard !enabled.isEmpty else {
			return (false, 0, nil, faces.isEmpty ? nil : Self.allFacesOffMessage)
		}
		guard let candidate = embedder.embed(sample) else {
			return (false, 0, nil, nil)
		}

		var best: (score: Float, face: FaceEnrollment)?
		for face in enabled {
			let score = face.bestSimilarity(to: candidate, using: embedder)
			if score > (best?.score ?? -1) { best = (score, face) }
		}

		guard let best else { return (false, 0, nil, nil) }
		let matched = best.score >= embedder.matchThreshold
		return (matched, best.score, matched ? best.face : nil, nil)
	}
}

// MARK: - Portraits

extension FaceEnrollmentStore {

	/// Where a face's portrait lives.
	///
	/// A file beside the vault rather than a field on `FaceEnrollment`, for two reasons.
	/// The enrolment record is encrypted and rewritten whenever anything about a face
	/// changes, and a picture is the one part of it that is neither secret nor small —
	/// base64ing a portrait into that blob would triple the size of the thing the Secure
	/// Enclave has to unwrap on every launch, to protect a photograph the user chose.
	///
	/// And the file is disposable. A missing portrait is a face with no portrait, which is
	/// the normal state, so nothing here throws and nothing needs migrating.
	static func portraitsDirectory() -> URL? {
		guard
			let support = FileManager.default.urls(
				for: .applicationSupportDirectory, in: .userDomainMask
			).first
		else { return nil }
		let dir = support.appendingPathComponent("Gaze/Portraits", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	static func portraitURL(for id: UUID) -> URL? {
		portraitsDirectory()?.appendingPathComponent("\(id.uuidString).png")
	}

	/// The portrait somebody chose for this face, if they chose one.
	///
	/// Safe to call from a view body: after the first call per face it is a dictionary
	/// lookup. The `fileExists` check that used to guard this is gone — `NSImage` already
	/// returns nil for a file that is not there, so the extra `stat` bought nothing.
	func portrait(for id: UUID) -> NSImage? {
		if let cached = portraitCache[id] { return cached }
		let loaded = Self.portraitURL(for: id).flatMap { NSImage(contentsOf: $0) }
		portraitCache[id] = loaded
		return loaded
	}

	/// Stores a portrait, or clears it when handed nil.
	///
	/// Downsampled to 256pt square before writing. The picker hands back whatever the user
	/// picked — frequently a 4000px photograph — and this is drawn at 68pt. Keeping the
	/// original would put megabytes on disk and decode them on every settings redraw for a
	/// picture that can never show the detail.
	func setPortrait(_ image: NSImage?, for id: UUID) {
		guard let url = Self.portraitURL(for: id) else { return }
		guard let image else {
			try? FileManager.default.removeItem(at: url)
			// Cached as a known absence, not simply dropped — dropping it would send the
			// next read back to the filesystem for a file we just deleted.
			portraitCache[id] = .some(nil)
			portraitRevision &+= 1
			return
		}

		let side = 256.0
		let target = NSImage(size: NSSize(width: side, height: side))
		target.lockFocus()
		// Aspect-fill into a square: portraits are people, and letterboxing a face inside a
		// tile looks like a mistake rather than a choice.
		let source = image.size
		let scale = max(side / source.width, side / source.height)
		let drawn = NSSize(width: source.width * scale, height: source.height * scale)
		image.draw(
			in: NSRect(
				x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
				width: drawn.width, height: drawn.height),
			from: .zero, operation: .copy, fraction: 1)
		target.unlockFocus()

		guard let tiff = target.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:])
		else { return }
		try? png.write(to: url)
		// The downsampled copy is exactly what the tile draws, so cache it here rather than
		// letting the next body evaluation read and decode the file we just wrote.
		portraitCache[id] = target
		portraitRevision &+= 1
	}
}
