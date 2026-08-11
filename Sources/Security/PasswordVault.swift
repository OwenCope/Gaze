import Foundation
import os

/// Stores the account password for the keystroke unlock backend.
///
/// Only used by that backend. The authorization-plugin path never needs this, which is
/// the main reason to prefer it: a password that is never stored cannot be stolen.
enum PasswordVault {

	private static let account = "account-password"
	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "PasswordVault")

	private struct Record: Codable {
		var password: String
	}

	static var hasPassword: Bool {
		Keychain.read(account) != nil
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

	static func remove() {
		SecureVault.remove(account)
	}

	/// `dscl . -authonly` returns non-zero for a wrong password without unlocking or
	/// consuming any system attempt counter.
	static func verify(_ password: String, user: String = NSUserName()) -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
		process.arguments = [".", "-authonly", user, password]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			logger.error("Could not run dscl: \(error)")
			return false
		}
	}
}
