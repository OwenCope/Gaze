import Foundation
import Security

/// Minimal generic-password storage, scoped to this app.
///
/// This is only the compatibility bridge for vaults written by versions before 0.4.
/// `SecureVault` moves those records into one authenticated Application Support file on
/// first launch, so normal launches do not touch the Keychain at all.
enum Keychain {

	private static let service = "com.gazeunlock.Gaze"

	enum KeychainError: LocalizedError {
		case status(OSStatus)
		case malformedItem

		var errorDescription: String? {
			switch self {
			case .status(let status):
				let message = SecCopyErrorMessageString(status, nil) as String?
				return message ?? "Keychain access failed (\(status))."
			case .malformedItem:
				return "A Gaze Keychain item had an unexpected format."
			}
		}
	}

	/// Reads one legacy record. New code should use `readLegacyItems()` so macOS only
	/// has one opportunity to show a Keychain authorization sheet during migration.
	static func read(_ account: String) -> Data? {
		try? readThrowing(account)
	}

	private static func readThrowing(_ account: String) throws -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		switch status {
		case errSecSuccess:
			guard let data = item as? Data else { throw KeychainError.malformedItem }
			return data
		case errSecItemNotFound:
			return nil
		default:
			throw KeychainError.status(status)
		}
	}

	/// Fetches every item owned by the old vault in one call. A separate `SecItemCopyMatching`
	/// for the key, faceprint, lockout state and password could produce four consecutive
	/// authorization sheets. One query gives macOS one decision to remember.
	static func readLegacyItems() throws -> [String: Data] {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecReturnAttributes as String: true,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitAll,
		]
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)

		guard status != errSecItemNotFound else { return [:] }
		guard status == errSecSuccess else { throw KeychainError.status(status) }
		guard let items = result as? [[String: Any]] else {
			throw KeychainError.malformedItem
		}

		var records: [String: Data] = [:]
		for item in items {
			guard
				let account = item[kSecAttrAccount as String] as? String,
				let data = item[kSecValueData as String] as? Data
			else {
				throw KeychainError.malformedItem
			}
			records[account] = data
		}
		return records
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
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
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
		return status == errSecSuccess || status == errSecItemNotFound
	}
}
