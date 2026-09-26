import AppKit
import Foundation

struct FaceSample {}
struct SpoofDetector {
	let score: Float?
	func spoofConfidence(_ sample: FaceSample) -> Float? { score }
}

private enum TestError: Error { case injected, failed(String) }

enum SecureVault {
	static func load<Value: Decodable>(_ type: Value.Type, from account: String) throws -> Value? {
		throw TestError.injected
	}
	static func store<Value: Encodable>(_ value: Value, as account: String) throws {
		throw TestError.injected
	}
}

@main
@MainActor
enum HardeningTests {
	static var checks = 0
	static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
		guard condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	static func main() async throws {
		try sessionTests()
		try cameraSessionTests()
		try budgetTests()
		try lockoutTests()
		try frameTests()
		try matchHoldTests()
		try urlTests()
		try spoofTests()
		try await releaseTests()
		print("\(checks) hardening checks passed; synthetic inputs only, no camera, credentials, Keychain, UI authentication, or network requests")
	}

	static func sessionTests() throws {
		let identifier = UUID().uuidString
		var values: [String: Any] = [kCGSessionOnConsoleKey as String: true,
			kCGSessionLoginDoneKey as String: true, kCGSessionUserIDKey as String: UInt32(501),
			"CGSSessionUniqueSessionUUID": identifier]
		let original = AutofillConsoleSession.validated(values, owner: 501)
		try expect(original != nil, "unlocked session without the optional lock flag is valid")
		try expect(AutofillConsoleSession.validated(values, owner: 502) == nil, "other console owner rejected")
		try expect(AutofillConsoleSession.validated(nil, owner: 501) == nil, "missing session fails closed")
		values["CGSSessionScreenIsLocked"] = true
		try expect(AutofillConsoleSession.validated(values, owner: 501) == nil, "locked session rejected")
		values["CGSSessionScreenIsLocked"] = "false"
		try expect(AutofillConsoleSession.validated(values, owner: 501) == nil, "malformed lock flag rejected")
		values["CGSSessionScreenIsLocked"] = false
		values[kCGSessionOnConsoleKey as String] = false
		try expect(AutofillConsoleSession.validated(values, owner: 501) == nil, "background session rejected")
		values[kCGSessionOnConsoleKey as String] = true
		values["CGSSessionUniqueSessionUUID"] = "invalid"
		try expect(AutofillConsoleSession.validated(values, owner: 501) == nil, "malformed session identifier rejected")
		let workspace = NotificationCenter()
		let distributed = NotificationCenter()
		for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
			NSWorkspace.sessionDidResignActiveNotification] {
			let lease = AutofillSessionLease(current: { original }, workspace: workspace, distributed: distributed)
			var invalidations = 0
			lease.onInvalidation = { invalidations += 1 }
			try expect(lease.isValid, "new session lease valid")
			workspace.post(name: name, object: nil)
			workspace.post(name: name, object: nil)
			try expect(!lease.isValid && invalidations == 1, "workspace invalidation is irreversible and fires once")
		}
		for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
			let lease = AutofillSessionLease(current: { original }, workspace: workspace, distributed: distributed)
			distributed.post(name: Notification.Name(name), object: nil)
			try expect(!lease.isValid, "lock/unlock invalidates existing requests")
		}
		var current = original
		let lease = AutofillSessionLease(current: { current }, workspace: workspace, distributed: distributed)
		current = AutofillConsoleSession(userID: 501, identifier: UUID().uuidString)
		try expect(!lease.isValid, "session replacement invalidates lease")
		current = original
		try expect(!lease.isValid, "returning to original session cannot revive a request")
	}

	static func cameraSessionTests() throws {
		let original = AutofillConsoleSession(userID: 501, identifier: UUID().uuidString)
		var current: AutofillConsoleSession? = original
		let workspace = NotificationCenter()
		let distributed = NotificationCenter()
		var sessions: [AutofillSessionLease] = []
		let gate = CameraSessionGate(scope: .foreground) {
			let session = AutofillSessionLease(current: { current }, workspace: workspace, distributed: distributed)
			sessions.append(session)
			return session
		}
		var stops = 0
		try expect(!gate.isValid, "foreground camera is invalid before a session begins")
		for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
			NSWorkspace.sessionDidResignActiveNotification] {
			try expect(gate.begin { stops += 1 }, "foreground capture begins in the unlocked owner session")
			let previousStops = stops
			workspace.post(name: name, object: nil)
			workspace.post(name: name, object: nil)
			try expect(!gate.isValid && stops == previousStops + 1, "sleep or user switching releases foreground capture once")
		}
		for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
			try expect(gate.begin { stops += 1 }, "explicit restart creates a new foreground lease")
			let previousStops = stops
			distributed.post(name: Notification.Name(name), object: nil)
			try expect(!gate.isValid && stops == previousStops + 1, "lock state change stops practice capture instead of keeping the camera")
		}
		current = nil
		try expect(!gate.begin { stops += 1 }, "foreground capture refuses a locked or unknown console before opening a camera")
		current = original
		try expect(!gate.isValid, "unlocking does not revive an invalidated foreground capture")
		try expect(gate.begin { stops += 1 }, "reopening after unlock can acquire a fresh session")
		current = AutofillConsoleSession(userID: 501, identifier: UUID().uuidString)
		let beforeReplacement = stops
		try expect(!gate.isValid && stops == beforeReplacement + 1, "authoritative session replacement stops capture even without a notification")
		current = original
		try expect(gate.begin { stops += 1 }, "new attempt can follow a stopped capture")
		let stale = sessions.last!
		try expect(gate.begin { stops += 1 }, "restart replaces the old lease")
		let beforeStale = stops
		stale.invalidate()
		try expect(gate.isValid && stops == beforeStale, "old capture invalidation cannot stop a newer session")
		gate.end()
		gate.end()
		try expect(!gate.isValid && stops == beforeStale, "normal teardown invalidates silently and is idempotent")
		let lockCamera = CameraSessionGate(scope: .lockScreen) {
			preconditionFailure("Lock-screen scanning must not acquire a foreground-only lease")
		}
		try expect(lockCamera.begin { stops += 1 }, "lock-screen camera uses its separate authentication session checks")
		distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
		try expect(lockCamera.isValid && stops == beforeStale, "foreground invalidation does not cancel the genuine lock-screen capture")
	}

	static func budgetTests() throws {
		var stored: AutofillAttemptBudget.State?
		var failRead = false
		var failWrite = false
		var ignoreWrite = false
		func makeBudget() -> AutofillAttemptBudget {
			AutofillAttemptBudget(load: {
				if failRead { throw TestError.injected }
				return stored
			}, save: {
				if failWrite { throw TestError.injected }
				if !ignoreWrite { stored = $0 }
			})
		}
		let budget = makeBudget()
		for attempt in 1...AutofillAttemptBudget.limit {
			try expect(budget.reserve() && stored?.attempts == attempt, "attempt reserved durably before recognition")
		}
		try expect(!budget.reserve(), "retry limit blocks additional recognition")
		try expect(!makeBudget().reserve(), "retry limit survives a new instance")
		try expect(budget.resetAfterOwnerApproval() && budget.reserve(), "owner-approved reset restores attempts")
		failRead = true
		try expect(!budget.reserve(), "read failure blocks attempts")
		failRead = false
		try expect(!budget.reserve(), "storage failure remains latched until owner-approved recovery")
		try expect(budget.resetAfterOwnerApproval(), "owner approval can recover storage after repair")
		failWrite = true
		try expect(!budget.reserve(), "write failure blocks attempts")
		try expect(!budget.resetAfterOwnerApproval(), "failed reset is not reported as success")
		failWrite = false
		_ = budget.resetAfterOwnerApproval()
		ignoreWrite = true
		try expect(!budget.reserve(), "unconfirmed write blocks attempts")
		ignoreWrite = false
		stored = .init(attempts: -1)
		try expect(!makeBudget().reserve(), "negative persisted counter rejected")
		stored = .init(attempts: Int.max)
		try expect(!makeBudget().reserve(), "oversized counter rejected without integer overflow")
	}

	static func frameTests() throws {
		let start = ContinuousClock.now
		var lease = CameraFrameLease()
		let first = lease.begin()
		try expect(lease.accepts(first, capturedAt: start, now: start), "current camera frame accepted")
		try expect(!lease.accepts(first, capturedAt: start, now: start.advanced(by: .seconds(1))), "delayed camera callback rejected")
		try expect(!lease.accepts(first, capturedAt: start.advanced(by: .seconds(1)), now: start), "future timestamp rejected")
		lease.stop()
		try expect(!lease.accepts(first, capturedAt: start, now: start), "stopped camera rejects callbacks")
		let second = lease.begin()
		try expect(first != second && !lease.accepts(first, capturedAt: start, now: start), "new capture rejects previous generation")
		var frames = RecognitionFrameGate(now: start)
		try expect(frames.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false), "first frame does not inherit a hold")
		try expect(frames.observe(id: 1, capturedAt: start, now: start.advanced(by: .milliseconds(100))) == .waiting, "frozen frame cannot advance recognition")
		let next = start.advanced(by: .milliseconds(120))
		try expect(frames.observe(id: 2, capturedAt: next, now: next) == .fresh(continuous: true), "advancing fresh frame continues hold")
		let gap = start.advanced(by: .milliseconds(500))
		try expect(frames.observe(id: 3, capturedAt: gap, now: gap) == .fresh(continuous: false), "frame gap breaks match and challenge continuity")
		try expect(frames.observe(id: 4, capturedAt: next, now: gap) == .waiting, "out-of-order capture rejected even with a new frame ID")
		try expect(frames.observe(id: 4, capturedAt: gap, now: gap.advanced(by: .seconds(2))) == .stalled, "stale camera ends recognition")
		var empty = RecognitionFrameGate(now: start)
		try expect(empty.observe(id: 0, capturedAt: nil, now: start.advanced(by: .seconds(2))) == .waiting, "cold camera waits without accepting evidence")
		try expect(empty.observe(id: 0, capturedAt: nil, now: start.advanced(by: .seconds(9))) == .stalled, "camera with no frames fails closed after bounded startup")
	}

	static func matchHoldTests() throws {
		let start = ContinuousClock.now
		let first = UUID()
		let second = UUID()
		var hold = RecognitionMatchHold()
		try expect(!hold.consume(faceID: first, now: start, required: .seconds(2)), "new identity has no inherited hold")
		try expect(!hold.consume(faceID: first, now: start.advanced(by: .seconds(1)), required: .seconds(2)), "short hold cannot pass")
		try expect(hold.consume(faceID: first, now: start.advanced(by: .seconds(2)), required: .seconds(2)), "same identity must meet the full hold")
		try expect(!hold.consume(faceID: second, now: start.advanced(by: .seconds(3)), required: .seconds(2)), "another enrolled face cannot inherit recognition")
		try expect(!hold.consume(faceID: first, now: start.advanced(by: .seconds(4)), required: .seconds(2)), "alternating identities restarts the hold")
		hold.reset()
		try expect(hold.faceID == nil, "face loss, poor quality or frame gap clears identity")
		try expect(!hold.consume(faceID: first, now: start.advanced(by: .seconds(10)), required: .seconds(2)), "reset discards elapsed match time")
		try expect(!hold.consume(faceID: first, now: start, required: .seconds(2)), "time reversal cannot satisfy the hold")
	}

	static func lockoutTests() throws {
		var stored: LockoutManager.State?
		let manager = LockoutManager(load: { stored }, save: { stored = $0 })
		try expect(manager.attemptsRemaining == 6, "empty lockout starts with six failures available")
		for _ in 0..<6 { manager.recordFailure() }
		try expect(!manager.mayAttempt() && manager.attemptsRemaining == 0, "six failures disable recognition")
		manager.recordFailure()
		try expect(stored?.consecutiveFailures == 6, "failure counter saturates without overflow")
		let reloaded = LockoutManager(load: { stored }, save: { stored = $0 })
		try expect(reloaded.isLockedOut, "lockout survives restart")
		manager.clearAfterPasswordAuth()
		try expect(manager.mayAttempt() && stored?.consecutiveFailures == 0, "explicit password-approved reset persists")
		for invalid in [-1, Int.min, 7, Int.max] {
			let corrupt = LockoutManager(load: { .init(consecutiveFailures: invalid) }, save: { _ in })
			try expect(corrupt.isLockedOut && corrupt.attemptsRemaining == 0, "invalid lockout counter fails closed")
			corrupt.recordFailure()
			try expect(corrupt.isLockedOut, "corrupt counter cannot overflow on rejection")
		}
		let unreadable = LockoutManager(load: { throw TestError.injected }, save: { _ in })
		try expect(unreadable.isLockedOut, "unreadable lockout denies recognition")
		let writeFailure = LockoutManager(load: { nil }, save: { _ in throw TestError.injected })
		writeFailure.recordFailure()
		try expect(writeFailure.isLockedOut, "lockout write failure denies more attempts")
		let dropped = LockoutManager(load: { nil }, save: { _ in })
		dropped.recordFailure()
		try expect(dropped.isLockedOut, "silently dropped lockout write fails readback")
		dropped.clearAfterPasswordAuth()
		try expect(dropped.isLockedOut, "reset cannot bypass failed persistence")
	}

	static func urlTests() throws {
		for value in ["https://gazeunlock.com/releases", "https://gazeunlock.com:443/download/latest"] {
			try expect(ReleaseURLPolicy.download(value) != nil, "official HTTPS update destination allowed")
		}
		for value in ["http://gazeunlock.com/download", "file:///Applications/Other.app", "javascript:alert(1)",
			"x-apple.systempreferences:privacy", "https://gazeunlock.com.attacker.test/file", "https://attacker.test/gazeunlock.com",
			"https://gazeunlock.com@attacker.test/file", "https://user:pass@gazeunlock.com/file", "https://gazeunlock.com:444/file",
			"https://gazeunlock.com/file#fragment", "//gazeunlock.com/file", "https://127.0.0.1/file"] {
			try expect(ReleaseURLPolicy.download(value) == nil, "untrusted update URL rejected")
		}
		try expect(ReleaseURLPolicy.download(nil) == nil, "absent download routes to fixed releases page")
		try expect(ReleaseURLPolicy.download("https://gazeunlock.com/" + String(repeating: "a", count: 4096)) == nil, "oversized update URL rejected")
		let configuration = ReleaseURLPolicy.sessionConfiguration()
		try expect(configuration.urlCredentialStorage == nil && configuration.httpCookieStorage == nil,
			"update requests do not reuse credentials or cookies")
		try expect(configuration.timeoutIntervalForResource == 20 && configuration.urlCache == nil, "update request lifetime bounded without persistent cache")
	}

	static func spoofTests() throws {
		for score: Float in [.nan, .infinity, -.infinity, -0.1, 1.1] {
			try expect(AntiSpoofGate(spoof: .init(score: score)).evaluate(FaceSample()) == .unavailable,
				"invalid anti-spoof score fails closed")
		}
		try expect(AntiSpoofGate(spoof: nil).evaluate(FaceSample()) == .unavailable, "missing anti-spoof model fails closed")
		try expect(AntiSpoofGate(spoof: .init(score: nil)).evaluate(FaceSample()) == .unavailable, "failed inference is not a live face")
		try expect(AntiSpoofGate(spoof: .init(score: 0.1)).evaluate(FaceSample()) == .live, "valid low score follows unchanged threshold")
		if case .spoof = AntiSpoofGate(spoof: .init(score: 0.7)).evaluate(FaceSample()) { checks += 1 }
		else { throw TestError.failed("spoof rejected at existing threshold") }
	}

	static func releaseTests() async throws {
		var reads = 0
		var writes = 0
		var valid = true
		let read: () throws -> String? = { reads += 1; return "synthetic-test-value" }
		let write: (String) -> Bool = { _ in writes += 1; return true }
		let denied = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { false }, resetBudget: { true }, read: read, write: write)
		try expect(denied == .ownerRejected && reads == 0 && writes == 0, "face match without owner approval never reads a secret")
		let switched = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { valid = false; return true }, resetBudget: { true }, read: read, write: write)
		try expect(switched == .stale && reads == 0 && writes == 0, "target/session change during owner prompt prevents reads")
		valid = true
		let budgetFailed = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { true }, resetBudget: { false }, read: read, write: write)
		try expect(budgetFailed == .budgetUnavailable && reads == 0, "retry-state failure prevents credential read")
		let changedOnRead = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { true }, resetBudget: { true }, read: {
			valid = false; return try read()
		}, write: write)
		try expect(changedOnRead == .stale && writes == 0, "target/session change during vault access prevents writes")
		valid = true
		let writeDenied = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { true }, resetBudget: { true }, read: read, write: { _ in false })
		try expect(writeDenied == .fieldNotWritable && writes == 0, "denied targeted write has no keyboard fallback")
		let readFailed = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { true }, resetBudget: { true }, read: { throw TestError.injected }, write: write)
		try expect(readFailed == .noPassword && writes == 0, "vault read error does not release a secret")
		let approved = await AutofillReleaseGate.release(isCurrent: { valid }, approve: { true }, resetBudget: { true }, read: read, write: write)
		try expect(approved == .filled && writes == 1, "approved unchanged target receives exactly one write")
		let cancelled = Task { @MainActor in
			withUnsafeCurrentTask { $0?.cancel() }
			return await AutofillReleaseGate.release(isCurrent: { true }, approve: { true }, resetBudget: { true }, read: read, write: write)
		}
		let cancelledResult = await cancelled.value
		try expect(cancelledResult == .stale && writes == 1, "cancelled task cannot release credentials")
	}
}
