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
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
			return nil
		}
		return item as? Data
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
