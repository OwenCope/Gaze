import Foundation
import LocalAuthentication

/// Touch ID (or the account password) as authorisation for changes inside the app.
///
/// This is *in-app* biometrics and is unrelated to unlocking the Mac. It guards the
/// actions that would weaken the app — removing an enrolment, turning off tamper
/// protection, revealing settings — so someone at a borrowed, already-unlocked Mac
/// cannot quietly enrol their own face.
///
/// Note this still works when the authorization-plugin backend has disabled Touch ID on
/// the *lock screen*: that change only affects `system.login.screensaver`, not
/// `LAContext` inside a running app.
enum BiometricGate {

	enum Reason: String {
		case removeEnrollment = "remove your enrolled face"
		case changeSettings = "change Face ID settings"
		case disableTamperProtection = "turn off tamper protection"
		case storePassword = "store your account password"
	}

	static var isAvailable: Bool {
		var error: NSError?
		return LAContext().canEvaluatePolicy(
			.deviceOwnerAuthenticationWithBiometrics, error: &error)
	}

	/// Prompts for Touch ID, falling back to the account password automatically.
	///
	/// Returns false when the user cancels. Callers must treat false as "do not proceed"
	/// rather than retrying, so a cancelled prompt is never a way through.
	@discardableResult
	@MainActor
	static func authorize(_ reason: Reason) async -> Bool {
		guard Preferences.shared.touchIDFallback else { return true }

		// The prompt is a system panel attached to this app. From an accessory app that
		// never activates it can end up behind other windows, where it reads as the
		// action having silently failed — so come forward first.
		AppActivation.bringToFront()

		let context = LAContext()
		context.localizedFallbackTitle = "Use Password…"

		// `deviceOwnerAuthentication` — not `…WithBiometrics` — so a Mac without Touch ID,
		// or a finger that will not read, falls through to the password sheet.
		do {
			return try await context.evaluatePolicy(
				.deviceOwnerAuthentication,
				localizedReason: "Face ID needs to confirm it's you to \(reason.rawValue).")
		} catch {
			return false
		}
	}
}
