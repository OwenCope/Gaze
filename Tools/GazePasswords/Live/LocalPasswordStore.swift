import AppKit
import Combine
import LocalAuthentication

enum PasswordCollection: String, CaseIterable {
	case all = "All passwords", codes = "Codes", favorites = "Favorites", review = "Security review", personal = "Personal", work = "Work"
}

enum PasswordsBuild {
	#if PASSWORDS_UI_REVIEW
	static let isUIReview = true
	static let title = "Gaze Passwords · UI Review"
	#else
	static let isUIReview = false
	static let title = "Gaze Passwords"
	#endif
}

struct VaultRemovalRequest {
	let identifier: UUID
	let sessionID: UUID
	let revision: UUID
	let title: String
	let includesVerificationCode: Bool
}

@MainActor
final class LocalPasswordStore: ObservableObject {
	@Published private(set) var archive: PasswordArchive?
	@Published private(set) var busy = false
	@Published var errorMessage: String?
	@Published var query = "" { didSet { reconcileSelection() } }
	@Published var collection = PasswordCollection.all { didSet { reconcileSelection() } }
	@Published private(set) var sessionID = UUID()
	@Published var selectedID: UUID?
	@Published var revealedID: UUID?
	private var context: LAContext?
	private var persistedRevision: UUID?
	private var generation = UUID()
	private var expiresAt: ContinuousClock.Instant?
	private var inactivity: Task<Void, Never>?
	private let authenticate: @MainActor (LAContext) async throws -> Bool
	private let loadArchive: @MainActor (LAContext) throws -> PasswordArchive?
	private let saveArchive: @MainActor (PasswordArchive, UUID?, LAContext) throws -> Void
	private let applicationIsActive: @MainActor () -> Bool
	private let foregroundPause: @MainActor () async throws -> Void
	private let currentTime: @MainActor () -> ContinuousClock.Instant
	private let waitForExpiry: @MainActor () async throws -> Void

	init(
		authenticate: @escaping @MainActor (LAContext) async throws -> Bool = {
			try await $0.evaluatePolicy(.deviceOwnerAuthentication,
				localizedReason: "Unlock your local Gaze Passwords vault")
		},
		loadArchive: @escaping @MainActor (LAContext) throws -> PasswordArchive? = { try KeychainPasswordVault(context: $0).load() },
		saveArchive: @escaping @MainActor (PasswordArchive, UUID?, LAContext) throws -> Void = { try KeychainPasswordVault(context: $2).save($0, replacing: $1) },
		applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
		foregroundPause: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(25)) },
		currentTime: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
		waitForExpiry: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(300)) }
	) {
		self.authenticate = authenticate
		self.loadArchive = loadArchive
		self.saveArchive = saveArchive
		self.applicationIsActive = applicationIsActive
		self.foregroundPause = foregroundPause
		self.currentTime = currentTime
		self.waitForExpiry = waitForExpiry
	}

	var isLocked: Bool {
		guard archive != nil, let expiresAt else { return true }
		return currentTime() >= expiresAt
	}
	var review: PasswordReview { PasswordReview(entries: isLocked ? [] : archive?.entries ?? []) }
	var entries: [PasswordEntry] {
		guard !isLocked else { return [] }
		let reviewIDs = collection == .review ? review.flaggedIDs : []
		return (archive?.entries ?? []).filter { entry in
			entry.matches(query) && (collection == .all || collection == .favorites && entry.favorite
				|| collection == .codes && entry.verificationCode != nil
				|| collection == .review && reviewIDs.contains(entry.id) || entry.collection == collection.rawValue)
		}.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
	}
	var selected: PasswordEntry? { entries.first { $0.id == selectedID } }

	func showEntry(_ identifier: UUID) {
		guard !isLocked, archive?.entries.contains(where: { $0.id == identifier }) == true else { return }
		query = ""
		if !entries.contains(where: { $0.id == identifier }) { collection = .all }
		selectedID = identifier
		revealedID = nil
	}

	func moveSelection(by offset: Int) {
		guard !isLocked else { return }
		guard offset == 1 || offset == -1 else { return }
		let visible = entries
		guard !visible.isEmpty else { return }
		if let current = selectedID, let index = visible.firstIndex(where: { $0.id == current }) {
			let next = min(max(index + offset, 0), visible.count - 1)
			let nextID = visible[next].id
			guard nextID != current else { return }
			selectedID = nextID
			revealedID = nil
		} else {
			selectedID = visible.first?.id
			revealedID = nil
		}
	}

	private func reconcileSelection(preferred: UUID? = nil) {
		let visible = entries
		let identifier = preferred ?? selectedID
		selectedID = visible.first(where: { $0.id == identifier })?.id ?? visible.first?.id
		revealedID = nil
	}

	func unlock() async {
		guard !PasswordsBuild.isUIReview else {
			errorMessage = "This UI-only build cannot access a vault. Use a correctly provisioned Gaze Passwords build."
			return
		}
		guard !busy, isLocked else { return }
		if archive != nil { lock() }
		busy = true
		errorMessage = nil
		let token = generation
		let authentication = LAContext()
		authentication.localizedCancelTitle = "Cancel"
		context = authentication
		defer { if generation == token { busy = false } }
		do {
			guard try await authenticate(authentication) else { throw VaultError.authentication }
			let deadline = currentTime().advanced(by: .seconds(2))
			while !applicationIsActive() {
				guard generation == token else { throw CancellationError() }
				try Task.checkCancellation()
				guard currentTime() < deadline else { throw VaultError.unlockInterrupted }
				try await foregroundPause()
			}
			guard generation == token else { throw CancellationError() }
			try Task.checkCancellation()
			authentication.interactionNotAllowed = true
			let loaded = try loadArchive(authentication)
			guard generation == token else { throw CancellationError() }
			try Task.checkCancellation()
			guard applicationIsActive() else { throw VaultError.unlockInterrupted }
			persistedRevision = loaded?.revision
			expiresAt = currentTime().advanced(by: .seconds(300))
			archive = loaded ?? PasswordArchive()
			selectedID = entries.first?.id
			let current = generation
			inactivity?.cancel()
			inactivity = Task { [weak self, waitForExpiry] in
				do { try await waitForExpiry() } catch { return }
				guard let self, self.generation == current else { return }
				self.lock()
			}
		} catch {
			if generation == token {
				lock()
				let authenticationError = error as? LAError
				let cancelled = error is CancellationError || Task.isCancelled
					|| authenticationError?.code == .userCancel || authenticationError?.code == .appCancel
					|| authenticationError?.code == .systemCancel
				if !cancelled { errorMessage = error.localizedDescription }
			}
		}
	}

	func save(_ entry: PasswordEntry, replacing expected: PasswordEntry? = nil) throws {
		guard !busy, !isLocked else { throw VaultError.locked }
		try entry.validate()
		if let expected {
			guard entry.id == expected.id, archive?.entries.first(where: { $0.id == expected.id }) == expected else { throw VaultError.changed }
		}
		try update { archive in
			if let index = archive.entries.firstIndex(where: { $0.id == entry.id }) {
				archive.entries[index] = entry
			} else { archive.entries.append(entry) }
		}
		reconcileSelection(preferred: entry.id)
	}

	func prepareRemoval(_ identifier: UUID) throws -> VaultRemovalRequest {
		guard !busy, !isLocked, let archive else { throw VaultError.locked }
		guard let entry = archive.entries.first(where: { $0.id == identifier }) else { throw VaultError.staleConfirmation }
		return VaultRemovalRequest(identifier: identifier, sessionID: sessionID, revision: archive.revision,
			title: entry.title, includesVerificationCode: entry.verificationCode != nil)
	}

	func remove(_ request: VaultRemovalRequest) throws {
		guard !busy, !isLocked, let archive else { throw VaultError.locked }
		guard request.sessionID == sessionID, request.revision == archive.revision,
			archive.entries.contains(where: { $0.id == request.identifier }) else { throw VaultError.staleConfirmation }
		try update { $0.entries.removeAll { $0.id == request.identifier } }
		selectedID = entries.first?.id
	}

	func toggleFavorite(_ entry: PasswordEntry) throws {
		var updated = entry
		updated.favorite.toggle()
		updated.modifiedAt = .now
		try save(updated, replacing: entry)
	}

	func setVerificationCode(_ code: VerificationCode?, for original: PasswordEntry) throws {
		try code?.validate()
		var updated = original
		updated.verificationCode = code
		updated.modifiedAt = .now
		try save(updated, replacing: original)
	}

	@discardableResult
	func importEntries(_ entries: [PasswordEntry]) throws -> Int {
		guard !isLocked, let archive, !busy else { throw VaultError.locked }
		try entries.forEach { try $0.validate() }
		let plan = PasswordImportPlan(candidates: entries, existing: archive.entries)
		guard !plan.entries.isEmpty else { return 0 }
		guard archive.entries.count + plan.entries.count <= 1000 else { throw VaultError.tooLarge }
		try update { $0.entries.append(contentsOf: plan.entries) }
		return plan.entries.count
	}

	private func update(_ mutation: (inout PasswordArchive) -> Void) throws {
		guard !busy, !isLocked, var updated = archive, let context else { throw VaultError.locked }
		mutation(&updated)
		if updated.entries.contains(where: { $0.verificationCode != nil }) { updated.version = 2 }
		updated.revision = UUID()
		try saveArchive(updated, persistedRevision, context)
		persistedRevision = updated.revision
		archive = updated
		revealedID = nil
	}

	func lock() {
		generation = UUID()
		sessionID = UUID()
		context?.invalidate()
		context = nil
		archive = nil
		expiresAt = nil
		persistedRevision = nil
		selectedID = nil
		revealedID = nil
		query = ""
		busy = false
		inactivity?.cancel()
		inactivity = nil
	}
}
