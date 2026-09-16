import AppKit
import SwiftUI

struct LiveVaultView: View {
	@ObservedObject var store: LocalPasswordStore
	@ObservedObject var browser: PasswordBrowserService
	@Environment(\.openWindow) private var openWindow
	@State private var editing: PasswordEntry?
	@State private var adding = false
	@State private var addingCode = false
	@State private var editingCode: PasswordEntry?
	@State private var deleting = false
	@State private var removal: VaultRemovalRequest?
	@State private var clipboardChange: Int?
	@State private var clipboardExpiry: Task<Void, Never>?
	@State private var information = false
	@State private var copiedField: String?
	@FocusState private var searchFocused: Bool
	private var commandsAvailable: Bool {
		!store.isLocked && !adding && !addingCode && editing == nil && !information && !deleting && store.errorMessage == nil
	}

	var body: some View {
		Group {
			if store.isLocked { locked }
			else {
				HSplitView {
					list.frame(minWidth: 260, idealWidth: 290, maxWidth: 340)
					ScrollView {
						VStack(alignment: .leading, spacing: 24) {
							if let request = browser.request { approval(request) }
							if let entry = store.selected { detail(entry).id(entry.id) }
							else {
								emptySelection
							}
						}.padding(32).frame(maxWidth: .infinity, alignment: .leading)
					}.scrollIndicators(.never)
				}
			}
		}
		.frame(minWidth: 920, minHeight: 620)
		.background { PasswordsWindowBackground() }
		.modifier(PasswordsAppearance())
		.focusedSceneValue(\.liveVaultActions, commandsAvailable ? LiveVaultActions(
			addingCode: store.collection == .codes, add: addEntry, search: { searchFocused = true }) : nil)
		.toolbar {
			ToolbarItem(placement: .principal) {
				PasswordSectionPicker(selection: $store.collection, enabled: !store.isLocked)
					.fixedSize()
			}
			ToolbarItemGroup(placement: .primaryAction) {
				SettingsLink { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
				Button { openWindow(id: "import-passwords") } label: { Image(systemName: "square.and.arrow.down") }.help("Import passwords").accessibilityLabel("Import passwords")
				Button { information = true } label: { Image(systemName: "info.circle") }.help("About browser filling").accessibilityLabel("About browser filling")
				Button(action: addEntry) { Image(systemName: "plus") }
					.help(store.collection == .codes ? "Add verification code" : "Add password")
					.accessibilityLabel(store.collection == .codes ? "Add verification code" : "Add password").disabled(store.isLocked)
				Button { lock() } label: { Image(systemName: "lock") }.help("Lock passwords").accessibilityLabel("Lock passwords").disabled(store.isLocked)
			}
		}
		.sheet(isPresented: $adding) {
			PasswordEntryEditor(store: store, original: nil).id(store.sessionID)
		}
		.sheet(item: $editing) { entry in PasswordEntryEditor(store: store, original: entry).id(store.sessionID) }
		.sheet(isPresented: $addingCode) {
			VerificationCodeEditor(store: store, original: editingCode).id(store.sessionID)
		}
		.sheet(isPresented: $information) {
			VStack(alignment: .leading, spacing: 18) {
				Image(systemName: "key.horizontal").font(.system(size: 36))
				Text("Passwords, with Gaze").font(Typography.paneTitle)
				Text("Your vault is protected by macOS authentication and stays on this Mac. It does not sync, and there is no recovery service.")
				Text("Browser filling requires the separate Gaze extension in a supported Chromium browser. Click its key on an HTTPS login page, unlock Passwords, choose the login and approve with Gaze. Safari is not supported yet.")
				Text("Gaze adds a face check; it does not replace Touch ID or your Mac password. Websites can read passwords filled into their own forms.").foregroundStyle(.secondary)
				Text(browser.status).font(.callout)
				Button("Done") { information = false }.gazeButton(.primary).keyboardShortcut(.defaultAction)
			}.padding(32).frame(width: 470)
		}
		.alert("Gaze Passwords", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
			Button("OK") { store.errorMessage = nil }
		} message: { Text(store.errorMessage ?? "") }
		.modifier(VaultRemovalConfirmation(request: $removal, isPresented: $deleting) { request in
			perform { try store.remove(request) }
		})
		.onChange(of: store.isLocked) { _, locked in if locked { adding = false; editing = nil; addingCode = false; editingCode = nil; deleting = false; removal = nil; clearClipboard(); browser.cancel(); WebsiteIconCache.shared.clear() } }
		.onChange(of: store.selectedID) { _, _ in store.revealedID = nil; copiedField = nil }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
			if !store.busy { lock() }
		}
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in lock() }
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in lock() }
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
			if (notification.object as? NSWindow)?.title == PasswordsBuild.title { lock() }
		}
		.onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))) { _ in lock() }
	}

	private var emptySelection: some View {
		VStack(spacing: 16) {
			if !store.query.isEmpty && store.entries.isEmpty {
				ContentUnavailableView.search(text: store.query)
				Button("Clear search") { store.query = "" }.gazeButton()
				if store.collection != .all {
					Button("Search all passwords") { store.collection = .all }.gazeButton()
				}
			} else if store.collection == .codes && store.entries.isEmpty {
				ContentUnavailableView("No verification codes yet", systemImage: "number", description: Text("Add a setup key to a saved login, or import your codes."))
				Button("Add a code") { editingCode = nil; addingCode = true }.gazeButton(.primary)
					.disabled(store.archive?.entries.isEmpty != false)
				Button("View passwords") { store.collection = .all }.gazeButton()
				Button("Import…") { openWindow(id: "import-passwords") }.gazeButton()
			} else if store.collection == .review && store.entries.isEmpty {
				ContentUnavailableView("Nothing flagged", systemImage: "checkmark.shield", description: Text("No reused or short passwords in this vault."))
				InfoButton(title: "About security review") { Text("This is an on-device check for exact password reuse and passwords shorter than 12 characters. It is not a breach search or a guarantee that your accounts are safe. No passwords or hashes are sent anywhere.") }
			} else if store.archive?.entries.isEmpty == true {
				ContentUnavailableView("Your passwords, in one place", systemImage: "key.horizontal", description: Text("Import your passwords or add your first login."))
				Button("Add a password") { adding = true }.gazeButton(.primary)
				Button("Import passwords…") { openWindow(id: "import-passwords") }.gazeButton()
			} else if store.collection == .favorites && store.entries.isEmpty {
				ContentUnavailableView("Your favorites go here", systemImage: "star", description: Text("Star a login to keep it close at hand."))
				Button("View passwords") { store.collection = .all }.gazeButton(.primary)
			} else if store.entries.isEmpty && (store.collection == .work || store.collection == .personal) {
				ContentUnavailableView("No \(store.collection.rawValue.lowercased()) logins yet", systemImage: store.collection == .work ? "briefcase" : "person",
					description: Text("Add a login here, or move one using Edit password."))
				Button("Add a password") { adding = true }.gazeButton(.primary)
				Button("View all passwords") { store.collection = .all }.gazeButton()
			} else {
				ContentUnavailableView(store.entries.isEmpty ? "No passwords here yet" : "Choose a login", systemImage: "key.horizontal")
			}
		}.frame(maxWidth: .infinity)
	}

	private var locked: some View {
		VStack(spacing: 20) {
			PasswordsCompanion(size: 104).padding(.bottom, 8)
			Text("Your passwords. Only for you.").font(Typography.paneTitle)
			Text("Unlock with Touch ID or your Mac password.").foregroundStyle(.secondary)
			if let request = browser.request {
				Text("Browser request for \(request.origin.value)").textSelection(.enabled)
				Text("Unlock to review this request, or cancel it.").font(.callout).foregroundStyle(.secondary)
				Button("Cancel request") { browser.cancel() }.gazeButton()
			}
			Button { Task { await store.unlock() } } label: {
				Label(store.busy ? "Waiting for macOS…" : "Unlock Passwords", systemImage: "touchid")
			}.gazeButton(.primary, size: .large).disabled(store.busy || PasswordsBuild.isUIReview)
			Text(PasswordsBuild.isUIReview ? "UI review · Vault and browser connections are disabled" : "Local vault · Locks when you leave the app")
				.font(.caption).foregroundStyle(.secondary)
		}.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var list: some View {
		VStack(spacing: 12) {
			HStack {
				Text(store.collection == .all ? "Passwords" : store.collection.rawValue).font(.headline)
				Spacer()
			}.padding([.top, .horizontal], 16)
			VaultSearchField(placeholder: store.collection == .codes ? "Search codes" : "Search passwords", text: $store.query)
				.focused($searchFocused).padding(.horizontal, 16)
				.onKeyPress { press in
					guard searchFocused, press.modifiers.isEmpty else { return .ignored }
					if press.key == .upArrow {
						store.moveSelection(by: -1)
						return .handled
					} else if press.key == .downArrow {
						store.moveSelection(by: 1)
						return .handled
					}
					return .ignored
				}
				.onSubmit {
					if store.selected == nil { store.selectedID = store.entries.first?.id }
					searchFocused = false
				}
			List(selection: $store.selectedID) {
				ForEach(store.entries) { entry in
					HStack(spacing: store.collection == .codes ? 8 : 12) {
						WebsiteIcon(origin: entry.origin, size: store.collection == .codes ? 28 : 34)
						VStack(alignment: .leading, spacing: 4) {
							Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
							Text(entry.username.isEmpty ? entry.origin.value : entry.username).font(.caption).foregroundStyle(.secondary).lineLimit(1)
						}
						if store.collection == .codes, let code = entry.verificationCode {
							Spacer(minLength: 4)
							VerificationCodeDisplay(code: code, compact: true)
						}
					}.padding(.vertical, 6).tag(entry.id)
				}
			}.scrollContentBackground(.hidden).scrollIndicators(.never)
			HStack {
				Text("\(store.entries.count) \(store.collection == .codes ? (store.entries.count == 1 ? "verification code" : "verification codes") : store.entries.count == 1 ? "login" : "logins")").font(.caption).foregroundStyle(.secondary)
				Spacer()
			}.padding([.horizontal, .bottom], 16)
		}
	}

	private func detail(_ entry: PasswordEntry) -> some View {
		VStack(alignment: .leading, spacing: 24) {
			HStack(spacing: 16) {
				WebsiteIcon(origin: entry.origin, size: 56)
				VStack(alignment: .leading, spacing: 5) {
					Text(entry.title).font(Typography.paneTitle)
					Text(entry.origin.value).foregroundStyle(.secondary).textSelection(.enabled)
				}
				Spacer()
				Button { perform { try store.toggleFavorite(entry) } } label: { Image(systemName: entry.favorite ? "star.fill" : "star") }
					.gazeButton().help(entry.favorite ? "Remove from favorites" : "Add to favorites")
					.accessibilityLabel(entry.favorite ? "Remove from favorites" : "Add to favorites")
			}
			if store.collection == .codes, let code = entry.verificationCode { codeCard(code) }
			VStack(spacing: 0) {
				HStack {
					Text("Username")
					Spacer()
					Text(entry.username.isEmpty ? "None" : entry.username).lineLimit(2).textSelection(.enabled)
					Button { copy(entry.username, field: "username") } label: { Image(systemName: copiedField == "username" ? "checkmark" : "doc.on.doc") }
						.gazeButton().help("Copy username").accessibilityLabel("Copy username").disabled(entry.username.isEmpty)
				}.padding(20)
				if store.collection != .codes {
					Divider().padding(.horizontal, 20)
					HStack {
						Text("Password")
						Spacer()
						Text(store.revealedID == entry.id ? entry.password : "••••••••••••").font(.body.monospaced()).lineLimit(2)
						Button {
							guard allowVaultInteraction() else { return }
							store.revealedID = store.revealedID == entry.id ? nil : entry.id
						} label: { Image(systemName: store.revealedID == entry.id ? "eye.slash" : "eye") }
							.gazeButton().help(store.revealedID == entry.id ? "Hide password" : "Show password")
							.accessibilityLabel(store.revealedID == entry.id ? "Hide password" : "Show password")
						Button { copy(entry.password, field: "password") } label: { Image(systemName: copiedField == "password" ? "checkmark" : "doc.on.doc") }.gazeButton().help("Copy for 30 seconds").accessibilityLabel("Copy password")
					}.padding(20)
				}
			}.glassSurface()
			if store.collection != .codes, let code = entry.verificationCode { codeCard(code) }
			let review = store.review
			if store.collection != .codes && review.flaggedIDs.contains(entry.id) {
				HStack {
					Label(review.reusedIDs.contains(entry.id) ? "Password reused" : "Short password", systemImage: "exclamationmark.shield").font(.callout)
					Spacer()
					InfoButton(title: "Review this password") {
						Text("\(review.reusedIDs.contains(entry.id) ? "Another login in this vault uses the same password. " : "")\(review.shortIDs.contains(entry.id) ? "This password is shorter than 12 characters. " : "")Change it on the website first, then update the saved login. This check runs only on this Mac; it does not check for breaches.")
					}
				}.padding(16).glassSurface()
			}
			HStack {
				if store.collection != .codes {
					Button("Edit password") { if allowVaultInteraction() { editing = entry } }.gazeButton()
				}
				Button(entry.verificationCode == nil ? "Add code" : "Edit code") {
					guard allowVaultInteraction() else { return }
					editingCode = entry; addingCode = true
				}.gazeButton()
				if store.collection == .codes {
					Button("View password") { store.collection = .all; store.selectedID = entry.id }.gazeButton()
				} else {
					Button("Open website") { if let url = URL(string: entry.origin.value) { NSWorkspace.shared.open(url) } }.gazeButton()
				}
				Spacer()
				if store.collection != .codes {
					Button("Delete", role: .destructive) {
						perform { removal = try store.prepareRemoval(entry.id); deleting = true }
					}.gazeButton()
				}
			}
		}
	}

	private func codeCard(_ code: VerificationCode) -> some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Verification code").font(.callout).foregroundStyle(.secondary)
				VerificationCodeDisplay(code: code)
			}
			Spacer()
			Button {
				let now = Date()
				if let value = try? code.value(at: now) { copy(value, seconds: min(30, code.remaining(at: now)), field: "code") }
			} label: { Label(copiedField == "code" ? "Copied" : "Copy code", systemImage: copiedField == "code" ? "checkmark" : "doc.on.doc") }
			.gazeButton().help("Copy verification code until it expires")
		}.padding(20).glassSurface()
	}

	private func approval(_ request: BrowserMessage) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Label(request.operation == "save" ? "Save from browser" : "Fill this website", systemImage: request.operation == "save" ? "square.and.arrow.down" : "key.horizontal").font(.headline)
				Spacer()
				InfoButton(title: "About browser approval") {
					Text(request.operation == "save" ? "Confirm the website and username before saving. Updating replaces only the matching password and preserves its verification code. A page capture does not prove that sign-in succeeded." : "Gaze verifies your face after you choose a login. Only this exact website receives the password. Gaze does not submit the sign-in form.")
				}
			}
			Text(request.origin.value).font(.body.monospaced()).textSelection(.enabled)
			if request.operation == "save" {
				if let username = browser.saveUsername {
					LabeledContent("Username", value: username.isEmpty ? "None" : username)
					Button(browser.saveAction) { browser.approveSave() }.gazeButton(.primary)
				} else { ProgressView("Preparing…") }
			} else {
				let matches = (store.archive?.entries ?? []).filter { $0.origin == request.origin }
				BrowserLoginChoices(entries: matches, verifying: browser.verifying, choose: browser.approve).id(request.requestID)
			}
			if browser.verifying { ProgressView("Follow Gaze’s movements…") }
			Button("Cancel") { browser.cancel() }.gazeButton()
		}.padding(24).glassSurface()
	}

	private func perform(_ action: () throws -> Void) {
		do { try action() } catch { store.errorMessage = error.localizedDescription }
	}
	private func addEntry() {
		guard commandsAvailable else { return }
		if store.collection == .codes { editingCode = nil; addingCode = true }
		else { adding = true }
	}
	private func lock() { browser.cancel(); store.lock(); clearClipboard() }
	private func allowVaultInteraction() -> Bool {
		guard !store.isLocked, NSApp.isActive else { lock(); return false }
		return true
	}
	private func copy(_ password: String, seconds: Int = 30, field: String) {
		guard allowVaultInteraction() else { return }
		clearClipboard()
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(password, forType: .string)
		pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
		pasteboard.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
		let copiedChange = pasteboard.changeCount
		clipboardChange = copiedChange
		copiedField = field
		clipboardExpiry = Task {
			do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
			guard !Task.isCancelled, clipboardChange == copiedChange else { return }
			clearClipboard()
		}
	}
	private func clearClipboard() {
		clipboardExpiry?.cancel()
		clipboardExpiry = nil
		if let clipboardChange, NSPasteboard.general.changeCount == clipboardChange { NSPasteboard.general.clearContents() }
		clipboardChange = nil
		copiedField = nil
	}
}

struct PasswordEntryEditor: View {
	@ObservedObject var store: LocalPasswordStore
	let original: PasswordEntry?
	@Environment(\.dismiss) private var dismiss
	@State private var title = ""
	@State private var website = ""
	@State private var username = ""
	@State private var password = ""
	@State private var error: String?
	@State private var codeInput = ""
	@State private var confirmGenerate = false
	@State private var collection = "Personal"
	@State private var showsCode = false
	private var matchingOrigin: BrowserOrigin? { try? PasswordWebsiteInput.origin(from: website) }

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			HStack(spacing: 12) {
				PasswordsCompanion(size: 44)
				Text(original == nil ? "Add a password" : "Edit password").font(Typography.paneTitle)
			}
			field("Name", placeholder: "e.g. Personal email", text: $title)
			field("Website", placeholder: "https://example.com/login", text: $website)
			field("Username", placeholder: "Email or username", text: $username)
			HStack {
				Text("Collection").font(.callout).foregroundStyle(.secondary)
				Spacer()
				GlassEffectContainer(spacing: 6) {
					HStack(spacing: 6) {
						ForEach(["Personal", "Work"], id: \.self) { option in
							Button(option) { collection = option }.gazeButton(collection == option ? .primary : .standard)
								.accessibilityAddTraits(collection == option ? .isSelected : [])
						}
					}
				}.accessibilityElement(children: .contain).accessibilityLabel("Collection")
			}
			HStack {
				Text("Password").font(.callout).foregroundStyle(.secondary)
				Spacer()
				Button("Generate") {
					if password.isEmpty { generatePassword() } else { confirmGenerate = true }
				}.gazeButton().disabled(store.isLocked)
				InfoButton(title: "About generated passwords") {
					Text("Creates a random 24-character password on this Mac. Nothing is copied or saved until you choose to save this entry. Changing a saved password here does not change it on the website.")
				}
			}
			SettingsField(placeholder: "Password", text: $password, isSecure: true)
				.accessibilityLabel("Password")
			if original?.verificationCode != nil {
				HStack {
					Label("Verification code saved", systemImage: "number.circle")
					Spacer()
					InfoButton(title: "Manage verification code") {
						Text("Your setup key is kept when you edit this password. Use Edit code on the login’s detail page to replace or remove it.")
					}
				}
			} else if original == nil {
				DisclosureGroup("Verification code", isExpanded: $showsCode) {
					VStack(alignment: .leading, spacing: 8) {
						SettingsField(placeholder: "Optional · setup key or otpauth://totp URL", text: $codeInput, isSecure: true)
							.accessibilityLabel("Verification code setup key")
					}.padding(.top, 10)
				}
			}
			HStack {
				if let matchingOrigin {
					Text("Matches only \(matchingOrigin.value)").font(.caption.weight(.medium)).textSelection(.enabled)
				} else { Text("HTTPS login address required").font(.caption).foregroundStyle(.secondary) }
				Spacer()
				InfoButton(title: "About website matching") {
					Text("Paste the full HTTPS login address. Only its site is saved; paths, queries and fragments are omitted. Subdomains and non-default ports are separate.")
				}
			}
			if let error { Text(error).foregroundStyle(.red) }
			HStack {
				Button("Cancel") { password = ""; dismiss() }.gazeButton().keyboardShortcut(.cancelAction)
				Spacer()
				Button("Save password") {
					do {
						var entry = try PasswordEntry(title: title, origin: PasswordWebsiteInput.origin(from: website), username: username, password: password)
						if let original { entry.id = original.id; entry.favorite = original.favorite }
						else { entry.favorite = store.collection == .favorites }
						entry.collection = collection
						if let original { entry.verificationCode = original.verificationCode }
						else if !codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { entry.verificationCode = try VerificationCode(input: codeInput) }
						try store.save(entry, replacing: original)
						store.showEntry(entry.id)
						password = ""
						dismiss()
					} catch { self.error = error.localizedDescription }
				}.gazeButton(.primary).keyboardShortcut(.defaultAction)
					.disabled(store.isLocked || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matchingOrigin == nil || password.isEmpty)
			}
		}.padding(32).frame(width: 460)
		.confirmationDialog("Replace the password in this editor?", isPresented: $confirmGenerate) {
			Button("Generate a new password", role: .destructive) { generatePassword() }
			Button("Cancel", role: .cancel) {}
		} message: { Text("The saved entry stays unchanged until you choose Save password. This does not change your password on the website.") }
		.onAppear {
			if let original { title = original.title; website = original.origin.value; username = original.username; password = original.password; collection = original.collection }
			else { collection = store.collection == .work ? "Work" : "Personal" }
		}
		.onChange(of: store.isLocked) { _, locked in if locked { password = ""; dismiss() } }
		.onDisappear { password = ""; codeInput = "" }
		.onChange(of: website) { _, _ in error = nil }
	}
	private func generatePassword() {
		guard !store.isLocked else { return }
		do { password = try PasswordGenerator.generate(); error = nil }
		catch { self.error = error.localizedDescription }
	}
	private func field(_ name: String, placeholder: String, text: Binding<String>) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(name).font(.callout).foregroundStyle(.secondary)
			SettingsField(placeholder: placeholder, text: text, isSecure: false).accessibilityLabel(name)
		}
	}
}
