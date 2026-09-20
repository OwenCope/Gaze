import Foundation
import Security

/// Minimal generic-password storage, scoped to this app.
///
/// Everything written here is already encrypted by `SecureVault`; the Keychain is used
/// for its access control and because it survives app reinstalls being deleted, not as
/// the confidentiality boundary.
enum Keychain {

	private static let service = "com.gazeunlock.Gaze"

	static func read(_ account: String) -> Data? {
		try? load(account)
	}

	enum ReadError: Error {
		case status(OSStatus)
		case unexpectedData
	}

	static func load(_ account: String) throws -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		if status == errSecItemNotFound { return nil }
		guard status == errSecSuccess else { throw ReadError.status(status) }
		guard let data = item as? Data else { throw ReadError.unexpectedData }
		return data
	}

	@discardableResult
	static func write(_ data: Data, to account: String) -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let attributes: [String: Any] = [
			kSecValueData as String: data,
			// The lock screen runs while the device is unlocked-since-boot at most, and
			// the helper needs to read this without a user present.
			//
			// `ThisDeviceOnly` rather than the plain variant: it also keeps the item out of
			// encrypted backups and off any restore to another Mac. The app tells people
			// their password is "never synced, never sent anywhere", and that sentence
			// should be enforced by the flag rather than by a promise.
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
			// Stated rather than assumed. An unset `kSecAttrSynchronizable` already defaults
			// to non-syncing, so this changes nothing today — but "we never sync your
			// password" resting on an unwritten default is a claim one careless edit away
			// from being false, and the edit would be silent.
			kSecAttrSynchronizable as String: false,
		]

		let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		if status == errSecSuccess { return true }

		guard status == errSecItemNotFound else { return false }
		return SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
	}

	@discardableResult
	static func delete(_ account: String) -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else { return false }
		var remaining: CFTypeRef?
		return SecItemCopyMatching(query as CFDictionary, &remaining) == errSecItemNotFound
	}
}
