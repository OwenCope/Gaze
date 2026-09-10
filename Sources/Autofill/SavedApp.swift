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

	/// Whether this place carries an identity Gaze can verify.
	var isVerifiable: Bool { requirement?.isEmpty == false }

	init(
		id: UUID = UUID(), bundleID: String, name: String, username: String = "",
		requirement: String? = nil
	) {
		self.id = id
		self.bundleID = bundleID
		self.name = name
		self.username = username
		self.requirement = requirement
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
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Autofill")

	private static func secretAccount(for id: UUID) -> String {
		"autofill-place-\(id.uuidString)"
	}

	private(set) var apps: [SavedApp] = []

	/// App icons, cached.
	///
	/// `NSWorkspace.icon(forFile:)` hits the filesystem and builds an `NSImage` every time
	/// it is called, and these are read from inside a SwiftUI list body — the same shape
	/// of mistake that made choosing a face portrait judder. `@ObservationIgnored` because
	/// it is filled during body evaluation, and mutating observed state there turns a
	/// redraw into a redraw loop.
	@ObservationIgnored private var iconCache: [String: NSImage?] = [:]

	init() {
		load()
	}

	// MARK: - Reading

	/// The place for whichever app is in front, if there is one.
	func savedApp(forBundleID bundleID: String) -> SavedApp? {
		apps.first { $0.bundleID == bundleID }
	}

	/// The real app icon, from the installed app.
	///
	/// Nil when the app is not installed any more — the row still shows, because deleting
	/// somebody's saved password because they moved an app would be worse than a blank
	/// tile, and reinstalling puts the icon straight back.
	func icon(for savedApp: SavedApp) -> NSImage? {
		icon(forBundleID: savedApp.bundleID)
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
		try SecureVault.load(Secret.self, from: Self.secretAccount(for: savedApp.id))?.password
	}

	private struct Secret: Codable {
		var password: String
	}

	// MARK: - Writing

	@discardableResult
	func add(bundleID: String, name: String, username: String, password: String) -> SavedApp? {
		// One entry per app. Adding an app that is already saved updates it instead of
		// creating a second row that silently never wins the match.
		// Re-read on every save, including an update. That is what lets someone repair a
		// record written before requirements existed, or one whose app has since been
		// re-signed, simply by saving the place again.
		let requirement = AppIdentity.designatedRequirement(forBundleID: bundleID)
		if requirement == nil {
			Self.logger.notice(
				"\(bundleID, privacy: .public) has no verifiable signature; it will not autofill.")
		}

		if var existing = savedApp(forBundleID: bundleID) {
			existing.username = username
			existing.name = name
			existing.requirement = requirement
			update(existing, password: password)
			return existing
		}

		let entry = SavedApp(
			bundleID: bundleID, name: name, username: username, requirement: requirement)
		do {
			try SecureVault.store(Secret(password: password), as: Self.secretAccount(for: entry.id))
		} catch {
			Self.logger.error("Could not store the password for \(name, privacy: .public).")
			return nil
		}
		apps.append(entry)
		apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		persist()
		return entry
	}

	/// Updates the row, and the password when a new one is given. Passing nil leaves the
	/// stored secret alone — editing a username should not require retyping a password.
	func update(_ savedApp: SavedApp, password: String?) {
		if let password {
			try? SecureVault.store(
				Secret(password: password), as: Self.secretAccount(for: savedApp.id))
		}
		if let index = apps.firstIndex(where: { $0.id == savedApp.id }) {
			apps[index] = savedApp
		}
		persist()
	}

	func remove(_ id: UUID) {
		// The secret goes first. If persisting the list failed afterwards the worst case is
		// a row with no password behind it, which the UI can show; the other order risks a
		// secret with no row, which nothing would ever clean up.
		SecureVault.remove(Self.secretAccount(for: id))
		apps.removeAll { $0.id == id }
		persist()
	}

	// MARK: - Persistence

	private func load() {
		do {
			apps = try SecureVault.load([SavedApp].self, from: Self.listAccount) ?? []
		} catch {
			Self.logger.error("Could not read the saved places; starting empty.")
			apps = []
		}
	}

	private func persist() {
		do {
			try SecureVault.store(apps, as: Self.listAccount)
		} catch {
			Self.logger.error("Could not save the places list.")
		}
	}
}
