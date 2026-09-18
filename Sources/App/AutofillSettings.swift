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
	@State private var operationError: String?
	/// Detected once when the pane appears, not on every redraw — it reads plists off
	/// disk, and a body can run many times a second.
	@State private var suggestions: [PasswordApps.Suggestion] = []

	var body: some View {
		if let error = savedApps.storageError ?? operationError {
			SettingsSection(title: "Saved-password error") {
				Text(error)
					.foregroundStyle(Theme.warning)
					.fixedSize(horizontal: false, vertical: true)
				if savedApps.storageError != nil {
					Button("Retry Storage Recovery") {
						operationError = nil
						savedApps.reload()
					}
				}
			}
		}
		if !suggestions.isEmpty {
			SettingsSection(title: "Password apps on this Mac", info: suggestionsFooter) {
				ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, app in
					if index > 0 { RowDivider() }
					suggestionRow(app)
				}
			}
		}

		SettingsSection(title: "Saved apps", footer: "Stored on this Mac. Browser filling isn't supported.", info: footer) {
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

		SettingsSection(title: "How it works", info: shortcutFooter) {
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
		.background {
			SavedAppEditorSheet(draft: $draft) { draft, username, password in
				try await savedApps.add(
					bundleID: draft.bundleID, name: draft.name,
					username: username, password: password, selection: draft.selection,
					replacing: draft.existing)
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
		SettingsSection(title: "Last attempt", info: diagnosticsFooter) {
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
		"Automatic filling and the shortcut require a verified face, fresh Touch ID or macOS password approval, and a secure writable field in the exact saved app. Five attempts require owner approval to reset. Browser filling remains blocked."
	}

	// MARK: - Suggestions

	private func suggestionRow(_ app: PasswordApps.Suggestion) -> some View {
		SettingRow(
			title: app.name,
			detail: "Found on this Mac",
			portrait: NSWorkspace.shared.icon(forFile: app.url.path)
		) {
			Button("Set Up") {
				guard let selection = AppIdentity.selection(forAppAt: app.url) else {
					operationError = "The selected app's signing identity could not be verified. Nothing was saved."
					return
				}
				draft = SavedAppDraft(
					bundleID: app.bundleID, name: app.name, username: "",
					selection: selection, applicationURL: selection.url)
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
			portrait: displayIcon(for: savedApp)
		) {
			HStack(spacing: 8) {
				Button("Change Password…") {
					draft = SavedAppDraft(
						bundleID: savedApp.bundleID, name: savedApp.name,
						username: savedApp.username, existing: savedApp,
						applicationURL: savedApp.applicationURL)
				}
				.gazeButton(.standard, size: .small)

				Button {
					do {
						try savedApps.remove(savedApp.id)
						operationError = nil
					} catch {
						operationError = error.localizedDescription
					}
				} label: {
					Image(systemName: "minus.circle.fill")
						.foregroundStyle(Theme.danger)
				}
				.buttonStyle(.plain)
				.help("Remove \(savedApp.name)")
			}
		}
	}

	private func displayIcon(for savedApp: SavedApp) -> NSImage? {
		savedApps.icon(for: savedApp)
			?? savedApps.icon(forBundleID: savedApp.bundleID)
			?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
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
		guard let selection = AppIdentity.selection(forAppAt: url) else {
			operationError = "The selected app's signing identity could not be verified. Nothing was saved."
			return
		}
		draft = SavedAppDraft(
			bundleID: bundleID, name: name,
			username: existing?.username ?? "", existing: existing,
			selection: selection, applicationURL: selection.url)
	}

	/// Read fresh each time the pane draws, rather than stored. Registration happens once
	/// at launch and cannot change while this window is open, so there is nothing to
	/// observe — and a cached copy would be the stale thing telling you it is fine.
	private var shortcutIsHeld: Bool { AppServices.shared.isAutofillShortcutRegistered }

	private var footer: String {
		savedApps.apps.isEmpty
			? "Gaze can fill secure password fields in verified saved apps after face recognition. Automatic filling is optional; Gaze does not press Return."
			: "Passwords are stored encrypted on this Mac. A row is removed only after password deletion and the saved list update are confirmed. Failed changes block filling until storage recovery succeeds."
	}

	private var shortcutFooter: String {
		"Automatic filling and the shortcut require a focused, secure, writable password field in a verified saved app. Neither fills plain text fields or presses Return. Browser filling requires a future website-identity integration."
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
	var existing: SavedApp? = nil
	var isExisting: Bool { existing != nil }
	var selection: AppIdentity.Selection? = nil
	var applicationURL: URL? = nil
}

private struct SavedAppEditor: View {

	let draft: SavedAppDraft
	let save: (String, String) async throws -> Void
	let dismiss: () -> Void

	@State private var username: String = ""
	@State private var password: String = ""
	@State private var appIcon: NSImage?
	@State private var saveError: String?
	@State private var saveTask: Task<Void, Never>?
	@State private var isSaving = false
	@FocusState private var focusedField: Field?

	private enum Field: Hashable {
		case username, password
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			HStack(spacing: 12) {
				Button {
					saveTask?.cancel()
					dismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 13, weight: .semibold))
						.frame(width: 20, height: 20)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.controlSize(.large)
				.keyboardShortcut(.cancelAction)
				.accessibilityLabel("Cancel")
				.help("Cancel")

				Group {
					if let appIcon {
						Image(nsImage: appIcon)
							.resizable()
							.scaledToFit()
					} else {
						Image(systemName: "key.fill")
							.font(.system(size: 28))
							.foregroundStyle(.secondary)
					}
				}
				.frame(width: 32, height: 32)
				.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 4) {
					Text(draft.isExisting ? "Edit Password" : "Add Password")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
					Text(draft.name)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
						.help(draft.bundleID)
				}
				Spacer(minLength: 0)
				Button(action: submit) {
					Image(systemName: "checkmark")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.blue)
						.frame(width: 20, height: 20)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.controlSize(.large)
				.keyboardShortcut(.defaultAction)
				.accessibilityLabel(draft.isExisting ? "Save Changes" : "Add Password")
				.help(password.isEmpty ? "Enter a password to save" : "Save password")
				.disabled(password.isEmpty || isSaving)
			}

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
				GridRow {
					Text("Username:")
						.gridColumnAlignment(.trailing)
					TextField("Optional", text: $username)
						.textContentType(.username)
						.autocorrectionDisabled()
						.accessibilityLabel("Username")
						.accessibilityHint("Optional")
						.focused($focusedField, equals: .username)
						.onSubmit { focusedField = .password }
				}
				GridRow {
					Text(draft.isExisting ? "New password:" : "Password:")
					SecureField("Required", text: $password)
						.accessibilityLabel(draft.isExisting ? "New password" : "Password")
						.focused($focusedField, equals: .password)
						.onSubmit { submit() }
				}
			}
			.textFieldStyle(.roundedBorder)
			.controlSize(.regular)
			.disabled(isSaving)

			if let saveError {
				Text(saveError)
					.font(.footnote)
					.foregroundStyle(Theme.warning)
					.fixedSize(horizontal: false, vertical: true)
			}

			if draft.isExisting && draft.selection != nil {
				Text("If the selected app has a different signing identity, saving requires fresh Touch ID or account-password approval. Cancel if you did not intend to trust a different app.")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			if let url = draft.applicationURL {
				Text("Selected application: \(url.path)")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Text("Gaze saves this password for autofill; it doesn't change the password in \(draft.name). Stored encrypted on this Mac and filled after face recognition.")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

		}
		.padding(24)
		.frame(width: 460)
		.onAppear {
			username = draft.username
			if let url = draft.applicationURL {
				appIcon = NSWorkspace.shared.icon(forFile: url.path)
			}
			focusedField = draft.isExisting ? .password : .username
		}
		.onDisappear {
			saveTask?.cancel()
			password = ""
		}
	}

	private func submit() {
		guard !password.isEmpty, !isSaving else { return }
		isSaving = true
		saveError = nil
		saveTask = Task { @MainActor in
			defer { isSaving = false }
			do {
				try await save(username, password)
				password = ""
				dismiss()
			} catch {
				saveError = error.localizedDescription
			}
		}
	}
}

private struct SavedAppEditorSheet: NSViewRepresentable {
	@Binding var draft: SavedAppDraft?
	let save: (SavedAppDraft, String, String) async throws -> Void

	func makeCoordinator() -> Coordinator { Coordinator(draft: $draft, save: save) }

	func makeNSView(context: Context) -> AnchorView {
		let view = AnchorView()
		view.onWindowChange = { [weak coordinator = context.coordinator] window in
			coordinator?.schedulePresentation(in: window)
		}
		return view
	}

	func updateNSView(_ view: AnchorView, context: Context) {
		context.coordinator.draft = $draft
		context.coordinator.requestedDraft = draft
		context.coordinator.save = save
		context.coordinator.schedulePresentation(in: view.window)
	}

	static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
		view.onWindowChange = nil
		coordinator.pendingPresentation?.cancel()
		coordinator.close()
	}

	final class AnchorView: NSView {
		var onWindowChange: ((NSWindow?) -> Void)?
		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			onWindowChange?(window)
		}
	}

	final class EditorPanel: NSPanel {
		var onCancel: (() -> Void)?
		override var canBecomeKey: Bool { true }
		override var canBecomeMain: Bool { false }
		override func cancelOperation(_ sender: Any?) { onCancel?() }
	}

	@MainActor
	final class Coordinator {
		var draft: Binding<SavedAppDraft?>
		var requestedDraft: SavedAppDraft?
		var save: (SavedAppDraft, String, String) async throws -> Void
		var pendingPresentation: Task<Void, Never>?
		private var panel: EditorPanel?

		init(draft: Binding<SavedAppDraft?>, save: @escaping (SavedAppDraft, String, String) async throws -> Void) {
			self.draft = draft
			self.requestedDraft = draft.wrappedValue
			self.save = save
		}

		func schedulePresentation(in parent: NSWindow?) {
			pendingPresentation?.cancel()
			pendingPresentation = Task { @MainActor [weak self, weak parent] in
				await Task.yield()
				guard !Task.isCancelled, let self else { return }
				guard let currentDraft = self.requestedDraft else {
					self.close()
					return
				}
				guard let parent, self.panel == nil, parent.attachedSheet == nil else { return }
				self.present(currentDraft, in: parent)
			}
		}

		private func present(_ currentDraft: SavedAppDraft, in parent: NSWindow) {
			let editor = SavedAppEditor(
				draft: currentDraft,
				save: { [weak self] username, password in
					guard let self else { throw CancellationError() }
					try await self.save(currentDraft, username, password)
				},
				dismiss: { [weak self] in self?.close() })
			let host = NSHostingView(rootView: editor)
			let frame = NSRect(origin: .zero, size: host.fittingSize)
			let panel = EditorPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
			panel.title = currentDraft.isExisting ? "Edit Password" : "Add Password"
			panel.isOpaque = false
			panel.backgroundColor = .clear
			panel.hasShadow = true
			panel.isReleasedWhenClosed = false
			panel.appearance = parent.effectiveAppearance
			panel.onCancel = { [weak self] in self?.close() }
			let glass = NSGlassEffectView(frame: frame)
			glass.style = .regular
			glass.cornerRadius = 24
			glass.contentView = host
			panel.contentView = glass
			self.panel = panel
			parent.beginSheet(panel) { [weak self, weak panel] _ in
				panel?.orderOut(nil)
				guard let self, self.panel === panel else { return }
				self.panel = nil
				if self.draft.wrappedValue?.id == currentDraft.id {
					self.draft.wrappedValue = nil
				}
			}
		}

		func close() {
			guard let panel else { return }
			panel.sheetParent?.endSheet(panel)
			panel.orderOut(nil)
		}
	}
}
