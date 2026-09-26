import AppKit
import CoreGraphics

private enum TestError: Error {
	case assertion(String), vaultUnavailable, preparationFailed
}

private func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
	guard try value() else { throw TestError.assertion(message) }
}

private func expectFailure(_ operation: () throws -> Void) throws {
	do { try operation() } catch { return }
	throw TestError.assertion("Expected an error")
}

@MainActor
private final class SubmissionHarness {
	var session: LockedConsoleSession? = LockedConsoleSession(userID: 501, identifier: "00000000-0000-0000-0000-000000000001")
	var enabled = true
	var authorized = true
	var verified = true
	var executionPolicy = UnlockExecutionPolicy.normal
	var password: String? = "dummy-password"
	var reads = 0
	var preparations = 0
	var events: [CGEvent] = []
	var onRead: (() throws -> Void)?
	var onPrepare: (() throws -> Void)?
	var onPost: (() -> Void)?

	func submit() throws {
		try LockScreenPasswordSubmission.submit(
			readPassword: {
				self.reads += 1
				try self.onRead?()
				return self.password
			},
			currentSession: { self.session },
			isEnabled: { self.enabled },
			canPost: { self.authorized },
			isVerified: { self.verified },
			executionPolicy: executionPolicy,
			prepare: { password in
				self.preparations += 1
				try self.onPrepare?()
				return try Keystrokes.passwordEvents(password)
			},
			post: { event in
				self.events.append(event)
				self.onPost?()
			})
	}
}

@main
@MainActor
private enum SubmissionTests {
	static var passed = 0
	static var failed = 0

	static func test(_ name: String, _ operation: () async throws -> Void) async {
		do {
			try await operation()
			passed += 1
			print("PASS \(name)")
		} catch {
			failed += 1
			print("FAIL \(name): \(error)")
		}
	}

	static func payload(_ event: CGEvent) -> [UniChar] {
		var count = 0
		event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
		var units = [UniChar](repeating: 0, count: count)
		event.keyboardGetUnicodeString(maxStringLength: count, actualStringLength: &count, unicodeString: &units)
		return units
	}

	static func main() async {
		await test("automatic unlocking requires a fresh explicit opt-in and supports revocation") {
			let suite = "com.gazeunlock.Tests.UnlockConsent.\(UUID().uuidString)"
			let defaults = UserDefaults(suiteName: suite)!
			defer { defaults.removePersistentDomain(forName: suite) }
			try expect(!PasswordReplaySafety.isEnabled(in: defaults), "Fresh installation opted in")
			defaults.set("keystroke", forKey: "unlockBackend")
			try expectFailure { try PasswordReplaySafety.requireEnabled(in: defaults) }
			PasswordReplaySafety.setEnabled(true, in: defaults)
			try PasswordReplaySafety.requireEnabled(in: defaults)
			try expect(PasswordReplaySafety.isEnabled(in: UserDefaults(suiteName: suite)!), "Explicit opt-in did not persist")
			PasswordReplaySafety.setEnabled(false, in: defaults)
			try expectFailure { try PasswordReplaySafety.requireEnabled(in: defaults) }
		}
		await test("scan-only is independent of password replay settings") {
			for selected in [false, true] {
				for replay in [false, true] {
					try expect(UnlockExecutionPolicy.scanOnly.permitsScanning(passwordReplayEnabled: replay,
						keystrokeSelected: selected), "Diagnostic unexpectedly requires password replay")
					for policy in [UnlockExecutionPolicy.uiReview, .browserOnly] {
						try expect(!policy.permitsScanning(passwordReplayEnabled: replay,
							keystrokeSelected: selected), "Non-lock mode can scan the lock screen")
					}
					try expect(UnlockExecutionPolicy.normal.permitsScanning(passwordReplayEnabled: replay,
						keystrokeSelected: selected) == (replay && selected), "Normal mode bypassed suspension")
				}
			}
		}
		await test("launch flags keep scan-only and UI review fail-closed") {
			try expect(UnlockExecutionPolicy(arguments: []) == .normal, "Normal mode changed")
			try expect(UnlockExecutionPolicy(arguments: ["--ui-review"]) == .uiReview, "Review flag ignored")
			try expect(UnlockExecutionPolicy(arguments: ["--ui-review", "--scan-only"]) == .scanOnly, "Diagnostic mode ambiguous")
			try expect(!UnlockExecutionPolicy.scanOnly.permitsAutomaticLocking, "Diagnostic can lock Mac")
			try expect(UnlockExecutionPolicy.scanOnly.permitsLockObservation, "Diagnostic cannot observe manual lock")
			try expect(!UnlockExecutionPolicy.uiReview.permitsLockObservation, "UI review can observe lock")
		}
		for policy in [UnlockExecutionPolicy.uiReview, .scanOnly] {
			await test("\(policy) cannot read credentials or post events") {
				let harness = SubmissionHarness()
				harness.executionPolicy = policy
				try expectFailure { try harness.submit() }
				try expect(harness.reads == 0 && harness.preparations == 0 && harness.events.isEmpty, "Diagnostic crossed password boundary")
			}
		}
		await test("expired verification before submission does not read credentials") {
			let harness = SubmissionHarness()
			harness.verified = false
			try expectFailure { try harness.submit() }
			try expect(harness.reads == 0 && harness.events.isEmpty, "Unverified credential read")
		}
		await test("verification expiring during credential read prevents preparation") {
			let harness = SubmissionHarness()
			harness.onRead = { harness.verified = false }
			try expectFailure { try harness.submit() }
			try expect(harness.preparations == 0 && harness.events.isEmpty, "Expired read prepared events")
		}
		await test("verification expiring during event preparation prevents all posting") {
			let harness = SubmissionHarness()
			harness.onPrepare = { harness.verified = false }
			try expectFailure { try harness.submit() }
			try expect(harness.events.isEmpty, "Expired prepared events posted")
		}
		for boundary in 1...3 {
			await test("verification expiring after event \(boundary) stops remaining input") {
				let harness = SubmissionHarness()
				harness.onPost = { if harness.events.count == boundary { harness.verified = false } }
				try expectFailure { try harness.submit() }
				try expect(harness.events.count == boundary, "Events posted after proof expiry")
			}
		}
		await test("new lock cycle permits one password submission") {
			var budget = LockScreenSubmissionBudget()
			try expect(budget.reserve(), "First submission denied")
			try expect(!budget.maySubmit, "Reservation did not consume budget")
		}
		await test("repeated wake cannot replay a refused password") {
			var budget = LockScreenSubmissionBudget()
			_ = budget.reserve()
			for _ in 0..<10 { try expect(!budget.reserve(), "Repeated submission allowed") }
		}
		await test("verified unlock starts a new submission cycle") {
			var budget = LockScreenSubmissionBudget()
			_ = budget.reserve()
			budget.resetAfterVerifiedUnlock()
			try expect(budget.reserve(), "Verified unlock did not reset budget")
			try expect(!budget.reserve(), "Reset allowed multiple submissions")
		}
		await test("successful submission reads once and prepares before posting") {
			let harness = SubmissionHarness()
			try harness.submit()
			try expect(harness.reads == 1 && harness.preparations == 1, "Unexpected read/retry")
			try expect(harness.events.map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp], "Wrong event order")
			try expect(harness.events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, 0, 36, 36], "Wrong key sequence")
			try expect(payload(harness.events[0]) == Array("dummy-password".utf16), "Wrong text payload")
		}
		for change in ["unlocked", "disabled", "denied"] {
			await test("\(change) before submission does not read the vault") {
				let harness = SubmissionHarness()
				if change == "unlocked" { harness.session = nil }
				if change == "disabled" { harness.enabled = false }
				if change == "denied" { harness.authorized = false }
				try expectFailure { try harness.submit() }
				try expect(harness.reads == 0 && harness.events.isEmpty, "Unsafe credential access")
			}
		}
		for change in ["unlocked", "session switched", "disabled", "denied", "vault error"] {
			await test("\(change) during password read prevents posting") {
				let harness = SubmissionHarness()
				harness.onRead = {
					switch change {
					case "unlocked": harness.session = nil
					case "session switched": harness.session = LockedConsoleSession(userID: 501, identifier: "00000000-0000-0000-0000-000000000002")
					case "disabled": harness.enabled = false
					case "denied": harness.authorized = false
					default: throw TestError.vaultUnavailable
					}
				}
				try expectFailure { try harness.submit() }
				try expect(harness.reads == 1 && harness.events.isEmpty, "Posted after unsafe read")
				try expect(harness.preparations == 0, "Prepared unsafe credential")
			}
		}
		for password in [nil, "", "dummy\npassword", "dummy\tpassword", "dummy\u{0}password"] {
			await test("missing, empty or control-character password refuses submission") {
				let harness = SubmissionHarness()
				harness.password = password
				try expectFailure { try harness.submit() }
				try expect(harness.events.isEmpty, "Unsafe password was posted")
			}
		}
		await test("event preparation failure cannot submit Return") {
			let harness = SubmissionHarness()
			harness.onPrepare = { throw TestError.preparationFailed }
			try expectFailure { try harness.submit() }
			try expect(harness.events.isEmpty, "Return posted without text")
		}
		await test("session changes during event preparation block all events") {
			let harness = SubmissionHarness()
			harness.onPrepare = { harness.session = nil }
			try expectFailure { try harness.submit() }
			try expect(harness.events.isEmpty, "Stale prepared events posted")
		}
		for change in ["session", "permission", "enabled"] {
			for boundary in 1...3 {
				await test("\(change) changes after event \(boundary): remaining events stop") {
					let harness = SubmissionHarness()
					harness.onPost = {
						guard harness.events.count == boundary else { return }
						if change == "session" { harness.session = nil }
						if change == "permission" { harness.authorized = false }
						if change == "enabled" { harness.enabled = false }
					}
					try expectFailure { try harness.submit() }
					try expect(harness.events.count == boundary, "Posted after state change")
				}
			}
		}
		await test("cancelled task does not read credentials") {
			let harness = SubmissionHarness()
			let task = Task { @MainActor in
				withUnsafeCurrentTask { $0?.cancel() }
				try harness.submit()
			}
			switch await task.result {
			case .success: throw TestError.assertion("Cancellation ignored")
			case .failure(let error): try expect(error is CancellationError, "Wrong cancellation error")
			}
			try expect(harness.reads == 0 && harness.events.isEmpty, "Cancelled task accessed secret")
		}
		await test("cancellation during read prevents posting") {
			let harness = SubmissionHarness()
			harness.onRead = { withUnsafeCurrentTask { $0?.cancel() } }
			let task = Task { @MainActor in try harness.submit() }
			switch await task.result {
			case .success: throw TestError.assertion("Cancellation ignored")
			case .failure(let error): try expect(error is CancellationError, "Wrong cancellation error")
			}
			try expect(harness.events.isEmpty, "Cancelled read posted events")
		}
		await test("event source failure throws instead of returning success") {
			try expectFailure { _ = try Keystrokes.passwordEvents("dummy", makeSource: { nil }) }
		}
		for failedEvent in 1...4 {
			await test("failure constructing event \(failedEvent) aborts preparation") {
				var calls = 0
				try expectFailure {
					_ = try Keystrokes.passwordEvents("dummy", makeEvent: { source, key, down in
						calls += 1
						return calls == failedEvent ? nil : CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
					})
				}
				try expect(calls == failedEvent, "Continued after event-creation failure")
			}
		}
		await test("modifier flags and autorepeat are cleared") {
			let events = try Keystrokes.passwordEvents("dummy", makeEvent: { source, key, down in
				let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
				event?.flags = [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskAlphaShift]
				event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
				return event
			})
			try expect(events.allSatisfy { $0.flags.isEmpty }, "Modifiers leaked into password")
			try expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 }, "Autorepeat remained")
		}
		for text in ["dummy-密码-🔐", "dummy-e\u{301}-👩‍💻", String(repeating: "dummy-long-", count: 30)] {
			await test("Unicode payload is preserved without normalization or truncation") {
				let events = try Keystrokes.passwordEvents(text)
				try expect(payload(events[0]) == Array(text.utf16), "Payload changed")
			}
		}
		let valid: [String: Any] = [
			"CGSSessionScreenIsLocked": true,
			kCGSessionOnConsoleKey as String: true,
			kCGSessionLoginDoneKey as String: true,
			kCGSessionUserIDKey as String: NSNumber(value: 501),
			"CGSSessionUniqueSessionUUID": "00000000-0000-0000-0000-000000000001",
		]
		await test("locked local owner session is accepted") {
			try expect(LockedConsoleSession.validated(valid, owner: 501) == LockedConsoleSession(userID: 501, identifier: "00000000-0000-0000-0000-000000000001"), "Valid session rejected")
		}
		await test("malformed session identity fails closed") {
			var values = valid
			values["CGSSessionUniqueSessionUUID"] = "invalid"
			try expect(LockedConsoleSession.validated(values, owner: 501) == nil, "Invalid session accepted")
		}
		for key in valid.keys.sorted() {
			await test("missing session field \(key) fails closed") {
				var values = valid
				values.removeValue(forKey: key)
				try expect(LockedConsoleSession.validated(values, owner: 501) == nil, "Incomplete session accepted")
			}
		}
		await test("another account or non-console session cannot receive a password") {
			try expect(LockedConsoleSession.validated(valid, owner: 502) == nil, "Wrong account accepted")
			var values = valid
			values[kCGSessionOnConsoleKey as String] = false
			try expect(LockedConsoleSession.validated(values, owner: 501) == nil, "Background session accepted")
			try expect(LockedConsoleSession.validated(nil, owner: 501) == nil, "Unknown session accepted")
		}
		print("\(passed) passed; \(failed) failed. No events posted; dummy credentials only.")
		if failed != 0 { exit(1) }
	}
}
