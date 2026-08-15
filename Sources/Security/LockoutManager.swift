import Foundation
import Observation
import os

/// Disables face unlock after too many consecutive failures.
///
/// Face matching is a similarity threshold, not a secret, so an attacker who can keep
/// presenting faces gets unlimited attempts at finding one that scores above the line.
/// Capping attempts is what turns "close enough eventually works" into "you get six
/// tries, then type your password" — the same reason iOS locks Gaze out.
///
/// State lives in the Secure Enclave-backed vault rather than a preference file, so it
/// cannot be reset by deleting a plist, and a tampered record fails closed.
@Observable
@MainActor
final class LockoutManager {

	/// Matches iOS: five retries after the first failure, then it stops asking.
	static let maxAttempts = 6

	private static let account = "lockout-state"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Lockout")

	private struct State: Codable {
		var consecutiveFailures: Int = 0
		/// Set when the vault record could not be read; only a password clears it.
		var forcedLockout: Bool = false
	}

	private var state = State()

	/// True when face unlock is refused until the user types their password.
	var isLockedOut: Bool {
		state.forcedLockout || state.consecutiveFailures >= Self.maxAttempts
	}

	var attemptsRemaining: Int {
		max(0, Self.maxAttempts - state.consecutiveFailures)
	}

	init() {
		load()
	}

	private func load() {
		do {
			state = try SecureVault.load(State.self, from: Self.account) ?? State()
		} catch {
			// A record exists but will not authenticate. Something edited it, so assume
			// the worst and require a password.
			Self.logger.error("Lockout record failed to open; failing closed. \(error)")
			state = State(consecutiveFailures: Self.maxAttempts, forcedLockout: true)
		}
	}

	private func persist() {
		do {
			try SecureVault.store(state, as: Self.account)
		} catch {
			// If we cannot record a failure we must not keep granting attempts.
			Self.logger.error("Could not persist lockout state; failing closed. \(error)")
			state.forcedLockout = true
		}
	}

	/// Call before every match attempt. Returns false when the attempt must not proceed.
	func mayAttempt() -> Bool { !isLockedOut }

	/// Records a rejected face. Persists before returning, so yanking power mid-attack
	/// does not roll the counter back.
	func recordFailure() {
		state.consecutiveFailures += 1
		persist()
		Self.logger.notice(
			"Face rejected. \(self.attemptsRemaining) attempt(s) before lockout.")
	}

	/// Records a match. Only ever called after a successful unlock.
	func recordSuccess() {
		guard state.consecutiveFailures > 0 || state.forcedLockout else { return }
		state = State()
		persist()
	}

	/// Clears the lockout. The caller must have verified the account password first —
	/// this is the only path out, and it is what makes the cap meaningful.
	func clearAfterPasswordAuth() {
		state = State()
		persist()
		Self.logger.notice("Lockout cleared after password authentication.")
	}
}
