import Darwin
import Foundation

@MainActor
private final class FillFixture {
	let origin = try! BrowserOrigin("https://example.invalid")
	let console = AutofillConsoleSession(userID: 501, identifier: UUID().uuidString)
	let entry: PasswordEntry
	let other: PasswordEntry
	let store: LocalPasswordStore
	var active = true
	var validSession = true
	var connects = 0
	var launches = 0
	var unavailableConnections = 0
	var untrusted = false
	var holdResponse = false
	var received: BrowserMessage?
	var mutateReply: (BrowserMessage) -> BrowserMessage = { $0 }
	var onLaunch: (() -> Void)?
	var onConnect: (() -> Void)?
	private var client: BrowserSocket?
	private var server: BrowserSocket?
	private var serving: Task<Void, Never>?

	lazy var service = PasswordBrowserService(store: store, makeSession: { [unowned self] in
		AutofillSessionLease(current: { [unowned self] in validSession ? console : nil }, workspace: NotificationCenter(), distributed: NotificationCenter())
	}, activateVault: {}, applicationIsActive: { [unowned self] in active }, connectGaze: { [unowned self] in
		connects += 1
		if untrusted { throw BrowserBridgeError.untrustedPeer }
		if unavailableConnections > 0 { unavailableConnections -= 1; throw BrowserBridgeError.unavailable }
		var descriptors: [Int32] = [0, 0]
		guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw BrowserBridgeError.unavailable }
		let client = BrowserSocket(descriptor: descriptors[0])
		let server = BrowserSocket(descriptor: descriptors[1])
		self.client = client; self.server = server
		serving = Task { [weak self] in
			do {
				let message = try await Task.detached { try server.read() }.value
				guard let self else { return }
				received = message
				while holdResponse { try await Task.sleep(for: .milliseconds(5)) }
				let response = message.operation == "status" ? message.response(operation: "status") : message.response(operation: "verified", approved: true)
				try server.write(mutateReply(response))
			} catch { }
		}
		onConnect?()
		return client
	}, launchGaze: { [unowned self] in launches += 1; onLaunch?() })

	init() throws {
		entry = PasswordEntry(title: "Fixture", origin: origin, username: "fixture-user", password: "synthetic-fixture-password")
		other = PasswordEntry(title: "Other", origin: try BrowserOrigin("https://other.invalid"), username: "other", password: "synthetic-other-password")
		let archive = PasswordArchive(entries: [entry, other])
		store = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in archive }, saveArchive: { archive, _, _ in _ = try archive.encoded() }, applicationIsActive: { true })
	}

	func begin(unlock: Bool = true) async throws -> Task<BrowserMessage, Error> {
		if unlock { await store.unlock() }
		let request = BrowserMessage(operation: "fill", requestID: UUID(), origin: origin)
		let task = Task { try await service.handle(request) }
		try await waitUntil { self.service.request != nil }
		return task
	}

	func waitUntil(_ condition: () -> Bool) async throws {
		for _ in 0..<200 {
			if condition() { return }
			try await Task.sleep(for: .milliseconds(5))
		}
		preconditionFailure("Fixture timed out")
	}

	func close() {
		service.cancel(); store.lock(); serving?.cancel(); client?.close(); server?.close()
	}
}

@main
struct BrowserFillServiceTests {
	@MainActor static func main() async throws {
		var checks = 0
		func check(_ success: Bool, _ message: String) { precondition(success, message); checks += 1 }
		let direct = try FillFixture()
		let pending = try await direct.begin()
		check(direct.connects == 0 && direct.launches == 0, "no camera service connection before login choice")
		direct.service.approve(direct.entry.id)
		let filled = try await pending.value
		check(direct.launches == 0 && direct.connects == 1, "reuse existing verified service without app launch")
		check(direct.received?.operation == "verify" && direct.received?.password == nil && direct.received?.username == nil, "Gaze gets no credentials")
		check(filled.operation == "filled" && filled.approved == true && filled.password == direct.entry.password, "approved current exact-site login returned")
		check(direct.service.request == nil && !direct.service.verifying, "success clears pending service state")
		direct.close()

		let overlap = try FillFixture()
		let first = try await overlap.begin()
		let duplicate = BrowserMessage(operation: "fill", requestID: UUID(), origin: overlap.origin)
		check((try? await overlap.service.handle(duplicate)) == nil, "overlapping fill is rejected")
		check(overlap.store.errorMessage == nil, "rejected overlap stays quiet while approval is pending")
		overlap.service.approve(overlap.entry.id)
		check(try await first.value.approved == true, "owning approval still succeeds after an overlap")
		check(overlap.store.errorMessage == nil, "successful approval leaves no stale failure text")
		overlap.close()

		let stale = try FillFixture()
		let failed = try await stale.begin()
		stale.service.approve(stale.other.id)
		check((try? await failed.value) == nil, "wrong-site fill fails")
		check(stale.store.errorMessage != nil, "genuine failure is still reported")
		let retried = try await stale.begin()
		check(stale.store.errorMessage == nil, "new approval clears the earlier failure text")
		stale.service.approve(stale.entry.id)
		check(try await retried.value.approved == true && stale.store.errorMessage == nil, "retry succeeds without stale text")
		stale.close()

		let cold = try FillFixture(); cold.unavailableConnections = 1
		let coldTask = try await cold.begin(); cold.service.approve(cold.entry.id)
		check(try await coldTask.value.approved == true, "cold launch connects and approves")
		check(cold.launches == 1 && cold.connects == 2, "only missing service triggers launch")
		cold.close()

		let status = try FillFixture()
		await status.service.checkGazeConnection()
		check(status.service.gazeSummary == "Connected" && status.store.isLocked, "status checks connection without unlocking")
		check(status.received?.operation == "status" && status.launches == 0, "status does not start camera approval or launch app")
		status.close()

		for scenario in ["wrong-site", "locked", "untrusted", "cancel-before-choice"] {
			let fixture = try FillFixture()
			let task = try await fixture.begin(unlock: scenario != "locked")
			fixture.untrusted = scenario == "untrusted"
			if scenario == "cancel-before-choice" { fixture.service.cancel() }
			else { fixture.service.approve(scenario == "wrong-site" ? fixture.other.id : fixture.entry.id) }
			check((try? await task.value) == nil, "deny \(scenario)")
			check(fixture.received == nil && fixture.launches == 0, "\(scenario) cannot contact Gaze or launch another copy")
			fixture.close()
		}

		for scenario in ["lock", "session", "revision", "focus", "cancel"] {
			let fixture = try FillFixture(); fixture.unavailableConnections = 1
			fixture.onLaunch = {
				switch scenario {
				case "lock": fixture.store.lock()
				case "session": fixture.validSession = false
				case "revision": try! fixture.store.toggleFavorite(fixture.entry)
				case "focus": fixture.active = false
				default: fixture.service.cancel()
				}
			}
			let task = try await fixture.begin(); fixture.service.approve(fixture.entry.id)
			check((try? await task.value) == nil, "startup \(scenario) cancels approval")
			check(fixture.received == nil && fixture.connects == 1, "startup \(scenario) stops before another connection")
			fixture.onLaunch = nil; fixture.close()
		}

		let interrupted = try FillFixture()
		interrupted.onConnect = { interrupted.store.lock() }
		let interruptedTask = try await interrupted.begin(); interrupted.service.approve(interrupted.entry.id)
		check((try? await interruptedTask.value) == nil && interrupted.received == nil, "lock during connect cannot send verification request")
		interrupted.onConnect = nil; interrupted.close()

		for scenario in ["wrong-origin", "wrong-nonce", "denied", "credential-reply", "error", "wrong-operation", "wrong-version"] {
			let fixture = try FillFixture()
			fixture.mutateReply = { reply in
				var reply = reply
				switch scenario {
				case "wrong-origin": reply.origin = fixture.other.origin
				case "wrong-nonce": reply.requestID = UUID()
				case "denied": reply.approved = false
				case "credential-reply": reply.password = "unexpected-fixture"
				case "error": reply.error = "Fixture rejection"
				case "wrong-version": reply.version = 99
				default: reply.operation = "status"
				}
				return reply
			}
			let task = try await fixture.begin(); fixture.service.approve(fixture.entry.id)
			check((try? await task.value) == nil, "Gaze \(scenario) never releases credentials")
			check(fixture.service.request == nil && !fixture.service.verifying, "\(scenario) cleans request state")
			fixture.mutateReply = { $0 }; fixture.close()
		}

		for scenario in ["lock", "session", "revision", "focus", "cancel", "task-cancel"] {
			let fixture = try FillFixture(); fixture.holdResponse = true
			let task = try await fixture.begin(); fixture.service.approve(fixture.entry.id)
			try await fixture.waitUntil { fixture.received != nil }
			switch scenario {
			case "lock": fixture.store.lock()
			case "session": fixture.validSession = false
			case "revision": try fixture.store.toggleFavorite(fixture.entry)
			case "focus": fixture.active = false
			case "task-cancel": task.cancel()
			default: fixture.service.cancel()
			}
			fixture.holdResponse = false
			check((try? await task.value) == nil, "\(scenario) after face request cannot release credentials")
			check(fixture.service.request == nil && !fixture.service.verifying, "\(scenario) clears pending approval")
			fixture.close()
		}
		print("Browser fill service: \(checks) checks passed. Mock authentication, in-memory vault and socket pairs only; no camera, browser, Keychain or app launches.")
	}
}
