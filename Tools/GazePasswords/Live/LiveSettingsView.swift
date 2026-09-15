import SwiftUI

struct LiveSettingsView: View {
	@ObservedObject var store: LocalPasswordStore
	@ObservedObject var browser: PasswordBrowserService
	@AppStorage("passwords.preview.appearance") private var appearance = "system"
	@AppStorage("passwords.preview.animateBlob") private var animateBlob = true
	@AppStorage("passwords.downloadWebsiteIcons") private var websiteIcons = false
	@Environment(\.openWindow) private var openWindow
	@State private var selectedBrowser = SupportedPasswordBrowser.browserOS
	@State private var confirmBrowserSetup = false
	@State private var setupStatus: String?
	@State private var setupDetails: String?
	@State private var installedBrowsers: [BrowserSetup.DiscoveredBrowser] = []
	@State private var findingBrowsers = false
	@State private var hasSearchedBrowsers = false
	@State private var connectingBrowser = false
	@State private var openingExtensions = false
	@State private var conflictingRegistration: URL?

	var body: some View {
		VStack(spacing: 0) {
			PasswordsCompanion(size: 104).padding(.top, 16)
			Text("Gaze Passwords").font(Typography.paneTitle)
			Form {
				Section {
					HStack {
						Text("Theme")
						Spacer()
						GlassEffectContainer(spacing: 6) {
							HStack(spacing: 6) {
								ForEach(PasswordsTheme.allCases) { theme in
									Button(theme == .glass ? "Glass" : theme.title) { appearance = theme.rawValue }
										.gazeButton(appearance == theme.rawValue ? .primary : .standard)
										.accessibilityLabel(theme.title).accessibilityAddTraits(appearance == theme.rawValue ? .isSelected : [])
								}
							}.accessibilityElement(children: .contain).accessibilityLabel("Theme")
						}
					}
					Toggle("Animate Gaze companion", isOn: $animateBlob).toggleStyle(.switch)
					HStack {
						Toggle("Download website icons", isOn: $websiteIcons).toggleStyle(.switch)
						Button("Reload website icons", systemImage: "arrow.clockwise") { WebsiteIconCache.shared.clear() }
							.labelStyle(.iconOnly).font(.system(size: 12))
							.gazeButton().help("Reload website icons")
							.disabled(!websiteIcons || store.isLocked)
						InfoButton(title: "About website icons") {
							Text("When enabled, visible logins request /favicon.ico directly from their website. Google Accounts can also load its icon from www.google.com. Sites can see your IP address, but receive no vault credentials or cookies. Connections use a validated public IP with the website’s TLS identity; private addresses, proxies, nonstandard ports and redirects are skipped. Icons stay in memory and clear when the vault locks. Leave this off to avoid contacting websites.")
						}
					}.onChange(of: websiteIcons) { _, _ in WebsiteIconCache.shared.clear() }
				} header: {
					sectionHeader("Appearance", information: "System follows your Mac’s appearance. Glass uses the darker, more translucent Gaze style. Motion and glass respect Reduce Motion and Reduce Transparency.")
				}
				Section {
					HStack {
						VStack(alignment: .leading, spacing: 4) {
							Text("Import passwords")
							Text("Apple Passwords, Bitwarden or CSV").font(.caption).foregroundStyle(.secondary)
						}
						Spacer()
						Button("Get started") { openWindow(id: "import-passwords") }.gazeButton()
					}
				} header: {
					sectionHeader("Import & setup", information: "The import window includes the floating Apple Passwords export guide. Choose a CSV and review the result before saving. Existing passwords aren’t overwritten.")
				}
				Section {
					LabeledContent("Vault protection", value: "macOS authentication")
					LabeledContent("Automatic lock", value: "On leaving · 5 min maximum")
					Button("Lock Passwords") { browser.cancel(); store.lock() }.gazeButton().disabled(store.isLocked)
				} header: {
					sectionHeader("Security", information: "The vault locks when you leave the app, lock your Mac, put it to sleep, or reach five minutes after unlocking. Keychain access requires Touch ID or your Mac password. Gaze currently adds browser approval, not face-only vault unlock. Existing credentials retain their macOS protection.")
				}
				Section {
					HStack {
						Text("Browser")
						Spacer()
						if findingBrowsers || !hasSearchedBrowsers {
							ProgressView().controlSize(.small).accessibilityLabel("Finding browsers")
						} else if installedBrowsers.count <= 1 {
							Text(installedBrowsers.first?.id.rawValue ?? "No supported browser found").foregroundStyle(.secondary)
								.accessibilityLabel(installedBrowsers.first.map { "Detected browser, \($0.id.rawValue)" } ?? "No supported browser found")
						}
						Button("Find installed browsers", systemImage: "arrow.clockwise") { Task { await refreshBrowsers() } }
							.labelStyle(.iconOnly).font(.system(size: 12))
							.gazeButton().help("Find installed browsers")
							.disabled(findingBrowsers || connectingBrowser)
					}
					if hasSearchedBrowsers && !findingBrowsers && installedBrowsers.isEmpty {
						Text("Install or move a supported Chromium browser into Applications, then choose Find installed browsers.")
							.font(.caption).foregroundStyle(.secondary)
							.accessibilityLabel("No supported browser found. Install or move a supported Chromium browser into Applications, then choose Find installed browsers.")
					}
					if installedBrowsers.count > 1 {
						GlassEffectContainer(spacing: 8) {
							LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
								ForEach(installedBrowsers) { browser in
									Button { selectedBrowser = browser.id } label: {
										Text(browser.id.rawValue).frame(maxWidth: .infinity)
									}.gazeButton(selectedBrowser == browser.id ? .primary : .standard)
										.accessibilityAddTraits(selectedBrowser == browser.id ? .isSelected : [])
										.disabled(connectingBrowser || findingBrowsers)
								}
							}.accessibilityElement(children: .contain).accessibilityLabel("Browser")
						}
					}
					HStack {
						Button(connectingBrowser ? "Connecting…" : "Connect browser…") { confirmBrowserSetup = true }.gazeButton()
							.disabled(PasswordsBuild.isUIReview || selectedInstallation == nil || findingBrowsers || connectingBrowser)
						Button("Show extension") {
							if let folder = BrowserSetup.extensionFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
						}.gazeButton().disabled(BrowserSetup.extensionFolder == nil)
					}
					Button(openingExtensions ? "Opening…" : "Open browser extensions") {
						Task { await openExtensions() }
					}.gazeButton().disabled(PasswordsBuild.isUIReview || selectedInstallation == nil || openingExtensions)
					if let setupStatus {
						HStack {
							Text(setupStatus).font(.caption).foregroundStyle(.secondary)
							Spacer()
							if let setupDetails { InfoButton(title: "Browser setup details") { Text(setupDetails) } }
						}
					}
					if let conflictingRegistration {
						Button("Show existing helper file") {
							NSWorkspace.shared.activateFileViewerSelecting([conflictingRegistration])
						}.gazeButton()
					}
					LabeledContent("Browser service", value: browser.serviceSummary)
					LabeledContent("Helper contact", value: browser.lastBrowserContact == nil ? "Not checked this session" : "Received")
					if let contact = browser.lastBrowserContact {
						LabeledContent("Last browser request") { Text(contact, style: .time).monospacedDigit() }
					}
					HStack {
						LabeledContent("Gaze approval", value: browser.checkingGaze ? "Checking…" : browser.gazeSummary)
						InfoButton(title: "Gaze connection details") { Text(browser.gazeStatus) }
					}
					Button(browser.checkingGaze ? "Checking…" : "Check Gaze connection") { Task { await browser.checkGazeConnection() } }
						.gazeButton().disabled(browser.checkingGaze || PasswordsBuild.isUIReview)
					Text("Helper registration, extension loading and Gaze approval are separate steps. Use Check app connection inside the installed extension to verify the full browser path.")
						.font(.caption).foregroundStyle(.secondary)
				} header: {
					HStack {
						Text("Browser connection")
						Spacer()
						InfoButton(title: "About browser connection") {
							VStack(alignment: .leading, spacing: 12) {
								Text(browser.status)
								Text("Gaze finds supported browsers through macOS, Applications and your user Applications folder, then checks their signatures. Refresh this list after moving or installing a browser. Unsigned or unsupported apps do not appear.")
								Text("Connect browser registers this signed app’s helper for the selected browser only. It does not install an extension or change your default browser. Keep the app in this location afterward.")
								Text("Choose Show extension, then open your browser’s Extensions page, turn on Developer mode and choose Load unpacked. Select the BrowserExtension folder revealed in Finder and pin Gaze Passwords. Click its key on an HTTPS login page to fill or save a login. Saving always asks for confirmation in Passwords.")
								Text("A listening service or helper contact does not prove that an extension is installed. Check app connection from the extension itself to verify that path. Safari, background automatic saving and passkeys are not enabled yet.")
							}
						}
					}
				}
			}.formStyle(.grouped).scrollIndicators(.never).scrollContentBackground(.hidden)
		}.frame(width: 530, height: 720)
		.background { PasswordsWindowBackground() }.modifier(PasswordsAppearance())
		.task { await refreshBrowsers() }
		.onChange(of: selectedBrowser) { _, _ in setupStatus = nil; setupDetails = nil; conflictingRegistration = nil }
		.confirmationDialog("Connect Gaze Passwords to \(selectedBrowser.rawValue)?", isPresented: $confirmBrowserSetup) {
			Button("Connect browser") { Task { await connectBrowser() } }
			Button("Cancel", role: .cancel) {}
		} message: { Text("Adds this app’s native helper to your browser’s settings. No extension is installed and no credentials are accessed. Existing helper registrations are never replaced.") }
	}
	private var selectedInstallation: BrowserSetup.DiscoveredBrowser? {
		installedBrowsers.first { $0.id == selectedBrowser }
	}
	@MainActor private func openExtensions() async {
		guard !openingExtensions, let installation = selectedInstallation else { return }
		openingExtensions = true
		defer { openingExtensions = false }
		do {
			try await BrowserSetup.openExtensions(for: installation)
			setupStatus = "Load the extension in \(installation.id.rawValue)"
			setupDetails = "On the Extensions page, enable Developer mode and choose Load unpacked. Select the folder opened by Show extension. After loading, open Gaze Passwords from the browser toolbar and use its information button to Check app connection. Opening this page does not install anything."
		} catch {
			setupStatus = "Couldn’t open extensions"
			setupDetails = error.localizedDescription
		}
	}
	@MainActor private func refreshBrowsers() async {
		guard !findingBrowsers, !connectingBrowser else { return }
		findingBrowsers = true
		setupStatus = nil
		setupDetails = nil
		conflictingRegistration = nil
		defer { findingBrowsers = false }
		let candidates = BrowserSetup.discoveryCandidates()
		let found = await Task.detached(priority: .utility) { BrowserSetup.verifiedBrowsers(candidates) }.value
		guard !Task.isCancelled else { return }
		installedBrowsers = found
		hasSearchedBrowsers = true
		if selectedInstallation == nil, let first = found.first { selectedBrowser = first.id }
	}
	@MainActor private func connectBrowser() async {
		guard !connectingBrowser, let installation = selectedInstallation else { return }
		connectingBrowser = true
		conflictingRegistration = nil
		defer { connectingBrowser = false }
		do {
			try await Task.detached(priority: .userInitiated) { try BrowserSetup.register(installation.id, application: installation.application) }.value
			setupStatus = "Helper registered — load the extension next"
			setupDetails = "The helper is registered for \(installation.id.rawValue). Choose Show extension, then load that folder from your browser’s Extensions page. The helper alone does not install or enable the extension, and Gaze approval is checked separately with Check Gaze connection."
		} catch BrowserSetup.SetupError.existingRegistration {
			setupStatus = "This browser is connected to another copy"
			setupDetails = "Use Gaze Passwords at its registered location, or review the existing helper file before connecting this copy. Nothing was overwritten. Loading an extension alone does not change the helper path."
			conflictingRegistration = BrowserSetup.registrationURL(for: installation.id)
		} catch {
			setupStatus = "Couldn’t connect"
			setupDetails = error.localizedDescription + " Nothing was replaced: conflicting helper registrations are never overwritten."
		}
	}

	private func sectionHeader(_ title: String, information: String) -> some View {
		HStack {
			Text(title)
			Spacer()
			InfoButton(title: "About \(title.lowercased())") { Text(information) }
		}
	}
}
