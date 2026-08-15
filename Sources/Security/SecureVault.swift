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

	enum VaultError: Error {
		case enclaveUnavailable
		case corrupted
	}

	/// True on Apple Silicon and T2 Macs. Without it we refuse to store templates at all
	/// rather than quietly falling back to something weaker.
	static var isAvailable: Bool { SecureEnclave.isAvailable }

	// MARK: - Key material

	private static func enclaveKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
		guard SecureEnclave.isAvailable else { throw VaultError.enclaveUnavailable }

		if let blob = Keychain.read(keyAccount),
			let key = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob)
		{
			return key
		}

		let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()
		Keychain.write(key.dataRepresentation, to: keyAccount)
		logger.info("Created a new Secure Enclave vault key.")
		return key
	}

	/// A symmetric key derived by having the Enclave key agree with its own public key.
	///
	/// Deterministic, so it reconstitutes across launches, but only ever computable
	/// inside the Enclave that holds the private half.
	private static func symmetricKey() throws -> SymmetricKey {
		let key = try enclaveKey()
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
		let sealed = try AES.GCM.seal(plaintext, using: symmetricKey())
		guard let combined = sealed.combined else { throw VaultError.corrupted }
		Keychain.write(combined, to: account)
	}

	/// Loads and decrypts a value, or nil if absent.
	///
	/// Throws — rather than returning nil — when a blob exists but will not open, so
	/// callers can fail closed on tampering instead of treating it as "not enrolled".
	static func load<T: Decodable>(_ type: T.Type, from account: String) throws -> T? {
		guard let combined = Keychain.read(account) else { return nil }
		let box = try AES.GCM.SealedBox(combined: combined)
		let plaintext = try AES.GCM.open(box, using: symmetricKey())
		return try JSONDecoder().decode(type, from: plaintext)
	}

	static func remove(_ account: String) {
		Keychain.delete(account)
	}

	/// Destroys the vault key, which renders every stored blob permanently unreadable.
	static func destroy() {
		Keychain.delete(keyAccount)
		logger.notice("Vault key destroyed; all stored data is now unrecoverable.")
	}
}
