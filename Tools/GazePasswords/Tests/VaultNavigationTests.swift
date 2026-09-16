import Foundation

@main
struct VaultNavigationTests {
	@MainActor static func main() async throws {
		var checks = 0
		func check(_ value: Bool, _ name: String) {
			precondition(value, name)
			checks += 1
		}
		var personal = PasswordEntry(title: "Personal account", origin: try BrowserOrigin("https://personal.invalid"), username: "demo", password: "synthetic-personal-password")
		personal.favorite = true
		var work = PasswordEntry(title: "Work account", origin: try BrowserOrigin("https://work.invalid"), username: "office", password: "synthetic-work-password")
		work.collection = "Work"
		work.verificationCode = try VerificationCode(input: "JBSWY3DPEHPK3PXP")
		let fixture = PasswordArchive(version: 2, entries: [personal, work])
		var writes = 0
		var failSave = false
		let store = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in fixture },
			saveArchive: { archive, _, _ in
				if failSave { throw VaultError.changed }
				_ = try archive.encoded()
				writes += 1
			}, applicationIsActive: { true })
		await store.unlock()
		check(store.selectedID == personal.id, "initial visible login selected")
		store.revealedID = personal.id
		store.query = "office work"
		check(store.selectedID == work.id && store.selected?.id == work.id, "multiword search selects visible result")
		check(store.revealedID == nil, "search conceals previous password")
		store.query = "nonexistent"
		check(store.selectedID == nil && store.entries.isEmpty, "no results clear stale selection")
		store.query = ""
		check(store.selectedID == personal.id, "clear search restores valid selection")
		store.selectedID = work.id
		store.query = "account"
		check(store.selectedID == work.id, "search keeps matching selected login")
		store.collection = .favorites
		check(store.selectedID == personal.id, "collection change selects matching login")
		store.collection = .codes
		check(store.selectedID == work.id, "codes selects code-bearing login")
		store.collection = .personal
		store.query = "missing"
		store.showEntry(work.id)
		check(store.query.isEmpty && store.collection == .all && store.selectedID == work.id, "show saved entry clears filters that conceal it")
		store.collection = .codes
		store.showEntry(work.id)
		check(store.collection == .codes && store.selectedID == work.id, "show saved code retains compatible collection")
		store.showEntry(UUID())
		check(store.collection == .codes && store.selectedID == work.id, "missing entry cannot alter navigation")
		check(writes == 0, "navigation never persists vault data")
		try store.setVerificationCode(nil, for: work)
		check(store.collection == .codes && store.selectedID == nil && store.entries.isEmpty, "removing last code leaves honest empty state")
		store.collection = .favorites
		try store.toggleFavorite(personal)
		check(store.collection == .favorites && store.selectedID == nil, "unfavorite stays in favorites without stale detail")
		store.collection = .all
		store.selectedID = personal.id
		var changed = personal
		changed.favorite = false
		changed.title = "Renamed account"
		failSave = true
		do { try store.save(changed, replacing: store.selected); fatalError("failed persistence accepted") }
		catch VaultError.changed {}
		check(store.selectedID == personal.id && store.selected?.title == personal.title, "save failure preserves selection and content")
		let alpha = PasswordEntry(title: "Alpha shared", origin: try BrowserOrigin("https://alpha.invalid"), username: "alpha", password: "synthetic-alpha-password")
		let bravo = PasswordEntry(title: "Bravo shared", origin: try BrowserOrigin("https://bravo.invalid"), username: "bravo", password: "synthetic-bravo-password")
		let charlie = PasswordEntry(title: "Charlie solo", origin: try BrowserOrigin("https://charlie.invalid"), username: "charlie", password: "synthetic-charlie-password")
		var navWrites = 0
		let nav = LocalPasswordStore(authenticate: { _ in true },
			loadArchive: { _ in PasswordArchive(version: 1, entries: [charlie, alpha, bravo]) },
			saveArchive: { archive, _, _ in _ = try archive.encoded(); navWrites += 1 },
			applicationIsActive: { true })
		await nav.unlock()
		check(nav.selectedID == alpha.id, "keyboard navigation starts on first visible login")
		nav.moveSelection(by: 1)
		check(nav.selectedID == bravo.id, "down arrow advances to next visible login")
		nav.moveSelection(by: 1)
		check(nav.selectedID == charlie.id, "down arrow traverses sorted visible logins")
		nav.moveSelection(by: 1)
		check(nav.selectedID == charlie.id, "down arrow clamps at last login without wrapping")
		nav.moveSelection(by: -1)
		check(nav.selectedID == bravo.id, "up arrow moves to previous visible login")
		nav.moveSelection(by: -1)
		nav.moveSelection(by: -1)
		check(nav.selectedID == alpha.id, "up arrow clamps at first login without wrapping")
		nav.query = "shared"
		check(nav.entries.map(\.id) == [alpha.id, bravo.id] && nav.selectedID == alpha.id, "filter narrows visible logins for keyboard traversal")
		nav.moveSelection(by: 1)
		check(nav.selectedID == bravo.id, "keyboard traversal follows filtered logins")
		nav.moveSelection(by: 1)
		check(nav.selectedID == bravo.id, "filtered traversal clamps at last filtered login")
		nav.selectedID = nil
		nav.moveSelection(by: 1)
		check(nav.selectedID == alpha.id, "down arrow without selection selects first filtered login")
		nav.selectedID = UUID()
		nav.moveSelection(by: -1)
		check(nav.selectedID == alpha.id, "up arrow with stale selection selects first filtered login")
		nav.query = "nonexistent"
		check(nav.selectedID == nil && nav.entries.isEmpty, "no results leave no keyboard selection")
		nav.moveSelection(by: 1)
		nav.moveSelection(by: -1)
		check(nav.selectedID == nil, "keyboard navigation stays empty with no results")
		nav.query = ""
		nav.selectedID = bravo.id
		nav.revealedID = bravo.id
		nav.moveSelection(by: 1)
		check(nav.selectedID == charlie.id && nav.revealedID == nil, "keyboard move conceals revealed password")
		nav.moveSelection(by: 5)
		check(nav.selectedID == charlie.id, "unsupported keyboard offset leaves selection alone")
		nav.lock()
		nav.moveSelection(by: 1)
		nav.moveSelection(by: -1)
		check(nav.isLocked && nav.selectedID == nil, "locked vault refuses keyboard navigation")
		var now = ContinuousClock.now
		let expiring = LocalPasswordStore(authenticate: { _ in true },
			loadArchive: { _ in PasswordArchive(entries: [alpha]) },
			saveArchive: { _, _, _ in preconditionFailure("Navigation must not persist") }, applicationIsActive: { true },
			currentTime: { now })
		await expiring.unlock()
		let pinned = expiring.selectedID
		now = now.advanced(by: .seconds(301))
		check(expiring.isLocked, "expiry locks vault before keyboard refusal check")
		expiring.moveSelection(by: 1)
		check(expiring.selectedID == pinned && expiring.revealedID == nil, "expired session refuses keyboard navigation")
		expiring.lock()
		check(navWrites == 0, "keyboard navigation never persists vault data")
		store.lock()
		store.showEntry(personal.id)
		check(store.isLocked && store.selectedID == nil, "navigation cannot reopen locked vault")
		check(writes == 2, "only requested fixture mutations persisted")
		print("Vault navigation: \(checks) checks passed. In-memory fixtures only; no Keychain, browser or clipboard access.")
	}
}
