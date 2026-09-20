import AppKit
import CoreGraphics
import LocalAuthentication

struct AutofillConsoleSession: Equatable {
	let userID: UInt32
	let identifier: String

	static func current() -> Self? {
		validated(CGSessionCopyCurrentDictionary() as? [String: Any], owner: geteuid())
	}

	static func validated(_ values: [String: Any]?, owner: UInt32) -> Self? {
		guard let values,
			values[kCGSessionOnConsoleKey as String] as? Bool == true,
			values[kCGSessionLoginDoneKey as String] as? Bool == true,
			let userID = values[kCGSessionUserIDKey as String] as? UInt32, userID == owner,
			let identifier = values["CGSSessionUniqueSessionUUID"] as? String,
			UUID(uuidString: identifier) != nil
		else { return nil }
		if let locked = values["CGSSessionScreenIsLocked"] {
			guard let locked = locked as? Bool, !locked else { return nil }
		}
		return Self(userID: userID, identifier: identifier)
	}
}

@MainActor
final class AutofillSessionLease {
	private let original: AutofillConsoleSession?
	private let current: () -> AutofillConsoleSession?
	private let workspace: NotificationCenter
	private let distributed: NotificationCenter
	private var workspaceObservers: [NSObjectProtocol] = []
	private var distributedObservers: [NSObjectProtocol] = []
	private var invalidated = false
	var onInvalidation: (() -> Void)?

	init(current: @escaping () -> AutofillConsoleSession? = AutofillConsoleSession.current,
		workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
		distributed: NotificationCenter = DistributedNotificationCenter.default()) {
		self.current = current
		self.original = current()
		self.workspace = workspace
		self.distributed = distributed
		for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
			NSWorkspace.sessionDidResignActiveNotification] {
			workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.invalidate() }
			})
		}
		for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
			distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.invalidate() }
			})
		}
	}

	var isValid: Bool {
		guard !invalidated, original != nil, current() == original, !Task.isCancelled else {
			invalidate()
			return false
		}
		return true
	}

	func invalidate() {
		guard !invalidated else { return }
		invalidated = true
		onInvalidation?()
	}

	deinit {
		for observer in workspaceObservers { workspace.removeObserver(observer) }
		for observer in distributedObservers { distributed.removeObserver(observer) }
	}
}

@MainActor
final class AutofillAttemptBudget {
	struct State: Codable, Equatable {
		var attempts: Int
	}

	static let limit = 5
	private let load: () throws -> State?
	private let save: (State) throws -> Void
	private var storageFailed = false

	init(load: @escaping () throws -> State?, save: @escaping (State) throws -> Void) {
		self.load = load
		self.save = save
	}

	func reserve() -> Bool {
		guard !storageFailed else { return false }
		do {
			let state = try load() ?? State(attempts: 0)
			guard (0..<Self.limit).contains(state.attempts) else { return false }
			let next = State(attempts: state.attempts + 1)
			try save(next)
			guard try load() == next else { storageFailed = true; return false }
			return true
		} catch {
			storageFailed = true
			return false
		}
	}

	func resetAfterOwnerApproval() -> Bool {
		do {
			let next = State(attempts: 0)
			try save(next)
			guard try load() == next else { storageFailed = true; return false }
			storageFailed = false
			return true
		} catch {
			storageFailed = true
			return false
		}
	}
}

@MainActor
enum AutofillOwnerApproval {
	static func authorize(session: AutofillSessionLease, reason: String) async -> Bool {
		guard session.isValid else { return false }
		let context = LAContext()
		context.touchIDAuthenticationAllowableReuseDuration = 0
		context.localizedFallbackTitle = "Use Password…"
		session.onInvalidation = { context.invalidate() }
		defer {
			session.onInvalidation = nil
			context.invalidate()
		}
		return await withTaskCancellationHandler {
			do {
				let approved = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
				return approved && session.isValid && !Task.isCancelled
			} catch { return false }
		} onCancel: {
			context.invalidate()
		}
	}
}

@MainActor
enum AutofillReleaseGate {
	enum Result: Equatable {
		case filled, ownerRejected, stale, budgetUnavailable, noPassword, fieldNotWritable
	}

	static func release(isCurrent: () -> Bool, approve: () async -> Bool,
		resetBudget: () -> Bool, read: () throws -> String?, write: (String) -> Bool) async -> Result {
		guard !Task.isCancelled, isCurrent() else { return .stale }
		guard await approve() else { return .ownerRejected }
		guard !Task.isCancelled, isCurrent() else { return .stale }
		guard resetBudget() else { return .budgetUnavailable }
		guard !Task.isCancelled, isCurrent() else { return .stale }
		let password: String
		do {
			guard let stored = try read(), !stored.isEmpty else { return .noPassword }
			password = stored
		} catch { return .noPassword }
		guard !Task.isCancelled, isCurrent() else { return .stale }
		return write(password) ? .filled : .fieldNotWritable
	}
}
