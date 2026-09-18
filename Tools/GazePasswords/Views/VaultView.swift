import AppKit
import SwiftUI

struct VaultView: View {
	@ObservedObject var vault: DemoVault
	@Environment(\.scenePhase) private var scenePhase
	@State private var showingAbout = false
	@State private var showingSetup = false
	@FocusState private var searchFocused: Bool

	var body: some View {
		Group {
			if vault.isLocked {
				lockedView
			} else {
				HSplitView {
					loginList
						.frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)
					Group {
						if let login = vault.selectedLogin {
							LoginDetailView(vault: vault, login: login)
						} else {
							ContentUnavailableView("Choose a login", systemImage: "key.horizontal",
								description: Text("Your sample login details will appear here."))
						}
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
		.frame(minWidth: 920, minHeight: 620)
		.background { PasswordsWindowBackground() }
		.onAppear { searchFocused = false }
		.onExitCommand {
			if vault.hasSearch { vault.query = "" } else { searchFocused = false }
		}
		.focusedSceneValue(\.passwordsSearch, vault.isLocked ? nil : { searchFocused = true })
		.toolbar {
			ToolbarItem(placement: .principal) {
				PasswordsCollectionPicker(selection: $vault.collection, enabled: !vault.isLocked)
					.fixedSize()
			}
			ToolbarItem(placement: .primaryAction) {
				SettingsLink {
					Image(systemName: "gearshape")
				}
				.help("Settings")
				.accessibilityLabel("Settings")
			}
			ToolbarItem(placement: .primaryAction) {
				Button { vault.lock() } label: { Image(systemName: "lock") }
					.help("Hide demo vault")
					.accessibilityLabel("Hide demo vault")
					.disabled(vault.isLocked)
			}
		}
		.sheet(item: Binding(get: { vault.approval }, set: { if $0 == nil { vault.cancelApproval() } })) { request in
			ApprovalPreview(vault: vault, request: request)
		}
		.sheet(isPresented: $showingAbout) {
			VStack(alignment: .leading, spacing: 18) {
				PasswordsMark()
				Text("Gaze Passwords preview").font(Typography.paneTitle)
				Text("This is an interactive design preview with built-in sample logins. It cannot accept real passwords, connect to Bitwarden, access your camera, or fill websites.")
				Text("Bitwarden integration, website verification, vault-key protection, recovery, and face-approval security are not implemented.")
					.foregroundStyle(.secondary)
				Button("Done") { showingAbout = false }.gazeButton().keyboardShortcut(.defaultAction)
			}
			.padding(32)
			.frame(width: 460)
		}
		.sheet(isPresented: $showingSetup) {
			PasswordsSetupGuide().modifier(PasswordsAppearance())
		}
		.onChange(of: scenePhase) { _, phase in
			if phase != .active { vault.lock() }
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
			vault.lock()
		}
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
			vault.lock()
		}
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
			vault.lock()
		}
	}

	private var loginList: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 6) {
				SettingsField(placeholder: "Search passwords", text: $vault.query, isSecure: false)
					.focused($searchFocused)
					.accessibilityLabel("Search passwords")
					.help("Search passwords (⌘F)")
				Button { vault.query = ""; searchFocused = true } label: {
					Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
						.frame(width: 24, height: 28)
				}
				.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
				.opacity(vault.query.isEmpty ? 0 : 1)
				.disabled(vault.query.isEmpty).accessibilityHidden(vault.query.isEmpty)
			}
			.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 20)
			HStack {
				Text(vault.collection.rawValue).font(Typography.groupTitle).foregroundStyle(Theme.secondaryLabel)
				Spacer()
				Text("\(vault.visibleLogins.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
					.accessibilityLabel("\(vault.visibleLogins.count) \(vault.visibleLogins.count == 1 ? "sample login" : "sample logins")")
			}.padding(.horizontal, 20).padding(.bottom, 8)
			if vault.visibleLogins.isEmpty {
				ContentUnavailableView {
					Label(vault.emptyTitle, systemImage: vault.hasSearch ? "magnifyingglass" : vault.collection.symbol)
				} description: {
					Text(vault.emptyMessage)
				} actions: {
					if vault.collection != .all {
						Button(vault.hasSearch ? "Search all passwords" : "Show all passwords") { vault.collection = .all }.gazeButton()
					}
					if vault.hasSearch {
						Button("Clear search") { vault.query = ""; searchFocused = true }.gazeButton()
					}
				}
			} else {
				List(vault.visibleLogins, selection: $vault.selectedID) { login in
					HStack(spacing: 12) {
						LoginGlyph(login: login, size: 34)
						VStack(alignment: .leading, spacing: 5) {
							Text(login.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
							Text(login.username).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
						}
						Spacer(minLength: 0)
						if login.favorite {
							Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
								.accessibilityLabel("Favorite")
						}
					}
					.padding(.vertical, 6)
					.listRowSeparator(.hidden)
					.tag(login.id)
				}
				.listStyle(.inset)
				.scrollIndicators(.never)
				.scrollContentBackground(.hidden)
			}
			Spacer(minLength: 0)
			HStack {
					Text("Sample data only")
						.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
					Spacer()
					Button("Setup guide") { showingSetup = true }.gazeButton()
					Button { showingAbout = true } label: {
						Image(systemName: "info.circle")
					}
					.buttonStyle(.plain)
					.help("About this preview")
					.accessibilityLabel("About this preview")
			}
			.padding(16)
		}
	}

	private var lockedView: some View {
		VStack(spacing: 20) {
			PasswordsCompanion(size: 112)
			Text("Your demo vault is hidden").font(Typography.paneTitle)
			Text("Open it to explore the sample logins.\nNo real credentials are stored in this preview.")
				.multilineTextAlignment(.center).foregroundStyle(.secondary)
			Button("Open demo vault") { vault.openDemo() }
				.gazeButton(.primary, size: .large)
				.keyboardShortcut(.defaultAction)
			PreviewBadge().padding(.top, 10)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
