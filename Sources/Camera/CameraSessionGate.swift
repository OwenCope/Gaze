import Foundation

@MainActor
final class CameraSessionGate {
	enum Scope { case foreground, lockScreen }

	private let scope: Scope
	private let makeSession: @MainActor () -> AutofillSessionLease
	private var session: AutofillSessionLease?

	init(scope: Scope, makeSession: @escaping @MainActor () -> AutofillSessionLease = { AutofillSessionLease() }) {
		self.scope = scope
		self.makeSession = makeSession
	}

	func begin(onInvalidation: @escaping () -> Void) -> Bool {
		end()
		guard scope == .foreground else { return true }
		let session = makeSession()
		self.session = session
		session.onInvalidation = onInvalidation
		return session.isValid
	}

	var isValid: Bool { scope == .lockScreen || session?.isValid == true }

	func end() {
		let previous = session
		session = nil
		previous?.onInvalidation = nil
		previous?.invalidate()
	}
}
