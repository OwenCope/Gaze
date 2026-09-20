import Foundation
import OpenDirectory
import os

/// Stores the account password for the keystroke unlock backend.
///
enum PasswordVault {

	private static let account = "account-password"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "PasswordVault")

	private struct Record: Codable {
		var password: String
	}

	static var hasPassword: Bool {
		Keychain.read(account) != nil
	}

	static func containsPassword() throws -> Bool {
		try Keychain.load(account) != nil
	}

	/// Checks the password against the local directory before storing it, so a typo
	/// isn't discovered at the lock screen where it cannot be fixed.
	@discardableResult
	static func store(_ password: String, forUser user: String = NSUserName()) throws -> Bool {
		guard verify(password, user: user) else { return false }
		try SecureVault.store(Record(password: password), as: account)
		logger.notice("Stored account password for keystroke unlock.")
		return true
	}

	static func password() throws -> String? {
		try SecureVault.load(Record.self, from: account)?.password
	}

	static func remove() throws {
		try SecureVault.remove(account)
	}

	/// Checks a password against the local directory, without unlocking anything.
	///
	/// This used to shell out to `dscl . -authonly <user> <password>`, which put the
	/// password in the argument vector of a subprocess — and `argv` is readable from the
	/// process list by anything else running as this user for as long as the call takes.
	/// The window was short and the audience was limited to your own uid, but it meant the
	/// one moment the app handles a plaintext password was also the one moment it published
	/// it, which is not a trade worth making for a check the system exposes directly.
	///
	/// `ODRecord.verifyPassword` is the API `dscl` itself is a wrapper around. It stays
	/// in-process, avoiding a subprocess argument containing the password.
	static func verify(_ password: String, user: String = NSUserName()) -> Bool {
		do {
			let node = try ODNode(
				session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
			let record = try node.record(
				withRecordType: kODRecordTypeUsers, name: user, attributes: nil)
			try record.verifyPassword(password)
			return true
		} catch let error as NSError {
			// A wrong password and a broken lookup both land here, so tell them apart in the
			// log — "the password was wrong" and "we could not ask" need different fixes,
			// and conflating them is how a directory problem gets misread as a typo.
			if error.domain == "com.apple.OpenDirectory" && error.code == 5000 {
				logger.notice("Password did not verify against the local directory.")
			} else {
				logger.error("Could not verify password: \(error.localizedDescription)")
			}
			return false
		}
	}
}
