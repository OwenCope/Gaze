import Foundation

// MARK: - In-memory stubs for FaceEnrollment.swift dependencies
//
// These stand in for the production vault, embedder selection and biometric gate
// so the test process never touches the real Keychain, Secure Enclave, biometric
// UI, camera or filesystem portraits. The production FaceEnrollment.swift is
// compiled unchanged alongside this file; everything defined here exists only
// because that file references it.

struct Faceprint: Codable, Sendable, Equatable {
	var values: [Float]
	var source: String
	static func normalized(_ values: [Float], source: String) -> Faceprint? {
		let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
		guard !source.isEmpty, norm.isFinite, norm > 0 else { return nil }
		return Faceprint(values: values.map { $0 / norm }, source: source)
	}
}

struct FaceSample: Sendable {}
enum FrameQuality { static func isUsable(_ sample: FaceSample) -> Bool { true } }

protocol FaceEmbedder: Sendable {
	var identifier: String { get }
	var usesCosineSimilarity: Bool { get }
	var matchThreshold: Float { get }
	func embed(_ sample: FaceSample) -> Faceprint?
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float
}

struct FixtureEmbedder: FaceEmbedder {
	let identifier = "fixture-embedder-v1"
	let usesCosineSimilarity = false
	let matchThreshold: Float = 0.5
	func embed(_ sample: FaceSample) -> Faceprint? {
		Faceprint(values: [1, 0], source: identifier)
	}
	/// Real cosine, not equality: `learn` needs graded similarity to tell a new
	/// angle of the same face from a near-duplicate.
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float {
		guard a.source == b.source, a.values.count == b.values.count, !a.values.isEmpty else { return 0 }
		var dot: Float = 0, aa: Float = 0, bb: Float = 0
		for i in a.values.indices {
			dot += a.values[i] * b.values[i]
			aa += a.values[i] * a.values[i]
			bb += b.values[i] * b.values[i]
		}
		guard aa > 0, bb > 0, dot.isFinite else { return 0 }
		return dot / (sqrt(aa) * sqrt(bb))
	}
}

enum Embedders {
	static func best() -> FaceEmbedder { FixtureEmbedder() }
}

struct AdjustedThresholdEmbedder: FaceEmbedder {
	let base: any FaceEmbedder
	let offset: Float
	var identifier: String { base.identifier }
	var usesCosineSimilarity: Bool { base.usesCosineSimilarity }
	var matchThreshold: Float { base.matchThreshold + offset }
	func embed(_ sample: FaceSample) -> Faceprint? { base.embed(sample) }
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float { base.similarity(a, b) }
}

/// Only the sensitivity FaceEnrollment reads; standard adds nothing to the threshold.
final class Preferences: @unchecked Sendable {
	struct Sensitivity { let thresholdOffset: Float = 0 }
	struct Distance { let thresholdOffset: Float = 0 }
	static let shared = Preferences()
	let recognitionSensitivity = Sensitivity()
	let detectionDistance = Distance()
}

/// Models SecureVault.load/store semantics — one JSON blob that is either absent
/// (nil) or present — while counting vault reads. The "decryption" step is a
/// plain JSON decode of the staged plaintext, which is exactly the surface the
/// migration logic depends on: absent vs present-but-undecodable.
enum SecureVault {
	struct SimulatedFailure: Error {}

	static var plaintext: Data?
	static var loadError: Error?
	static var storeError: Error?
	static var loadCount = 0
	static var storeCount = 0
	static var storedPlaintext: Data?

	static func reset(plaintext: Data? = nil) {
		self.plaintext = plaintext
		self.loadError = nil
		self.storeError = nil
		self.loadCount = 0
		self.storeCount = 0
		self.storedPlaintext = nil
	}

	static func load<T: Decodable>(_ type: T.Type, from account: String) throws -> T? {
		loadCount += 1
		if let loadError { throw loadError }
		guard let plaintext else { return nil }
		return try JSONDecoder().decode(type, from: plaintext)
	}

	static func store<T: Encodable>(_ value: T, as account: String) throws {
		storeCount += 1
		if let storeError { throw storeError }
		storedPlaintext = try JSONEncoder().encode(value)
	}

	static func remove(_ account: String) throws {
		plaintext = nil
		storedPlaintext = nil
	}
}

enum BiometricGate {
	enum Reason: String {
		case addEnrollment
	}

	static func require(_ reason: Reason) async -> Bool { true }
}

// MARK: - Tests

@main
@MainActor
enum EnrollmentStorageTests {
	static var checks = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		precondition(condition(), description)
		checks += 1
	}

	static func makeRecord(embedder: String = "fixture-embedder-v1", name: String = "Face") -> FaceEnrollment {
		FaceEnrollment(
			name: name,
			prints: [Faceprint(values: [1, 0], source: embedder)],
			embedder: embedder,
			cameraID: "camera-1")
	}

	static func fp(_ values: [Float]) -> Faceprint {
		Faceprint(values: values, source: "fixture-embedder-v1")
	}

	// A learned-print candidate: mostly the base axis with a unique side
	// channel, so every candidate scores 0.6 against the base print (above the
	// 0.55 drift floor) but only 0.36 against any other candidate (below the
	// 0.97 near-duplicate line). 2D rotations cannot hold 8 such prints, so
	// these live in 12 dimensions.
	static func learnedCandidate(_ index: Int, source: String = "fixture-embedder-v1") -> Faceprint {
		var values = [Float](repeating: 0, count: 12)
		values[0] = 0.6
		values[index % 11 + 1] = 0.8
		return Faceprint(values: values, source: source)
	}

	static func learnedBase(source: String = "fixture-embedder-v1") -> Faceprint {
		var values = [Float](repeating: 0, count: 12)
		values[0] = 1
		return Faceprint(values: values, source: source)
	}

	static func main() {
		// Absent enrollment: empty faces, no corruption, exactly one vault read.
		SecureVault.reset()
		var store = FaceEnrollmentStore()
		check(store.faces.isEmpty, "Absent enrollment yields no faces")
		check(!store.isCorrupted, "Absent enrollment is not corruption")
		check(SecureVault.loadCount == 1, "Absent enrollment costs exactly one vault load")
		check(SecureVault.storeCount == 0, "Absent enrollment never rewrites the vault")

		// Valid array: decoded as-is, no vault rewrite, exactly one vault read.
		let pair = [makeRecord(name: "A"), makeRecord(name: "B")]
		SecureVault.reset(plaintext: try! JSONEncoder().encode(pair))
		store = FaceEnrollmentStore()
		check(store.faces.count == 2, "Valid array decodes both faces")
		check(!store.isCorrupted, "Valid array is not corruption")
		check(SecureVault.loadCount == 1, "Valid array costs exactly one vault load")
		check(SecureVault.storeCount == 0, "Valid array never rewrites the vault")

		// Legacy single record: adopted, migrated to the list shape, one vault read.
		let legacy = makeRecord(name: "Legacy")
		SecureVault.reset(plaintext: try! JSONEncoder().encode(legacy))
		store = FaceEnrollmentStore()
		check(store.faces.count == 1 && store.faces[0].name == "Legacy", "Legacy single record is adopted")
		check(!store.isCorrupted, "Legacy single record is not corruption")
		check(SecureVault.loadCount == 1, "Legacy single record costs exactly one vault load")
		check(SecureVault.storeCount == 1, "Legacy single record triggers one migration write")
		let migrated = try! JSONDecoder().decode([FaceEnrollment].self, from: SecureVault.storedPlaintext!)
		check(migrated.count == 1 && migrated[0].name == "Legacy", "Migration persists the legacy face as a list")

		// Malformed JSON: corruption is marked, faces stay empty, one vault read.
		SecureVault.reset(plaintext: Data("not-json".utf8))
		store = FaceEnrollmentStore()
		check(store.faces.isEmpty, "Malformed JSON yields no faces")
		check(store.isCorrupted, "Malformed JSON marks corruption")
		check(SecureVault.loadCount == 1, "Malformed JSON costs exactly one vault load")

		// Simulated vault failure: corruption, never mistaken for absence, one read.
		SecureVault.reset()
		SecureVault.loadError = SecureVault.SimulatedFailure()
		store = FaceEnrollmentStore()
		check(store.faces.isEmpty, "Vault failure yields no faces")
		check(store.isCorrupted, "Vault failure marks corruption rather than absence")
		check(SecureVault.loadCount == 1, "Vault failure costs exactly one vault load")

		// Incompatible-embedder filtering on the array shape: no rewrite.
		let mixed = [makeRecord(name: "Mine"), makeRecord(embedder: "other-embedder-v9", name: "Theirs")]
		SecureVault.reset(plaintext: try! JSONEncoder().encode(mixed))
		store = FaceEnrollmentStore()
		check(store.faces.count == 1 && store.faces[0].name == "Mine", "Array records from another embedder are filtered")
		check(!store.isCorrupted, "Filtered array is not corruption")
		check(SecureVault.storeCount == 0, "Filtered array never rewrites the vault")

		// Legacy single record from another embedder: nothing usable, so no migration.
		SecureVault.reset(plaintext: try! JSONEncoder().encode(makeRecord(embedder: "other-embedder-v9")))
		store = FaceEnrollmentStore()
		check(store.faces.isEmpty, "Unusable legacy record yields no faces")
		check(!store.isCorrupted, "Unusable legacy record is not corruption")
		check(SecureVault.loadCount == 1, "Unusable legacy record costs exactly one vault load")
		check(SecureVault.storeCount == 0, "Unusable legacy record triggers no migration write")

		// Failed migration write: decoded legacy faces are retained in memory.
		SecureVault.reset(plaintext: try! JSONEncoder().encode(makeRecord(name: "Legacy")))
		SecureVault.storeError = SecureVault.SimulatedFailure()
		store = FaceEnrollmentStore()
		check(store.faces.count == 1 && store.faces[0].name == "Legacy", "Failed migration retains decoded legacy faces")
		check(!store.isCorrupted, "Failed migration write does not mark corruption")
		check(SecureVault.loadCount == 1, "Failed migration costs exactly one vault load")

		// Records written before the switch existed carry no isEnabled key.
		let oldRecord: [String: Any] = [
			"id": UUID().uuidString,
			"name": "Old",
			"prints": [["values": [1.0, 0.0], "source": "fixture-embedder-v1"]],
			"embedder": "fixture-embedder-v1",
			"cameraID": "camera-1",
			"enrolledAt": 0.0,
		]
		let decodedOld = try! JSONDecoder().decode(
			FaceEnrollment.self, from: JSONSerialization.data(withJSONObject: oldRecord))
		check(decodedOld.isEnabled, "A record without isEnabled decodes as enabled")
		check(decodedOld.learnedPrints.isEmpty && decodedOld.upperPrints.isEmpty,
			"A record without learnedPrints or upperPrints decodes both as empty")

		// New faces start switched on.
		check(makeRecord().isEnabled, "A newly created face is enabled by default")

		// A disabled face never matches, even with an identical print.
		SecureVault.reset(plaintext: try! JSONEncoder().encode([makeRecord(name: "Solo")]))
		store = FaceEnrollmentStore()
		check(store.matches(FaceSample()).matched, "An enabled face matches its own print")
		check(store.anyEnabled, "A fresh store has a face enabled")
		store.setEnabled(store.faces[0].id, false)
		check(!store.faces[0].isEnabled, "setEnabled switches the face off")
		check(!store.anyEnabled, "One switched-off face reads as none enabled")
		let persisted = try! JSONDecoder().decode([FaceEnrollment].self, from: SecureVault.storedPlaintext!)
		check(persisted.count == 1 && !persisted[0].isEnabled, "setEnabled persists the switch-off")
		let switchedOff = store.matches(FaceSample())
		check(!switchedOff.matched && switchedOff.face == nil, "A disabled face never matches, even with an identical print")
		check(switchedOff.reason == FaceEnrollmentStore.allFacesOffMessage, "A lone switched-off face carries the shared reason")

		// All faces off means no match; switching one back on restores it.
		SecureVault.reset(plaintext: try! JSONEncoder().encode([makeRecord(name: "A"), makeRecord(name: "B")]))
		store = FaceEnrollmentStore()
		store.setEnabled(store.faces[0].id, false)
		store.setEnabled(store.faces[1].id, false)
		let none = store.matches(FaceSample())
		check(!none.matched && none.face == nil, "All faces off means no match")
		check(none.reason == FaceEnrollmentStore.allFacesOffMessage, "All faces off carries the shared reason")
		store.setEnabled(store.faces[0].id, true)
		check(store.anyEnabled, "Switching one face back on reads as enabled")
		check(store.matches(FaceSample()).matched, "A re-enabled face matches again")

		// Learning: the drift guard, the near-duplicate skip, the cap of eight.
		let cappedRecord = FaceEnrollment(
			name: "Capped",
			prints: [fp([1, 0])],
			learnedPrints: (0..<8).map { _ in fp([1, 0]) },
			embedder: "fixture-embedder-v1",
			cameraID: "camera-1")
		SecureVault.reset(plaintext: try! JSONEncoder().encode([cappedRecord]))
		store = FaceEnrollmentStore()
		let cappedFaceID = store.faces[0].id
		let writesBeforeLearning = SecureVault.storeCount

		// A print unlike the originals is refused — the face cannot drift.
		store.learn(fp([0, 1]), for: cappedFaceID)
		check(store.faces[0].learnedPrints.count == 8, "A print unlike the originals is not learned")

		// A near-duplicate of a learned print is skipped.
		store.learn(fp([1, 0]), for: cappedFaceID)
		check(store.faces[0].learnedPrints.count == 8, "A near-duplicate of a learned print is skipped")

		// A new angle of the same face is learned, and the oldest is dropped.
		store.learn(fp([0.8, 0.6]), for: cappedFaceID)
		check(store.faces[0].learnedPrints.count == 8, "The learned set stays capped at eight")
		check(store.faces[0].learnedPrints.last == fp([0.8, 0.6]), "Learning at the cap drops the oldest")
		check(SecureVault.storeCount == writesBeforeLearning + 1, "Learning persists to the vault")

		// An unknown face is a no-op, not a crash and not a write.
		store.learn(fp([1, 0]), for: UUID())
		check(SecureVault.storeCount == writesBeforeLearning + 1, "Learning an unknown face writes nothing")

		// A failed write reverts the learned print.
		SecureVault.storeError = SecureVault.SimulatedFailure()
		store.learn(fp([0.95, 0.312]), for: cappedFaceID)
		check(store.faces[0].learnedPrints.last == fp([0.8, 0.6]) && store.faces[0].learnedPrints.count == 8,
			"A failed learn write reverts the print")
		SecureVault.storeError = nil

		// Learned prints participate in matching: originals that do not match the
		// live print alone, matched through what was learned. Both sets need two
		// supporting prints, per the matcher's multi-print rule.
		let originalsOnly = FaceEnrollment(
			name: "Originals", prints: [fp([0, 1]), fp([0, 1])],
			embedder: "fixture-embedder-v1", cameraID: "camera-1")
		SecureVault.reset(plaintext: try! JSONEncoder().encode([originalsOnly]))
		store = FaceEnrollmentStore()
		check(!store.matches(FaceSample()).matched, "A face whose originals do not match does not match")
		let withLearned = FaceEnrollment(
			name: "WithLearned",
			prints: [fp([0, 1]), fp([0, 1])],
			learnedPrints: [fp([1, 0]), fp([1, 0])],
			embedder: "fixture-embedder-v1",
			cameraID: "camera-1")
		SecureVault.reset(plaintext: try! JSONEncoder().encode([withLearned]))
		store = FaceEnrollmentStore()
		check(store.matches(FaceSample()).matched, "Learned prints participate in matching")

		// Records written before learned prints and mask matching existed carry
		// neither key; both must default to empty rather than failing the decode.
		let bareRecord: [String: Any] = [
			"id": UUID().uuidString,
			"name": "Bare",
			"prints": [["values": [1.0, 0.0], "source": "fixture-embedder-v1"]],
			"embedder": "fixture-embedder-v1",
			"cameraID": "camera-1",
			"enrolledAt": 0.0,
			"isEnabled": true,
		]
		let decodedBare = try! JSONDecoder().decode(
			FaceEnrollment.self, from: JSONSerialization.data(withJSONObject: bareRecord))
		check(decodedBare.learnedPrints.isEmpty, "A record without learnedPrints decodes as none learned")
		check(decodedBare.upperPrints.isEmpty, "A record without upperPrints decodes as none")

		// Learned prints and upper prints round-trip through the vault encoding.
		let seeded = FaceEnrollment(
			name: "Seeded",
			prints: [Faceprint(values: [1, 0], source: "fixture-embedder-v1")],
			learnedPrints: [learnedCandidate(0)],
			upperPrints: [Faceprint(values: [0, 1], source: "fixture-embedder-v1")],
			embedder: "fixture-embedder-v1",
			cameraID: "camera-1")
		let roundTripped = try! JSONDecoder().decode(
			FaceEnrollment.self, from: JSONEncoder().encode(seeded))
		check(roundTripped.learnedPrints == seeded.learnedPrints, "learnedPrints round-trip through the vault encoding")
		check(roundTripped.upperPrints == seeded.upperPrints, "upperPrints round-trip through the vault encoding")

		// Learning banks a qualifying print and persists it.
		let learnerBase = learnedBase()
		SecureVault.reset(plaintext: try! JSONEncoder().encode([FaceEnrollment(
			name: "Learner", prints: [learnerBase, learnerBase], embedder: "fixture-embedder-v1", cameraID: "camera-1")]))
		store = FaceEnrollmentStore()
		let learnerID = store.faces[0].id
		check(store.faces[0].learnedPrints.isEmpty, "A fresh face has no learned prints")
		store.learn(learnedCandidate(0), for: learnerID)
		check(store.faces[0].learnedPrints.count == 1, "A distinct qualifying print is learned")
		let learnedPersisted = try! JSONDecoder().decode([FaceEnrollment].self, from: SecureVault.storedPlaintext!)
		check(learnedPersisted[0].learnedPrints.count == 1, "learn persists the learned print")

		// Near-duplicates add nothing, so a print within 0.97 of a learned one is skipped.
		let writesAfterFirst = SecureVault.storeCount
		store.learn(store.faces[0].learnedPrints[0], for: learnerID)
		check(store.faces[0].learnedPrints.count == 1, "A near-duplicate of a learned print is skipped")
		check(SecureVault.storeCount == writesAfterFirst, "A skipped duplicate writes nothing")

		// Prints too far from the original enrolment are rejected, so learning
		// can never drift: a side-channel-free print scores below threshold + 0.05.
		var drifter = [Float](repeating: 0, count: 12)
		drifter[3] = 1
		store.learn(Faceprint(values: drifter, source: "fixture-embedder-v1"), for: learnerID)
		check(store.faces[0].learnedPrints.count == 1, "A print far from the original prints is rejected")

		// At most 8 learned prints are kept; the oldest drops when full.
		for index in 1...8 {
			store.learn(learnedCandidate(index), for: learnerID)
		}
		check(store.faces[0].learnedPrints.count == 8, "Learned prints are capped at 8")
		check(!store.faces[0].learnedPrints.contains(learnedCandidate(0)), "The oldest learned print drops when full")

		// Unknown faces and wrong-embedder prints are ignored.
		let beforeIgnored = store.faces[0].learnedPrints.count
		store.learn(learnedCandidate(9), for: UUID())
		store.learn(learnedCandidate(9, source: "other-embedder-v9"), for: learnerID)
		check(store.faces[0].learnedPrints.count == beforeIgnored, "Unknown faces and foreign prints are ignored")

		print("PASS: \(checks) enrollment-storage checks; one vault read per startup shape, no Keychain, Secure Enclave, biometric UI, camera or filesystem portrait use.")
	}
}
