import CryptoKit
import Foundation
import Security
import os

/// Encrypts everything Gaze persists with a key held by the Secure Enclave.
///
/// The vault is deliberately one file rather than one Keychain item per record. The old
/// design asked the Keychain for the same Enclave key every time it loaded a faceprint,
/// lockout state or password. macOS quite correctly treated each access as a fresh request
/// from a newly rebuilt binary, which could turn one authorization into a loop of sheets.
///
/// The Enclave key representation and one authenticated record archive now live in
/// `Application Support/Gaze/vault.bin`. The representation is only an opaque handle; the
/// private key never leaves the Enclave. The decoded vault is cached for the life of the
/// process, so startup performs one key load and normal reads never touch the Keychain.
enum SecureVault {

	private static let keyAccount = "vault-key"
	private static let legacyAccounts = [
		"vault-key",
		"face-enrollment",
		"lockout-state",
		"account-password",
	]
	private static let vaultVersion = 1
	private static let vaultFileName = "vault.bin"
	private static let associatedData = Data("com.gazeunlock.Gaze.secure-vault.v1".utf8)
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "SecureVault")
	private static let stateLock = NSLock()

	private static var cachedState: VaultState?
	/// A failed legacy query is remembered for the life of the process. Startup has several
	/// readers (enrolment, lockout, and the optional password row); re-running the query from
	/// each one turns one unanswered Keychain sheet into a loop of identical sheets.
	private static var cachedFailure: (any Error)?

	private struct VaultState {
		var key: SecureEnclave.P256.KeyAgreement.PrivateKey
		var symmetricKey: SymmetricKey
		var records: [String: Data]
	}

	private struct DiskEnvelope: Codable {
		var version: Int
		var keyRepresentation: Data
		var sealedRecords: Data
	}

	private struct DiskRecords: Codable {
		var records: [String: Data]
	}

	enum VaultError: LocalizedError {
		case enclaveUnavailable
		case corrupted
		case storageUnavailable

		var errorDescription: String? {
			switch self {
			case .enclaveUnavailable:
				return "Gaze needs a Mac with Secure Enclave support to store protected data."
			case .corrupted:
				return "Gaze's protected data could not be verified."
			case .storageUnavailable:
				return "Gaze could not access its protected data folder."
			}
		}
	}

	/// True on Apple Silicon and T2 Macs. Without it we refuse to store templates rather
	/// than quietly falling back to something weaker.
	static var isAvailable: Bool { SecureEnclave.isAvailable }

	// MARK: - Public storage

	/// Encrypts and stores a value. AES-GCM authenticates as well as encrypts, so a modified
	/// record fails to open rather than decoding to attacker-chosen data.
	static func store<T: Encodable>(_ value: T, as account: String) throws {
		let plaintext = try JSONEncoder().encode(value)

		stateLock.lock()
		defer { stateLock.unlock() }

		var state = try loadOrCreateStateLocked()
		let sealed = try AES.GCM.seal(plaintext, using: state.symmetricKey)
		guard let combined = sealed.combined else { throw VaultError.corrupted }
		state.records[account] = combined
		try persistLocked(state)
	}

	/// Loads and decrypts a value, or nil if that account has never been written.
	///
	/// Throws when the vault or a present record will not authenticate. Callers can then fail
	/// closed instead of treating damaged data as "not enrolled".
	static func load<T: Decodable>(_ type: T.Type, from account: String) throws -> T? {
		stateLock.lock()
		defer { stateLock.unlock() }

		guard let state = try loadExistingStateLocked() else { return nil }
		guard let combined = state.records[account] else { return nil }
		let box = try AES.GCM.SealedBox(combined: combined)
		let plaintext = try AES.GCM.open(box, using: state.symmetricKey)
		return try JSONDecoder().decode(type, from: plaintext)
	}

	/// Returns whether a record exists without causing another Keychain access. A damaged
	/// vault is not reported as absent; the next typed load still exposes the failure.
	static func contains(_ account: String) -> Bool {
		stateLock.lock()
		defer { stateLock.unlock() }

		do {
			return try loadExistingStateLocked()?.records[account] != nil
		} catch {
			logger.error("Could not inspect vault: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Removes one record while retaining the Enclave key for the remaining records.
	static func remove(_ account: String) {
		stateLock.lock()
		defer { stateLock.unlock() }

		do {
			guard var state = try loadExistingStateLocked() else { return }
			guard state.records.removeValue(forKey: account) != nil else { return }
			try persistLocked(state)
		} catch {
			logger.error("Could not remove vault record: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Whether an older install can be imported without showing a Keychain prompt.
	///
	/// This is deliberately only a metadata check. Import is a user action because macOS may
	/// ask for the login keychain password when the old encrypted values are read.
	static var legacyDataAvailable: Bool {
		stateLock.lock()
		defer { stateLock.unlock() }

		guard cachedState == nil, let url = try? vaultURL(),
			!FileManager.default.fileExists(atPath: url.path)
		else { return false }
		return Keychain.hasLegacyItems()
	}

	/// Imports pre-0.4 records after the user explicitly chooses to restore them.
	///
	/// A declined or failed Keychain authorization is thrown to the caller, but is not cached:
	/// reopening the import action is the user's choice and must not poison normal vault reads.
	@discardableResult
	static func migrateLegacy() throws -> Int? {
		stateLock.lock()
		defer { stateLock.unlock() }

		if cachedState != nil { return nil }
		let url = try vaultURL()
		if FileManager.default.fileExists(atPath: url.path) {
			_ = try loadExistingStateLocked()
			return nil
		}

		let legacy = try Keychain.readLegacyItems()
		guard !legacy.isEmpty else { return nil }
		guard let keyData = legacy[keyAccount], !keyData.isEmpty else {
			throw VaultError.corrupted
		}

		let key = try makeKey(from: keyData)
		let symmetricKey = try deriveSymmetricKey(from: key)
		var records = legacy
		records.removeValue(forKey: keyAccount)

		// Validate every old blob before deleting its source. A successful migration must
		// never turn a damaged record into a silently missing one.
		for combined in records.values {
			let box = try AES.GCM.SealedBox(combined: combined)
			_ = try AES.GCM.open(box, using: symmetricKey)
		}

		let state = VaultState(key: key, symmetricKey: symmetricKey, records: records)
		try persistLocked(state)

		for account in legacy.keys {
			guard Keychain.delete(account) else {
				logger.error("Could not remove legacy Keychain item \(account, privacy: .public).")
				continue
			}
		}
		logger.notice("Migrated \(records.count) protected record(s) out of the Keychain.")
		return records.count
	}

	/// Destroys the vault file and removes any records left by pre-0.4 builds. The Enclave
	/// object itself remains non-exportable and becomes unreachable without its representation.
	static func destroy() {
		stateLock.lock()
		defer { stateLock.unlock() }

		cachedState = nil
		cachedFailure = nil
		if let url = try? vaultURL() {
			try? FileManager.default.removeItem(at: url)
		}
		// Deleting the known compatibility records does not require reading their secret data,
		// so destroying the vault never opens another authorization sheet.
		for account in legacyAccounts {
			_ = Keychain.delete(account)
		}
		logger.notice("Vault destroyed; stored data is now unrecoverable.")
	}

	// MARK: - State

	private static func loadExistingStateLocked() throws -> VaultState? {
		if let cachedState { return cachedState }
		if let cachedFailure { throw cachedFailure }

		let url = try vaultURL()
		let fileManager = FileManager.default
		guard fileManager.fileExists(atPath: url.path) else { return nil }

		do {
			let data = try Data(contentsOf: url)
			let envelope = try PropertyListDecoder().decode(DiskEnvelope.self, from: data)
			guard envelope.version == vaultVersion, !envelope.keyRepresentation.isEmpty else {
				throw VaultError.corrupted
			}

			let key = try makeKey(from: envelope.keyRepresentation)
			let symmetricKey = try deriveSymmetricKey(from: key)
			let box = try AES.GCM.SealedBox(combined: envelope.sealedRecords)
			let recordData = try AES.GCM.open(
				box, using: symmetricKey, authenticating: associatedData)
			let diskRecords = try PropertyListDecoder().decode(DiskRecords.self, from: recordData)
			let state = VaultState(key: key, symmetricKey: symmetricKey, records: diskRecords.records)
			cachedState = state
			return state
		} catch let error as VaultError {
			cachedFailure = error
			throw error
		} catch {
			logger.error("Vault file failed authentication: \(error.localizedDescription, privacy: .public)")
			let failure = VaultError.corrupted
			cachedFailure = failure
			throw failure
		}
	}

	private static func loadOrCreateStateLocked() throws -> VaultState {
		if let state = try loadExistingStateLocked() { return state }

		let key = try makeNewKey()
		let state = VaultState(
			key: key,
			symmetricKey: try deriveSymmetricKey(from: key),
			records: [:])
		try persistLocked(state)
		return state
	}

	private static func makeNewKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
		guard SecureEnclave.isAvailable else { throw VaultError.enclaveUnavailable }
		guard
			let accessControl = SecAccessControlCreateWithFlags(
				nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [], nil)
		else {
			throw VaultError.enclaveUnavailable
		}

		return try SecureEnclave.P256.KeyAgreement.PrivateKey(
			compactRepresentable: true, accessControl: accessControl)
	}

	private static func makeKey(from data: Data) throws
		-> SecureEnclave.P256.KeyAgreement.PrivateKey
	{
		guard SecureEnclave.isAvailable else { throw VaultError.enclaveUnavailable }
		return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data)
	}

	/// A symmetric key derived by having the Enclave key agree with its own public key.
	///
	/// Deterministic, so it reconstitutes across launches, but the private half never leaves
	/// the Enclave. The salt is versioned and must not be renamed without a new migration.
	private static func deriveSymmetricKey(
		from key: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> SymmetricKey
	{
		let shared = try key.sharedSecretFromKeyAgreement(with: key.publicKey)
		return shared.hkdfDerivedSymmetricKey(
			using: SHA256.self,
			salt: Data("app.faceid.vault.v1".utf8),
			sharedInfo: Data(),
			outputByteCount: 32)
	}

	private static func persistLocked(_ state: VaultState) throws {
		let recordsEncoder = PropertyListEncoder()
		recordsEncoder.outputFormat = .binary
		let records = try recordsEncoder.encode(DiskRecords(records: state.records))
		let sealed = try AES.GCM.seal(records, using: state.symmetricKey, authenticating: associatedData)
		guard let combined = sealed.combined else { throw VaultError.corrupted }
		let envelope = DiskEnvelope(
			version: vaultVersion,
			keyRepresentation: state.key.dataRepresentation,
			sealedRecords: combined)
		let envelopeEncoder = PropertyListEncoder()
		envelopeEncoder.outputFormat = .binary
		let data = try envelopeEncoder.encode(envelope)

		let destination = try vaultURL()
		let temporary = destination
			.deletingLastPathComponent()
			.appendingPathComponent(".vault-\(UUID().uuidString).tmp")
		defer { try? FileManager.default.removeItem(at: temporary) }

		try data.write(to: temporary, options: .atomic)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o600], ofItemAtPath: temporary.path)

		if FileManager.default.fileExists(atPath: destination.path) {
			_ = try FileManager.default.replaceItemAt(
				destination, withItemAt: temporary, backupItemName: nil,
				options: .usingNewMetadataOnly)
		} else {
			try FileManager.default.moveItem(at: temporary, to: destination)
		}
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o600], ofItemAtPath: destination.path)
		cachedState = state
	}

	private static func vaultURL() throws -> URL {
		guard
			let applicationSupport = FileManager.default.urls(
				for: .applicationSupportDirectory, in: .userDomainMask).first
		else {
			throw VaultError.storageUnavailable
		}

		let directory = applicationSupport.appendingPathComponent("Gaze", isDirectory: true)
		try FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700], ofItemAtPath: directory.path)
		return directory.appendingPathComponent(vaultFileName, isDirectory: false)
	}
}
