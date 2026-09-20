import CryptoKit
import Foundation
import os

/// Encrypts everything the app persists against a key held in the Secure Enclave.
///
/// The private key never leaves the Enclave, so the ciphertext is bound to this specific
/// Mac: copying the Keychain items to another machine yields nothing. That does not stop
/// a local attacker who is already running as this user — nothing at this layer can — but
/// it does mean face templates and the lockout counter cannot be lifted off the disk,
/// read on another machine, or edited in place without detection.
enum SecureVault {

	private static let keyAccount = "vault-key"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "SecureVault")

	enum VaultError: LocalizedError {
		case enclaveUnavailable
		case corrupted
		case missingKey
		case writeFailed
		case deleteFailed

		var errorDescription: String? {
			switch self {
			case .enclaveUnavailable: "The Secure Enclave is unavailable."
			case .corrupted: "The stored data could not be read."
			case .missingKey: "The vault key is missing."
			case .writeFailed: "The Keychain could not save the change."
			case .deleteFailed: "Deletion could not be confirmed. The stored data may still exist. Try again."
			}
		}
	}

	/// True on Apple Silicon and T2 Macs. Without it we refuse to store templates at all
	/// rather than quietly falling back to something weaker.
	static var isAvailable: Bool { SecureEnclave.isAvailable }

	// MARK: - Key material

	private static func enclaveKey(createIfMissing: Bool) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
		guard SecureEnclave.isAvailable else { throw VaultError.enclaveUnavailable }

		if let blob = try Keychain.load(keyAccount) {
			return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob)
		}
		guard createIfMissing else { throw VaultError.missingKey }

		let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()
		guard Keychain.write(key.dataRepresentation, to: keyAccount) else {
			throw VaultError.writeFailed
		}
		logger.info("Created a new Secure Enclave vault key.")
		return key
	}

	/// A symmetric key derived by having the Enclave key agree with its own public key.
	///
	/// Deterministic, so it reconstitutes across launches, but only ever computable
	/// inside the Enclave that holds the private half.
	private static func symmetricKey(createIfMissing: Bool) throws -> SymmetricKey {
		let key = try enclaveKey(createIfMissing: createIfMissing)
		let shared = try key.sharedSecretFromKeyAgreement(with: key.publicKey)
		// The salt keeps the old name deliberately. It is a cryptographic constant,
		// not a label: every key ever derived came from these exact bytes, and
		// renaming it to match the app would silently derive a different key and
		// make existing vaults undecryptable. It is versioned for when that is
		// actually wanted.
		return shared.hkdfDerivedSymmetricKey(
			using: SHA256.self,
			salt: Data("app.faceid.vault.v1".utf8),
			sharedInfo: Data(),
			outputByteCount: 32)
	}

	// MARK: - Storage

	/// Encrypts and stores a value. AES-GCM authenticates as well as encrypts, so a
	/// tampered blob fails to open rather than decoding to attacker-chosen data.
	static func store<T: Encodable>(_ value: T, as account: String) throws {
		let plaintext = try JSONEncoder().encode(value)
		let sealed = try AES.GCM.seal(plaintext, using: symmetricKey(createIfMissing: true))
		guard let combined = sealed.combined else { throw VaultError.corrupted }
		guard Keychain.write(combined, to: account) else { throw VaultError.writeFailed }
	}

	/// Loads and decrypts a value, or nil if absent.
	///
	/// Throws — rather than returning nil — when a blob exists but will not open, so
	/// callers can fail closed on tampering instead of treating it as "not enrolled".
	static func load<T: Decodable>(_ type: T.Type, from account: String) throws -> T? {
		guard let combined = try Keychain.load(account) else { return nil }
		let box = try AES.GCM.SealedBox(combined: combined)
		let plaintext = try AES.GCM.open(box, using: symmetricKey(createIfMissing: false))
		return try JSONDecoder().decode(type, from: plaintext)
	}

	static func remove(_ account: String) throws {
		guard Keychain.delete(account) else { throw VaultError.deleteFailed }
	}

	/// Destroys the vault key, which renders every stored blob permanently unreadable.
	static func destroy() throws {
		try remove(keyAccount)
		logger.notice("Vault key deletion confirmed.")
	}
}
