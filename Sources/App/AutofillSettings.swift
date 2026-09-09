import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Places pane: apps Gaze can fill a password into.
///
/// Laid out as rows rather than tiles, which is the opposite of the faces pane and for the
/// opposite reason. A face is a picture and belongs at picture size; a saved app is three
/// pieces of text with an icon in front of them, and it is scanned by reading down a
/// column. The rows are `SettingRow`, the same component the credits use, with the app's
/// real icon in the portrait slot — no drawn stand-ins, no generic key glyph per row.
struct AutofillSection: View {

	@Bindable var savedApps: SavedAppStore
	let store: FaceEnrollmentStore

	@State private var draft: SavedAppDraft?
	/// Detected once when the pane appears, not on every redraw — it reads plists off
	/// disk, and a body can run many times a second.
	@State private var suggestions: [PasswordApps.Suggestion] = []

	var body: some View {
		if !suggestions.isEmpty {
			SettingsSection(title: "Password apps on this Mac", footer: suggestionsFooter) {
				ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, app in
					if index > 0 { RowDivider() }
					suggestionRow(app)
				}
			}
		}

		SettingsSection(title: "Saved apps", footer: footer) {
			if savedApps.apps.isEmpty {
				emptyRow
			} else {
				ForEach(Array(savedApps.apps.enumerated()), id: \.element.id) { index, savedApp in
					if index > 0 { RowDivider() }
					row(for: savedApp)
				}
			}

			RowDivider()
			addRow
		}

		SettingsSection(title: "How it works", footer: shortcutFooter) {
			SettingToggle(
				title: "Fill automatically when an app asks",
				detail:
					"When a saved app comes forward showing a password box, Gaze offers to fill it",
				symbol: "wand.and.sparkles",
				isOn: Binding(
					get: { Preferences.shared.autofillOnActivation },
					set: { Preferences.shared.autofillOnActivation = $0 }))

			RowDivider()
			SettingRow(
				title: "Fill the focused field",
				detail: shortcutIsHeld
					? "Or press the shortcut yourself, any time"
					: "The shortcut isn't registered — another app may already use ⌥⌘G",
				symbol: "keyboard",
				symbolTint: shortcutIsHeld ? nil : Theme.warning
			) {
				Text("⌥⌘G")
					.font(Typography.detail.monospaced())
					.foregroundStyle(shortcutIsHeld ? Theme.secondaryLabel : Theme.warning)
			}

			RowDivider()
			SettingRow(
				title: "Accessibility",
				detail: AXIsProcessTrusted()
					? "Granted — Gaze can type into other apps"
					: "Needed before Gaze can type anything",
				symbol: "hand.raised.fill",
				symbolTint: AXIsProcessTrusted() ? nil : Theme.warning
			) {
				if !AXIsProcessTrusted() {
					Button("Open Settings") {
						NSWorkspace.shared.open(
							URL(
								string:
									"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
							)!)
					}
					.gazeButton(.standard, size: .small)
				}
			}
		}
		diagnosticsSection

		.onAppear { refreshSuggestions() }
		.onChange(of: savedApps.apps.count) { _, _ in refreshSuggestions() }
		.sheet(item: $draft) { draft in
			SavedAppEditor(draft: draft) { username, password in
				savedApps.add(
					bundleID: draft.bundleID, name: draft.name,
					username: username, password: password)
			}
		}
	}

	// MARK: - Diagnostics

	/// What happened last time, in plain words.
	///
	/// Exists because the honest failure mode of this feature is silence: nothing types,
	/// and there is no way from the outside to tell whether the shortcut never fired, the
	/// password box was never found, or the face was not recognised. Three very different
	/// problems that look identical. This says which one it was.
	@ViewBuilder
	private var diagnosticsSection: some View {
		SettingsSection(title: "Last attempt", footer: diagnosticsFooter) {
			if let last = AutofillService.lastOutcome {
				SettingRow(
					title: last.outcome.summary,
					detail: Self.relative.localizedString(for: last.at, relativeTo: Date()),
					symbol: last.outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
					symbolTint: last.outcome.isSuccess ? nil : Theme.warning
				) {
					EmptyView()
				}
			} else {
				SettingRow(
					title: "Nothing tried yet",
					detail: "Open a saved app, or press the shortcut in one",
					symbol: "clock"
				) {
					EmptyView()
				}
			}

			if let focus = AutofillService.lastFocusReport {
				RowDivider()
				SettingRow(
					title: "What Gaze last saw",
					detail: focus.summary,
					symbol: "text.cursor"
				) {
					EmptyView()
				}
			}
		}
	}

	/// Built once. A `RelativeDateTimeFormatter` per redraw is a lot of machinery for
	/// "2 minutes ago".
	private static let relative: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()

	private var diagnosticsFooter: String {
		"If a fill doesn't happen, this says which step stopped — a password box that isn't marked secure is the usual reason, and the shortcut works there even when automatic filling won't."
	}

	// MARK: - Suggestions

	private func suggestionRow(_ app: PasswordApps.Suggestion) -> some View {
		SettingRow(
			title: app.name,
			detail: "Found on this Mac",
			portrait: savedApps.icon(forBundleID: app.bundleID)
		) {
			Button("Set Up") {
				draft = SavedAppDraft(
					bundleID: app.bundleID, name: app.name, username: "", isExisting: false)
			}
			.gazeButton(.primary, size: .small)
		}
	}

	/// Re-run after saving, so an app that has just been set up drops out of the
	/// suggestions rather than sitting there offering to be added again.
	private func refreshSuggestions() {
		suggestions = PasswordApps.suggestions(excluding: savedApps.apps.map(\.bundleID))
	}

	private var suggestionsFooter: String {
		"Found by looking for apps that provide AutoFill passwords, rather than by matching a list of names — so anything you install later shows up here too."
	}

	// MARK: - Rows

	private var emptyRow: some View {
		SettingRow(
			title: "No apps saved yet",
			detail: "Add one and Gaze will fill its password when you press the shortcut",
			symbol: "key.slash"
		) {
			EmptyView()
		}
	}

	private func row(for savedApp: SavedApp) -> some View {
		SettingRow(
			title: savedApp.name,
			// The username, or an honest blank. "No username" would be a row of grey text
			// repeating on every entry that does not need one.
			detail: savedApp.username.isEmpty ? savedApp.bundleID : savedApp.username,
			portrait: savedApps.icon(for: savedApp)
		) {
			HStack(spacing: 8) {
				Button("Change Password…") {
					draft = SavedAppDraft(
						bundleID: savedApp.bundleID, name: savedApp.name,
						username: savedApp.username, isExisting: true)
				}
				.gazeButton(.standard, size: .small)

				Button {
					savedApps.remove(savedApp.id)
				} label: {
					Image(systemName: "minus.circle.fill")
						.foregroundStyle(Theme.danger)
				}
				.buttonStyle(.plain)
				.help("Remove \(savedApp.name)")
			}
		}
	}

	private var addRow: some View {
		SettingRow(
			title: "Add an app",
			detail: "Choose it from your Applications folder",
			symbol: "plus"
		) {
			Button("Choose App…") { chooseApp() }
				.gazeButton(.primary, size: .small)
		}
	}

	// MARK: - Adding

	/// Picks the app from disk rather than asking the user to type a bundle identifier.
	///
	/// The identifier is what matching runs on and nobody knows theirs. Reading it out of
	/// the bundle also gets the display name and the icon for free, and guarantees all
	/// three describe the same app — which typing them separately would not.
	private func chooseApp() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.application]
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.directoryURL = URL(fileURLWithPath: "/Applications")
		panel.prompt = "Choose"
		panel.message = "Pick the app Gaze should fill a password into."

		guard panel.runModal() == .OK, let url = panel.url,
			let bundle = Bundle(url: url),
			let bundleID = bundle.bundleIdentifier
		else { return }

		let name =
			(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
			?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
			?? url.deletingPathExtension().lastPathComponent

		let existing = savedApps.savedApp(forBundleID: bundleID)
		draft = SavedAppDraft(
			bundleID: bundleID, name: name,
			username: existing?.username ?? "", isExisting: existing != nil)
	}

	/// Read fresh each time the pane draws, rather than stored. Registration happens once
	/// at launch and cannot change while this window is open, so there is nothing to
	/// observe — and a cached copy would be the stale thing telling you it is fine.
	private var shortcutIsHeld: Bool { AppServices.shared.isAutofillShortcutRegistered }

	private var footer: String {
		savedApps.apps.isEmpty
			? "Gaze can type a saved password into an app when you ask it to, once it recognises you. Nothing is filled automatically and nothing is submitted for you."
			: "Passwords are encrypted with the Secure Enclave and never leave this Mac. Removing an app deletes its password."
	}

	private var shortcutFooter: String {
		"Automatic filling only ever acts on a saved app showing a focused password box. The shortcut is broader — it works in any text field, in any saved app. Neither presses Return for you."
	}
}

// MARK: - Editor

/// What the sheet is editing. A value rather than a `SavedApp`, because the app has been
/// chosen but nothing has been saved yet — and a half-made `SavedApp` in the store would be a
/// row with no password behind it.
struct SavedAppDraft: Identifiable {
	let id = UUID()
	let bundleID: String
	let name: String
	var username: String
	/// Whether this replaces a password already stored, which changes only what the sheet
	/// says — the store treats both the same.
	let isExisting: Bool
}

private struct SavedAppEditor: View {

	@State var draft: SavedAppDraft
	let save: (String, String) -> Void

	@State private var username: String = ""
	@State private var password: String = ""
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 4) {
				Text(draft.isExisting ? "Change the password for \(draft.name)" : "Save \(draft.name)")
					.font(Typography.heroTitle)
					.foregroundStyle(Theme.label)
				Text(draft.bundleID)
					.font(Typography.detail.monospaced())
					.foregroundStyle(Theme.tertiaryLabel)
			}

			VStack(alignment: .leading, spacing: 10) {
				SettingsField(placeholder: "Username (optional)", text: $username)
				SettingsField(placeholder: "Password", text: $password, isSecure: true)
			}

			Text(
				"Stored encrypted on this Mac. Gaze types it only when you press the shortcut and it recognises your face."
			)
			.font(Typography.detail)
			.foregroundStyle(Theme.secondaryLabel)
			.fixedSize(horizontal: false, vertical: true)

			HStack {
				Spacer()
				Button("Cancel") { dismiss() }
					.gazeButton()
					.keyboardShortcut(.cancelAction)
				Button(draft.isExisting ? "Update" : "Save") {
					save(username, password)
					dismiss()
				}
				.gazeButton(.primary)
				.keyboardShortcut(.defaultAction)
				.disabled(password.isEmpty)
			}
		}
		.padding(22)
		.frame(width: 420)
		.onAppear { username = draft.username }
	}
}
