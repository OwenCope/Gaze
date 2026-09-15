import Foundation

@main
struct VaultPersistenceTests {
	@MainActor static func main() async throws {
		var checks = 0
		func check(_ value: Bool, _ name: String) {
			precondition(value, name)
			checks += 1
		}
		func locked(_ operation: () throws -> Void) -> Bool {
			do { try operation(); return false } catch VaultError.locked { return true } catch { return false }
		}
		func changed(_ operation: () throws -> Void) -> Bool {
			do { try operation(); return false } catch VaultError.changed { return true } catch { return false }
		}
		let origin = try BrowserOrigin("https://example.invalid")
		func synthetic(_ username: String) -> PasswordEntry {
			PasswordEntry(title: "Synthetic \(username)", origin: origin, username: username, password: "synthetic-password-\(username)")
		}

		// Missing vault creates an empty in-memory archive without error; first save adds.
		var missingWrites = 0
		var missingExpected: UUID?? = .some(nil)
		let missing = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in nil },
			saveArchive: { archive, expected, _ in
				guard expected == nil else { throw VaultError.changed }
				_ = try archive.encoded()
				missingWrites += 1
				missingExpected = .some(expected)
			}, applicationIsActive: { true })
		await missing.unlock()
		check(!missing.isLocked && missing.errorMessage == nil, "missing vault unlocks empty without error")
		check(missing.archive?.entries.isEmpty == true && missing.selectedID == nil, "missing vault selects nothing")
		check(missingWrites == 0 && missingExpected == .some(nil), "missing vault performs no read-time write")
		let first = synthetic("fixture-one")
		try missing.save(first)
		check(missingWrites == 1 && missing.archive?.entries == [first], "first save persists into missing vault")
		check(missing.selectedID == first.id && missing.revealedID == nil, "first save selects entry and conceals")
		missing.lock()

		// Failed reads never recreate the vault and stay actionable.
		var failedWrites = 0
		let failed = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in throw VaultError.system(1) },
			saveArchive: { _, _, _ in failedWrites += 1 }, applicationIsActive: { true })
		await failed.unlock()
		check(failed.isLocked && failed.archive == nil, "system read failure remains locked without archive")
		check(failed.errorMessage == VaultError.system(1).localizedDescription, "system failure stays actionable")
		check(failedWrites == 0, "failed read never writes")
		let candidate = synthetic("fixture-two")
		check(locked { try failed.save(candidate) }, "locked add throws locked")
		check(locked { try failed.save(candidate, replacing: candidate) }, "locked edit with expected throws locked, not changed")
		check(locked { try failed.toggleFavorite(candidate) }, "locked favorite throws locked")
		check(locked { try failed.setVerificationCode(nil, for: candidate) }, "locked code edit throws locked")
		check(locked { _ = try failed.prepareRemoval(candidate.id) }, "locked removal preparation throws locked")
		check((try? failed.importEntries([candidate])) == nil && failedWrites == 0, "locked import never writes")
		failed.lock()

		// Mutations are rejected while an unlock is in progress.
		var gate: CheckedContinuation<Bool, Never>?
		let gating = LocalPasswordStore(authenticate: { _ in await withCheckedContinuation { gate = $0 } },
			loadArchive: { _ in nil }, applicationIsActive: { true })
		let attempt = Task { await gating.unlock() }
		while gate == nil { await Task.yield() }
		check(locked { try gating.save(candidate) }, "busy vault rejects saves")
		check(locked { _ = try gating.prepareRemoval(candidate.id) }, "busy vault rejects removal preparation")
		check((try? gating.importEntries([candidate])) == nil, "busy vault rejects imports")
		gate?.resume(returning: true)
		await attempt.value
		check(!gating.isLocked, "gated unlock completes after authentication")
		gating.lock()

		// Revision conflicts and save failures retain the correct in-memory data.
		let second = synthetic("fixture-two")
		var persisted = PasswordArchive(entries: [first, second])
		var writes = 0
		var failWrite = false
		let store = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in persisted },
			saveArchive: { next, expected, _ in
				if failWrite { throw VaultError.system(-50) }
				guard expected == persisted.revision else { throw VaultError.changed }
				_ = try next.encoded()
				persisted = next
				writes += 1
			}, applicationIsActive: { true })
		await store.unlock()
		store.selectedID = first.id
		store.revealedID = first.id
		var stale = first
		stale.title = "Stale synthetic edit"
		check(changed { try store.save(stale, replacing: PasswordEntry(title: "Other", origin: origin, username: "other", password: "synthetic-password-other")) },
			"mismatched identifier rejected as changed")
		var external = second
		external.password = "synthetic-external-update"
		persisted.entries[1] = external
		persisted.revision = UUID()
		var conflicting = second
		conflicting.title = "Conflicting synthetic edit"
		check(changed { try store.save(conflicting, replacing: second) }, "Keychain revision conflict propagated")
		check(store.archive?.entries == [first, second] && writes == 0, "conflict retains in-memory archive")
		check(store.selectedID == first.id && store.revealedID == first.id, "conflict preserves selection and reveal")
		failWrite = true
		var renamed = first
		renamed.title = "Renamed synthetic login"
		check((try? store.save(renamed, replacing: first)) == nil, "persistence failure surfaced")
		check(store.archive?.entries == [first, second], "failed save retains previous logins")
		check(store.selectedID == first.id && store.revealedID == first.id, "failed save preserves selection and reveal")
		check(store.selected?.title == first.title, "failed save preserves content")
		failWrite = false

		// Imports write once, skip without writing, and enforce bounds without mutating.
		let duplicateWrites = writes
		check(try store.importEntries([first, second]) == 0 && writes == duplicateWrites, "repeat import does not write")
		var overfull = persisted
		overfull.entries = (0..<1000).map { synthetic("bulk-\($0)") }
		let full = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in overfull },
			saveArchive: { _, _, _ in writes += 1 }, applicationIsActive: { true })
		await full.unlock()
		check((try? full.importEntries([synthetic("overflow")])) == nil, "over-capacity import rejected")
		check(full.archive?.entries.count == 1000, "rejected import leaves archive unchanged")
		full.lock()

		// Lock clears selection, reveal, search and busy state.
		store.query = "fixture"
		check(store.revealedID == nil, "search conceals revealed password")
		store.query = ""
		store.selectedID = first.id
		store.revealedID = first.id
		store.lock()
		check(store.isLocked && store.archive == nil && store.entries.isEmpty, "lock discards archive")
		check(store.selectedID == nil && store.revealedID == nil && store.query.isEmpty && !store.busy, "lock clears selection, reveal, search and busy")
		check(locked { try store.save(first) }, "mutations after lock throw locked")

		// Deliberately ignore cancellation in the injected wait to exercise a timer
		// that has already woken while a newer vault session is being established.
		var expirations: [CheckedContinuation<Void, Never>] = []
		var resumed = 0
		let timed = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in nil },
			saveArchive: { _, _, _ in preconditionFailure("Timer test must not persist") }, applicationIsActive: { true },
			waitForExpiry: {
				await withCheckedContinuation { expirations.append($0) }
				resumed += 1
			})
		await timed.unlock()
		while expirations.count < 1 { await Task.yield() }
		timed.lock()
		await timed.unlock()
		while expirations.count < 2 { await Task.yield() }
		expirations[0].resume()
		while resumed < 1 { await Task.yield() }
		await Task.yield()
		check(!timed.isLocked, "old expiry cannot lock a newer vault session")
		expirations[1].resume()
		while resumed < 2 { await Task.yield() }
		await Task.yield()
		check(timed.isLocked, "current expiry locks its own vault session")

		var now = ContinuousClock.now
		var releaseTimer: CheckedContinuation<Void, Never>?
		var deadlineWrites = 0
		let deadlineStore = LocalPasswordStore(authenticate: { _ in true },
			loadArchive: { _ in PasswordArchive(entries: [first]) },
			saveArchive: { _, _, _ in deadlineWrites += 1 }, applicationIsActive: { true },
			currentTime: { now }, waitForExpiry: { await withCheckedContinuation { releaseTimer = $0 } })
		await deadlineStore.unlock()
		while releaseTimer == nil { await Task.yield() }
		now = now.advanced(by: .seconds(299))
		check(!deadlineStore.isLocked && deadlineStore.entries.count == 1, "vault remains usable before its deadline")
		now = now.advanced(by: .seconds(1))
		check(deadlineStore.isLocked && deadlineStore.entries.isEmpty && deadlineStore.selected == nil,
			"deadline conceals logins even while the timer callback is suspended")
		check(locked { try deadlineStore.save(first) }, "expired vault cannot save while its timer is delayed")
		check(locked { _ = try deadlineStore.prepareRemoval(first.id) }, "expired vault cannot prepare removal")
		check(locked { _ = try deadlineStore.importEntries([second]) }, "expired vault cannot import")
		check(deadlineWrites == 0, "expired mutations never reach persistence")
		deadlineStore.lock()
		releaseTimer?.resume()
		print("Vault persistence: \(checks) checks passed. Synthetic in-memory archives only; no Keychain or real credentials accessed.")
	}
}
