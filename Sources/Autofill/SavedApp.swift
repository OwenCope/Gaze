import AppKit
import Observation
import os

/// An app Gaze can fill a password into.
///
/// "SavedApp" rather than "credential" or "entry" because the thing being named is *where*
/// you are when you press the shortcut. Matching is by bundle identifier — the one piece
/// of an app's identity that survives being renamed, moved, or updated.
struct SavedApp: Identifiable, Codable, Hashable {
	let id: UUID
	/// `com.apple.Safari`. The key everything matches on.
	var bundleID: String
	/// What the app calls itself, captured when it was added so the row still reads
	/// sensibly on a Mac where the app has since been deleted.
	var name: String
	/// Optional, and shown under the name. Not required to fill — plenty of prompts ask
	/// only for a password, and demanding a username to save one would be pedantry.
	var username: String
	/// The app's designated requirement, captured when the place was saved.
	///
	/// This is the identity check that `bundleID` cannot provide, because a bundle
	/// identifier is a self-declared string and any app can claim any other app's. Set
	/// once, from the installed copy on disk, and checked against the live process before
	/// a password is ever typed.
	///
	/// Optional only so that records written before this existed still decode. They are
	/// *not* trusted on that account — a nil requirement means the place cannot be filled
	/// until it is saved again. Grandfathering them in would leave exactly the hole this
	/// closes, silently, for everyone who had already set the app up.
	var requirement: String?
	var applicationURL: URL?
	var revision: UUID?

	/// Whether this place carries an identity Gaze can verify.
	var isVerifiable: Bool { requirement?.isEmpty == false }

	init(
		id: UUID = UUID(), bundleID: String, name: String, username: String = "",
		requirement: String? = nil, applicationURL: URL? = nil
	) {
		self.id = id
		self.bundleID = bundleID
		self.name = name
		self.username = username
		self.requirement = requirement
		self.applicationURL = applicationURL
	}
}

protocol SavedAppVault {
	func load<Value: Decodable>(_ type: Value.Type, from account: String) throws -> Value?
	func store<Value: Encodable>(_ value: Value, as account: String) throws
	func remove(_ account: String) throws
}

struct EncryptedSavedAppVault: SavedAppVault {
	func load<Value: Decodable>(_ type: Value.Type, from account: String) throws -> Value? {
		try SecureVault.load(type, from: account)
	}

	func store<Value: Encodable>(_ value: Value, as account: String) throws {
		try SecureVault.store(value, as: account)
	}

	func remove(_ account: String) throws {
		try SecureVault.remove(account)
	}
}

/// The saved places, and their secrets.
///
/// The list and the passwords are stored separately and deliberately. The list is metadata
/// — which apps you have set up — and lives under one vault record. Each password lives
/// under its own record keyed by the place's id, so reading one secret never decrypts the
/// others, and removing a place can destroy its secret without rewriting anything else.
@Observable
@MainActor
final class SavedAppStore {

	private static let listAccount = "autofill-places"
	private static let transactionAccount = "autofill-pending-change"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Autofill")

	private static func secretAccount(for id: UUID) -> String {
		"autofill-place-\(id.uuidString)"
	}

	private(set) var apps: [SavedApp] = []
	private(set) var storageError: String?
	private(set) var isChanging = false
	@ObservationIgnored private let vault: any SavedAppVault
	@ObservationIgnored private let inspect: (URL) -> AppIdentity.Selection?
	@ObservationIgnored private let approveIdentity: () async -> Bool

	/// App icons, cached.
	///
	/// `NSWorkspace.icon(forFile:)` hits the filesystem and builds an `NSImage` every time
	/// it is called, and these are read from inside a SwiftUI list body — the same shape
	/// of mistake that made choosing a face portrait judder. `@ObservationIgnored` because
	/// it is filled during body evaluation, and mutating observed state there turns a
	/// redraw into a redraw loop.
	@ObservationIgnored private var iconCache: [String: NSImage?] = [:]

	init(
		vault: any SavedAppVault = EncryptedSavedAppVault(),
		inspect: @escaping (URL) -> AppIdentity.Selection? = AppIdentity.selection(forAppAt:),
		approveIdentity: @escaping () async -> Bool = {
			await BiometricGate.require(.replaceAutofillIdentity)
		}
	) {
		self.vault = vault
		self.inspect = inspect
		self.approveIdentity = approveIdentity
		reload()
	}

	// MARK: - Reading

	/// The place for whichever app is in front, if there is one.
	func savedApp(forBundleID bundleID: String) -> SavedApp? {
		guard storageError == nil else { return nil }
		return apps.first { $0.bundleID == bundleID }
	}

	/// The real app icon, from the installed app.
	///
	/// Nil when the app is not installed any more — the row still shows, because deleting
	/// somebody's saved password because they moved an app would be worse than a blank
	/// tile, and reinstalling puts the icon straight back.
	func icon(for savedApp: SavedApp) -> NSImage? {
		guard let url = savedApp.applicationURL else { return nil }
		if let cached = iconCache[url.path] { return cached }
		let icon = NSWorkspace.shared.icon(forFile: url.path)
		iconCache[url.path] = icon
		return icon
	}

	/// Keyed on the bundle identifier rather than on a saved `SavedApp`, so the suggestion
	/// rows — which are apps that have not been saved yet — share the same cache.
	func icon(forBundleID bundleID: String) -> NSImage? {
		if let cached = iconCache[bundleID] { return cached }
		let icon = NSWorkspace.shared
			.urlForApplication(withBundleIdentifier: bundleID)
			.map { NSWorkspace.shared.icon(forFile: $0.path) }
		iconCache[bundleID] = icon
		return icon
	}

	/// The stored password. Throws rather than returning nil on a decryption failure, so a
	/// broken vault is never mistaken for an empty one.
	func password(for savedApp: SavedApp) throws -> String? {
		try requireReady()
		guard apps.contains(savedApp) else { throw StoreError.changed }
		return try vault.load(Secret.self, from: Self.secretAccount(for: savedApp.id))?.password
	}

	private struct Secret: Codable, Equatable {
		var password: String
	}

	// MARK: - Writing

	@discardableResult
	func add(
		bundleID: String, name: String, username: String, password: String,
		selection: AppIdentity.Selection? = nil, replacing expected: SavedApp? = nil
	) async throws -> SavedApp {
		try requireReady()
		let current = apps.first { $0.bundleID == bundleID }
		guard current == expected else { throw StoreError.changed }
		isChanging = true
		defer { isChanging = false }
		var entry = current ?? SavedApp(bundleID: bundleID, name: name)
		if let selection {
			guard selection.bundleID == bundleID, inspect(selection.url) == selection else {
				throw StoreError.changed
			}
			if apps.contains(where: { $0.id == entry.id }), entry.requirement != selection.requirement {
				guard await approveIdentity() else { throw StoreError.notAuthorized }
			}
			try Task.checkCancellation()
			guard inspect(selection.url) == selection else { throw StoreError.changed }
			entry.requirement = selection.requirement
			entry.applicationURL = selection.url
		} else if !entry.isVerifiable {
			throw StoreError.selectionRequired
		}
		try Task.checkCancellation()
		entry.name = name
		entry.username = username
		entry.revision = UUID()
		var updated = apps.filter { $0.id != entry.id }
		updated.append(entry)
		updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		try commit(Change(apps: updated, id: entry.id, secret: Secret(password: password)))
		return entry
	}

	func remove(_ id: UUID) throws {
		try requireReady()
		guard apps.contains(where: { $0.id == id }) else { throw StoreError.changed }
		try commit(Change(apps: apps.filter { $0.id != id }, id: id, secret: nil))
	}

	private struct Change: Codable, Equatable {
		let apps: [SavedApp]
		let id: UUID
		let secret: Secret?
	}

	private enum StoreError: LocalizedError {
		case unavailable, busy, changed, notAuthorized, selectionRequired, unconfirmed

		var errorDescription: String? {
			switch self {
			case .unavailable: "Saved passwords are unavailable. Retry storage recovery before editing or filling."
			case .busy: "A saved-password change is already in progress."
			case .changed: "The selected app or saved record changed. Choose the app again."
			case .notAuthorized: "The signing identity was not changed. Fresh owner approval is required."
			case .selectionRequired: "Choose the application again to verify its signing identity."
			case .unconfirmed: "The saved-password change could not be confirmed."
			}
		}
	}

	private func requireReady() throws {
		guard storageError == nil else { throw StoreError.unavailable }
		guard !isChanging else { throw StoreError.busy }
	}

	func reload() {
		guard !isChanging else { return }
		do {
			if let pending = try vault.load(Change.self, from: Self.transactionAccount) {
				try finish(pending)
			}
			apps = try vault.load([SavedApp].self, from: Self.listAccount) ?? []
			storageError = nil
		} catch {
			recordFailure(error)
		}
	}

	private func commit(_ change: Change) throws {
		do {
			try storeConfirmed(change, as: Self.transactionAccount)
			try finish(change)
			apps = change.apps
		} catch {
			recordFailure(error)
			throw error
		}
	}

	private func finish(_ change: Change) throws {
		if let secret = change.secret {
			try storeConfirmed(secret, as: Self.secretAccount(for: change.id))
		} else {
			try removeConfirmed(Secret.self, from: Self.secretAccount(for: change.id))
		}
		try storeConfirmed(change.apps, as: Self.listAccount)
		try removeConfirmed(Change.self, from: Self.transactionAccount)
	}

	private func storeConfirmed<Value: Codable & Equatable>(_ value: Value, as account: String) throws {
		try vault.store(value, as: account)
		guard try vault.load(Value.self, from: account) == value else {
			throw StoreError.unconfirmed
		}
	}

	private func removeConfirmed<Value: Decodable>(_ type: Value.Type, from account: String) throws {
		try vault.remove(account)
		guard try vault.load(type, from: account) == nil else { throw StoreError.unconfirmed }
	}

	private func recordFailure(_ error: Error) {
		storageError = "\(error.localizedDescription) The change may be incomplete. Filling is blocked until storage recovery succeeds. Recovery finishes any pending change."
		Self.logger.error("Saved-password storage is unavailable; recovery is required.")
	}
}
