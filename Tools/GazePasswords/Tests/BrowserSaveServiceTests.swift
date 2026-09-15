import Darwin
import Foundation
import LocalAuthentication

@main
struct BrowserSaveServiceTests {
	@MainActor static func main() async throws {
		var checks = 0
		func check(_ success: Bool, _ name: String) { precondition(success, name); checks += 1 }
		let origin = try BrowserOrigin("https://example.invalid")
		let request = BrowserMessage(operation: "save", requestID: UUID(), origin: origin, username: "synthetic-user", password: "synthetic-password")
		let console = AutofillConsoleSession(userID: 501, identifier: UUID().uuidString)
		var writes = 0
		var active = true
		var sessionValid = true
		let store = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in nil }, saveArchive: { _, _, _ in writes += 1 }, applicationIsActive: { true })
		let service = PasswordBrowserService(store: store, makeSession: {
			AutofillSessionLease(current: { sessionValid ? console : nil }, workspace: NotificationCenter(), distributed: NotificationCenter())
		}, activateVault: {}, applicationIsActive: { active })
		func waitForProposal() async throws {
			for _ in 0..<100 {
				if service.saveUsername != nil { return }
				try await Task.sleep(for: .milliseconds(10))
			}
			preconditionFailure("Save proposal did not arrive")
		}
		let status = try await service.handle(BrowserMessage(operation: "status", requestID: UUID(), origin: origin))
		check(status.operation == "status" && status.approved == nil && status.password == nil && store.isLocked, "status never unlocks or returns approval")
		let lockedRequest = Task { try await service.handle(request) }
		try await Task.sleep(for: .milliseconds(30))
		service.approveSave()
		check(service.saveUsername == nil && writes == 0, "locked vault never publishes or approves a capture")
		service.cancel()
		check((try? await lockedRequest.value) == nil, "locked capture cancels")
		await store.unlock()
		store.collection = .codes
		store.query = "not-a-fixture"
		let saving = Task { try await service.handle(request) }
		try await waitForProposal()
		check(service.request?.password == nil && service.request?.username == nil, "published request strips secrets")
		check(writes == 0, "showing confirmation never writes")
		service.approveSave()
		let reply = try await saving.value
		check(writes == 1 && store.archive?.entries.count == 1, "explicit approval commits exactly once")
		check(store.collection == .all && store.query.isEmpty && store.selected?.username == request.username,
			"saved browser login is visible even when previous code/search filters hid it")
		check(reply.operation == "saved" && reply.approved == true && reply.username == nil && reply.password == nil, "save acknowledgement carries no secrets")
		check(service.request == nil && service.saveUsername == nil, "finished capture clears public state")
		let same = Task { try await service.handle(request) }
		try await waitForProposal()
		check(service.saveAction == "Keep saved password", "same password shown as already saved")
		service.approveSave()
		_ = try await same.value
		check(writes == 1, "unchanged capture does not rewrite archive")
		var update = request
		update.password = "synthetic-updated-password"
		for reason in ["task", "cancel", "lock", "revision", "foreground", "session"] {
			if store.isLocked { await store.unlock() }
			active = true; sessionValid = true
			let attempt = Task { try await service.handle(update) }
			try await waitForProposal()
			if reason == "task" { attempt.cancel() }
			if reason == "cancel" { service.cancel() }
			if reason == "lock" { store.lock() }
			if reason == "revision" {
				var extra = PasswordEntry(title: "Other fixture", origin: origin, username: "other", password: "separate-synthetic")
				extra.id = UUID()
				try store.save(extra)
			}
			if reason == "foreground" { active = false }
			if reason == "session" { sessionValid = false }
			let before = writes
			service.approveSave()
			check((try? await attempt.value) == nil, "save denied after \(reason)")
			check(writes == before, "no capture write after \(reason)")
			check(service.request == nil && service.saveUsername == nil, "request cleared after \(reason)")
		}
		active = true; sessionValid = true
		store.lock()
		check(store.isLocked, "fixture vault finishes locked")
		var original = PasswordEntry(title: "Named account", origin: origin, username: "synthetic-user", password: "old-synthetic-password")
		original.favorite = true
		original.collection = "Work"
		original.verificationCode = try VerificationCode(input: "JBSWY3DPEHPK3PXP")
		var rejectWrite = true
		var failureWrites = 0
		let failureStore = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in PasswordArchive(version: 2, entries: [original]) },
			saveArchive: { _, _, _ in if rejectWrite { throw VaultError.changed }; failureWrites += 1 }, applicationIsActive: { true })
		let failureService = PasswordBrowserService(store: failureStore, makeSession: {
			AutofillSessionLease(current: { console }, workspace: NotificationCenter(), distributed: NotificationCenter())
		}, activateVault: {}, applicationIsActive: { true })
		func waitForFailureProposal() async throws {
			for _ in 0..<100 {
				if failureService.saveUsername != nil { return }
				try await Task.sleep(for: .milliseconds(10))
			}
			preconditionFailure("Failure fixture proposal did not arrive")
		}
		await failureStore.unlock()
		let rejectedSave = Task { try await failureService.handle(update) }
		try await waitForFailureProposal()
		var overlap = update
		overlap.requestID = UUID()
		check((try? await failureService.handle(overlap)) == nil, "overlapping save request is rejected")
		check(failureStore.errorMessage == nil, "overlapping save stays quiet while approval is pending")
		check(failureService.request?.requestID == update.requestID && failureService.saveUsername == original.username,
			"overlapping request cannot replace pending approval")
		failureService.approveSave()
		check((try? await rejectedSave.value) == nil, "failed persistence never receives success acknowledgement")
		check(failureStore.archive?.entries == [original] && failureWrites == 0, "failed save leaves original record intact")
		check(failureStore.errorMessage == VaultError.changed.localizedDescription, "persistence failure is visible")
		check(failureService.request == nil && failureService.saveUsername == nil, "failed write clears pending capture")
		rejectWrite = false
		let retry = Task { try await failureService.handle(update) }
		try await waitForFailureProposal()
		check(failureStore.errorMessage == nil, "new save approval clears the earlier persistence-failure text")
		check(failureService.saveAction == "Update password", "retry still recognizes exact existing login")
		failureService.approveSave()
		let retryReply = try await retry.value
		let updated = failureStore.archive!.entries[0]
		check(retryReply.approved == true && failureWrites == 1 && updated.password == update.password, "retry persists once after explicit approval")
		check(updated.id == original.id && updated.title == original.title && updated.favorite && updated.collection == "Work"
			&& updated.verificationCode == original.verificationCode, "browser update preserves code and user metadata")
		failureStore.lock()
		var wireWrites = 0
		let wireStore = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in nil },
			saveArchive: { _, _, _ in wireWrites += 1 }, applicationIsActive: { true })
		let wireService = PasswordBrowserService(store: wireStore, makeSession: {
			AutofillSessionLease(current: { console }, workspace: NotificationCenter(), distributed: NotificationCenter())
		}, activateVault: {}, applicationIsActive: { true })
		await wireStore.unlock()
		func roundTrip(_ request: BrowserMessage) async throws -> BrowserMessage {
			let input = Pipe()
			let output = Pipe()
			defer { try? input.fileHandleForReading.close(); try? output.fileHandleForReading.close() }
			let writer = Task.detached {
				defer { try? input.fileHandleForWriting.close() }
				try NativeMessageChannel.write(request, to: input.fileHandleForWriting)
			}
			let received = try NativeMessageChannel.read(from: input.fileHandleForReading)
			try await writer.value
			var descriptors: [Int32] = [0, 0]
			guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw BrowserBridgeError.unavailable }
			let client = BrowserSocket(descriptor: descriptors[0])
			let server = BrowserSocket(descriptor: descriptors[1])
			defer { client.close(); server.close() }
			let serving = Task {
				let message = try await Task.detached { try server.read() }.value
				let response = try await wireService.handle(message)
				try server.write(response)
			}
			let bridging = Task.detached {
				defer { try? output.fileHandleForWriting.close() }
				try client.write(received)
				let response = try client.read()
				try NativeMessageChannel.validateResponse(response, to: received)
				try NativeMessageChannel.write(response, to: output.fileHandleForWriting)
			}
			let before = wireWrites
			for _ in 0..<100 where wireService.saveUsername == nil { try await Task.sleep(for: .milliseconds(10)) }
			check(wireService.saveUsername == request.username, "pipe and socket request reaches exact login proposal")
			check(wireWrites == before, "transport cannot approve or persist by itself")
			wireService.approveSave()
			try await serving.value
			try await bridging.value
			let bytes = try output.fileHandleForReading.readToEnd()!
			let count = bytes.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
			check(Int(count) == bytes.count - 4, "save acknowledgement framing is intact")
			let response = try JSONDecoder().decode(BrowserMessage.self, from: bytes.dropFirst(4))
			check(response.requestID == request.requestID && response.origin == request.origin && response.operation == "saved"
				&& response.approved == true && response.username == nil && response.password == nil, "full transport returns bound secret-free acknowledgement")
			return response
		}
		_ = try await roundTrip(request)
		check(wireWrites == 1 && wireStore.archive?.entries.first?.password == request.password, "first wire save commits once")
		_ = try await roundTrip(update)
		check(wireWrites == 2 && wireStore.archive?.entries.count == 1 && wireStore.archive?.entries.first?.password == update.password,
			"wire update replaces exact login without duplicating it")
		_ = try await roundTrip(update)
		check(wireWrites == 2, "wire retry of unchanged save does not write again")
		wireStore.lock()
		print("Browser save service: \(checks) checks passed. Synthetic in-memory store and anonymous pipe/socket integration; no real vault, app activation, camera or browser used.")
	}
}
