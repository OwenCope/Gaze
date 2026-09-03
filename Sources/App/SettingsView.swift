import AppKit
import SwiftUI

/// The four places in Gaze's settings window.
enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
	case general
	case face
	case credits
	case about

	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: return "General"
		case .face: return "Gaze"
		case .credits: return "Credits"
		case .about: return "About"
		}
	}

	var symbol: String {
		switch self {
		case .general: return "slider.horizontal.3"
		case .face: return "faceid"
		case .credits: return "sparkles"
		case .about: return "info.circle"
		}
	}

	var tint: Color {
		self == .face ? Theme.faceID : Theme.secondaryLabel
	}

	var summary: String {
		switch self {
		case .general:
			return "Lock screen appearance, security, and this Mac"
		case .face:
			return "Your face, recognition, and unlock behavior"
		case .credits:
			return "The work and people behind Gaze"
		case .about:
			return "What Gaze does, and what it does not claim"
		}
	}
}

struct SettingsView: View {

	let store: FaceEnrollmentStore
	let lockout: LockoutManager

	@State private var pane: SettingsPane = .face
	@State private var settings = Preferences.shared
	@State private var updates = UpdateChecker.shared
	@State private var passwordEntry = ""
	@State private var passwordError: String?
	@State private var lockoutPassword = ""

	@Environment(\.openWindow) private var openWindow

	var body: some View {
		ScrollView {
			SettingsPage(
				pane: pane,
				store: store,
				lockout: lockout,
				settings: settings,
				updates: updates,
				passwordEntry: $passwordEntry,
				passwordError: $passwordError,
				lockoutPassword: $lockoutPassword,
				onSetup: openEnrollment,
				onTest: openRecognitionTest,
				onStorePassword: storePassword,
				onClearLockout: clearLockout)
			.frame(maxWidth: 760, alignment: .leading)
			.padding(.horizontal, 42)
			.padding(.top, 30)
			.padding(.bottom, 38)
		}
		.scrollIndicators(.automatic)
		.frame(
			minWidth: 760, idealWidth: 840, maxWidth: .infinity,
			minHeight: 560, idealHeight: 640, maxHeight: .infinity)
		.background(WindowGlass(keepsTitle: true, extraTranslucent: settings.appTheme == .glass))
		.preferredColorScheme(settings.appTheme.colorScheme)
		// The unified compact toolbar is the native draggable title bar. Keeping the
		// navigation in its principal slot leaves the traffic lights and drag region to AppKit.
		.toolbar {
			ToolbarSpacer(.flexible, placement: .navigation)
			ToolbarItem(placement: .principal) {
				SettingsNavigationBar(selection: $pane)
			}
			ToolbarSpacer(.flexible, placement: .primaryAction)
		}
		.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
		.toolbarColorScheme(settings.appTheme.colorScheme, for: .windowToolbar)
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	private func openEnrollment() {
		AppActivation.bringToFront()
		openWindow(id: "enrollment")
	}

	private func openRecognitionTest() {
		AppActivation.bringToFront()
		openWindow(id: "test")
	}

	private func storePassword() {
		Task {
			guard await BiometricGate.authorize(.storePassword) else { return }
			do {
				if try PasswordVault.store(passwordEntry) {
					passwordEntry = ""
					passwordError = nil
				} else {
					passwordError = "That password didn't match your account."
				}
			} catch {
				passwordError = error.localizedDescription
			}
		}
	}

	private func clearLockout() {
		if PasswordVault.verify(lockoutPassword) {
			lockout.clearAfterPasswordAuth()
		}
		lockoutPassword = ""
	}
}

// MARK: - Native toolbar navigation

private struct SettingsNavigationBar: View {

	@Binding var selection: SettingsPane

	var body: some View {
		HStack(spacing: 2) {
			ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element) { index, pane in
				SettingsNavigationButton(
					pane: pane,
					isSelected: selection == pane,
					select: { selection = pane })
				.keyboardShortcut(
					KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
			}
		}
		.padding(3)
		.glassEffect(.regular.interactive(), in: Capsule())
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Gaze settings navigation")
	}
}

private struct SettingsNavigationButton: View {

	let pane: SettingsPane
	let isSelected: Bool
	let select: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: select) {
			Text(pane.title)
				.font(.system(.caption, weight: isSelected ? .semibold : .medium))
				.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
				.frame(minWidth: 62)
				.padding(.horizontal, 7)
				.padding(.vertical, 5)
				.background {
					Capsule()
						.fill(
							isSelected
								? Theme.selection
								: (isHovering ? Theme.hoverFill : .clear))
				}
		}
		.buttonStyle(.plain)
		.contentShape(Capsule())
		.onHover { isHovering = $0 }
		.accessibilityLabel(pane.title)
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
		.animation(.smooth(duration: 0.14), value: isSelected)
	}
}

// MARK: - Page routing

private struct SettingsPage: View {

	let pane: SettingsPane
	let store: FaceEnrollmentStore
	let lockout: LockoutManager
	@Bindable var settings: Preferences
	let updates: UpdateChecker

	@Binding var passwordEntry: String
	@Binding var passwordError: String?
	@Binding var lockoutPassword: String

	let onSetup: () -> Void
	let onTest: () -> Void
	let onStorePassword: () -> Void
	let onClearLockout: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 28) {
			SettingsPageHeader(
				pane: pane,
				isEnrolled: store.isEnrolled,
				isLockedOut: lockout.isLockedOut)

			switch pane {
			case .general:
				GeneralSettingsPage(settings: settings, updates: updates)
			case .face:
				GazeSettingsPage(
					store: store,
					lockout: lockout,
					settings: settings,
					passwordEntry: $passwordEntry,
					passwordError: passwordError,
					lockoutPassword: $lockoutPassword,
					onSetup: onSetup,
					onTest: onTest,
					onStorePassword: onStorePassword,
					onClearLockout: onClearLockout)
			case .credits:
				CreditsSettingsPage()
			case .about:
				AboutSettingsPage(store: store, updates: updates)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct SettingsPageHeader: View {

	let pane: SettingsPane
	let isEnrolled: Bool
	let isLockedOut: Bool

	var body: some View {
		HStack(alignment: .center, spacing: 18) {
			VStack(alignment: .leading, spacing: 5) {
				Text(pane.title)
					.font(.system(.largeTitle, weight: .bold))
					.foregroundStyle(Theme.label)
				Text(pane.summary)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}

			Spacer(minLength: 12)

			if pane == .face {
				ProtectionState(isEnrolled: isEnrolled, isLockedOut: isLockedOut)
			}
		}
	}
}

private struct ProtectionState: View {

	let isEnrolled: Bool
	let isLockedOut: Bool

	private var title: String {
		if isLockedOut { return "Paused" }
		return isEnrolled ? "Ready" : "Not set up"
	}

	private var tint: Color {
		if isLockedOut { return Theme.danger }
		return isEnrolled ? Theme.faceID : Theme.warning
	}

	private var symbol: String {
		if isLockedOut { return "lock.fill" }
		return isEnrolled ? "checkmark" : "exclamationmark"
	}

	var body: some View {
		Label(title, systemImage: symbol)
			.font(.system(.callout, weight: .semibold))
			.foregroundStyle(tint)
			.accessibilityElement(children: .combine)
	}
}

// MARK: - Gaze

private struct GazeSettingsPage: View {

	let store: FaceEnrollmentStore
	let lockout: LockoutManager
	@Bindable var settings: Preferences
	@Binding var passwordEntry: String
	let passwordError: String?
	@Binding var lockoutPassword: String
	let onSetup: () -> Void
	let onTest: () -> Void
	let onStorePassword: () -> Void
	let onClearLockout: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			if lockout.isLockedOut {
				LockoutRecoverySection(
					password: $lockoutPassword,
					onUnlock: onClearLockout)
			}

			GazeStatusSection(
				isEnrolled: store.isEnrolled,
				isCorrupted: store.isCorrupted,
				isLockedOut: lockout.isLockedOut,
				detail: enrollmentDetail,
				onSetup: onSetup,
				onTest: onTest)

			UnlockSettingsSection(
				settings: settings,
				passwordEntry: $passwordEntry,
				passwordError: passwordError,
				onStorePassword: onStorePassword,
				isEnrolled: store.isEnrolled)

			if store.isEnrolled {
				FaceManagementSection(store: store)
			}
		}
	}

	private var enrollmentDetail: String {
		if store.isCorrupted {
			return "Your saved face could not be read. Set it up again to restore protection."
		}
		if let enrollment = store.enrollment {
			return "\(enrollment.prints.count) angles captured on \(enrollment.enrolledAt.formatted(date: .abbreviated, time: .shortened))"
		}
		return "Enrol your face to unlock this Mac by looking at it."
	}
}

private struct GazeStatusSection: View {

	let isEnrolled: Bool
	let isCorrupted: Bool
	let isLockedOut: Bool
	let detail: String
	let onSetup: () -> Void
	let onTest: () -> Void

	private var tint: Color {
		if isLockedOut { return Theme.danger }
		if isCorrupted || !isEnrolled { return Theme.warning }
		return Theme.faceID
	}

	private var title: String {
		if isLockedOut { return "Gaze is paused" }
		if isCorrupted { return "Gaze needs attention" }
		return isEnrolled ? "Gaze is ready" : "Set up Gaze"
	}

	var body: some View {
		SettingsSection {
			HStack(spacing: 14) {
				Image(systemName: isEnrolled ? "faceid" : "person.crop.circle.badge.questionmark")
					.font(Typography.glyph)
					.foregroundStyle(tint)
					.frame(width: 42)

				VStack(alignment: .leading, spacing: 4) {
					Text(title)
						.font(Typography.heroTitle)
						.foregroundStyle(Theme.label)
					Text(detail)
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}

				Spacer(minLength: 12)

				VStack(alignment: .trailing, spacing: 6) {
					Button(isEnrolled ? "Set Up Again" : "Set Up Gaze", action: onSetup)
						.buttonStyle(.primaryAction)

					if isEnrolled {
						Button("Test Recognition", action: onTest)
							.buttonStyle(.quiet)
					}
				}
				.frame(width: 132)
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 14)
		}
		.animation(.smooth(duration: 0.2), value: isEnrolled)
	}
}

private struct LockoutRecoverySection: View {

	@Binding var password: String
	let onUnlock: () -> Void

	var body: some View {
		SettingsSection(
			title: "Locked out",
			footer: "Gaze is disabled after \(LockoutManager.maxAttempts) failed attempts.") {
			StatusLine(
				kind: .warning,
				message: "Enter your account password to re-enable Gaze.")

			RowDivider(inset: 0)

			SettingRow(
				title: "Account password",
				detail: "Used only to clear the failed-attempt limit.",
				symbol: "exclamationmark.lock.fill",
				symbolTint: Theme.danger) {
				HStack(spacing: 7) {
					SettingsField(placeholder: "Password", text: $password)
						.frame(width: 150)
					Button("Unlock", action: onUnlock)
						.buttonStyle(.accent)
						.disabled(password.isEmpty)
				}
			}
		}
	}
}

private struct UnlockSettingsSection: View {

	@Bindable var settings: Preferences
	@Binding var passwordEntry: String
	let passwordError: String?
	let onStorePassword: () -> Void
	let isEnrolled: Bool

	var body: some View {
		SettingsSection(title: "After recognition", footer: unlockFooter) {
			SettingRow(
				title: "Action",
				detail: selectedBackendDetail,
				symbol: settings.unlockBackend.symbol,
				symbolTint: settings.unlockBackend == .keystroke ? Theme.action : Theme.faceID) {
				Picker("Action after recognition", selection: $settings.unlockBackend) {
					if settings.unlockBackend == .authPlugin {
						Text("Authorization plugin").tag(UnlockBackendKind.authPlugin)
					}
					ForEach(UnlockBackendKind.selectableCases, id: \.self) { kind in
						Text(kind.title).tag(kind)
					}
				}
				.labelsHidden()
				.pickerStyle(.menu)
				.controlSize(.small)
				.tint(Theme.label)
				.fixedSize()
			}
			.onChange(of: settings.unlockBackend) { _, _ in
				AppServices.shared.startUnlockTrigger()
			}

			if settings.unlockBackend == .keystroke {
				RowDivider()
				PasswordSettingsRow(
					password: $passwordEntry,
					error: passwordError,
					onStore: onStorePassword)
			}

			if let problem = readinessProblem {
				RowDivider(inset: 0)
				StatusLine(kind: problem.kind, message: problem.message)
			}
		}
		.opacity(isEnrolled ? 1 : 0.92)
	}

	private var selectedBackendDetail: String {
		if settings.unlockBackend == .authPlugin {
			return "The legacy plugin is retained only for recovery."
		}
		return settings.unlockBackend.detail
	}

	private var unlockFooter: String? {
		if settings.unlockBackend == .authPlugin {
			return "The authorization plugin was removed because it can lock you out. Restore Apple's lock screen before selecting another option: run Plugin/uninstall.sh as an administrator."
		}
		return settings.unlockBackend.detail
	}

	private var readinessProblem: (kind: StatusLine.Kind, message: String)? {
		let backend: UnlockBackend =
			switch settings.unlockBackend {
			case .none: NoUnlockBackend()
			case .authPlugin: AuthPluginUnlockBackend()
			case .keystroke: KeystrokeUnlockBackend()
			}

		switch backend.readiness() {
		case .ready: return nil
		case .needsSetup(let message): return (.warning, message)
		case .unavailable(let message): return (.error, message)
		}
	}
}

private struct PasswordSettingsRow: View {

	@Binding var password: String
	let error: String?
	let onStore: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			SettingRow(
				title: "Account password",
				detail: PasswordVault.hasPassword
					? "A password is stored on this Mac."
					: "Checked against your account before it is stored.",
				symbol: "key.fill",
				symbolTint: Theme.action) {
				HStack(spacing: 7) {
					SettingsField(placeholder: "Password", text: $password)
						.frame(width: 150)
					Button("Store", action: onStore)
						.buttonStyle(.accent)
						.disabled(password.isEmpty)
					InfoButton(title: "How your password is stored") {
						Text("It is encrypted with a key generated inside this Mac's Secure Enclave, which never leaves it.")
						Text("It is not hashed. Gaze must be able to reproduce the password to type it, so anything running as your user account could decrypt it.")
						Text("Choose Just recognise me if you do not want a password stored at all.")
					}
				}
			}

			if let error {
				StatusLine(kind: .error, message: error)
			}
		}
	}
}

private struct FaceManagementSection: View {

	let store: FaceEnrollmentStore

	var body: some View {
		SettingsSection(
			title: "Enrolled face",
			footer: store.embedder.identifier.hasPrefix("landmark")
				? "No recognition model is installed, so Gaze is matching face geometry only. That is much weaker than a trained model."
				: "Your faceprints stay on this Mac and are protected by the Secure Enclave.") {
			SettingRow(
				title: "Remove enrolled face",
				detail: "This cannot be undone.",
				symbol: "trash.fill",
				symbolTint: Theme.danger) {
				Button("Remove", role: .destructive) {
					Task {
						guard await BiometricGate.authorize(.removeEnrollment) else { return }
						store.removeEnrollment()
					}
				}
				.buttonStyle(.destructive)
			}
		}
	}
}

// MARK: - General

private struct GeneralSettingsPage: View {

	@Bindable var settings: Preferences
	let updates: UpdateChecker

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			NotchSettingsSection(settings: settings)
			SecuritySettingsSection(settings: settings)
			MacBehaviorSection(settings: settings)
			AppearanceSettingsSection(settings: settings)
			UpdatesSettingsSection(updates: updates)
		}
	}
}

private struct SecuritySettingsSection: View {

	@Bindable var settings: Preferences

	var body: some View {
		SettingsSection(title: "Security", footer: footer) {
			SettingToggle(
				title: "Only trust the built-in camera",
				detail: "Refuses virtual and external cameras.",
				symbol: "camera.fill",
				isOn: $settings.requireBuiltInCamera)

			RowDivider()
			SettingToggle(
				title: "Reject photos held up to the camera",
				detail: "Uses the optional anti-spoof model.",
				symbol: "eye.trianglebadge.exclamationmark.fill",
				isEnabled: Liveness.isAvailable,
				isOn: $settings.livenessEnabled)

			RowDivider()
			SettingToggle(
				title: "Require Touch ID for changes here",
				detail: "Adds a biometric confirmation before sensitive changes.",
				symbol: "touchid",
				isEnabled: BiometricGate.isAvailable,
				isOn: $settings.touchIDFallback)
		}
	}

	private var footer: String? {
		var notes: [String] = []
		if !Liveness.isAvailable { notes.append("No anti-spoof model is installed.") }
		if !BiometricGate.isAvailable { notes.append("This Mac has no Touch ID sensor.") }
		return notes.isEmpty ? nil : notes.joined(separator: " ")
	}
}

private struct MacBehaviorSection: View {

	@Bindable var settings: Preferences

	var body: some View {
		SettingsSection(title: "This Mac", footer: footer) {
			SettingToggle(
				title: "Open at login",
				detail: "Start watching when you sign in.",
				symbol: "power",
				isOn: Binding(
					get: { LoginItem.isEnabled },
					set: { LoginItem.setEnabled($0) }))

			RowDivider()
			SettingToggle(
				title: "Ask for a password before quitting",
				detail: "Stops an unexpected quit from disabling protection.",
				symbol: "lock.fill",
				isOn: $settings.tamperProtection)
		}
	}

	private var footer: String {
		if LoginItem.needsApproval {
			return "Approve Gaze in System Settings › General › Login Items. Gaze only watches for your screen locking while it is running."
		}
		return "Gaze only watches for your screen locking while it is running."
	}
}

private struct AppearanceSettingsSection: View {

	@Bindable var settings: Preferences

	var body: some View {
		SettingsSection(
			title: "Appearance",
			footer: settings.appTheme == .glass
				? "Uses the notch panel's dark-to-clear material."
				: "Applies to this window. Camera flows keep a dark, neutral surround.") {
			SettingRow(
				title: "Window theme",
				detail: "Choose how the Gaze control center looks.",
				symbol: "circle.lefthalf.filled") {
				Picker("Window theme", selection: $settings.appTheme) {
					ForEach(Preferences.AppTheme.allCases, id: \.self) { theme in
						Text(theme.title).tag(theme)
					}
				}
				.labelsHidden()
				.pickerStyle(.menu)
				.controlSize(.small)
				.tint(Theme.label)
				.fixedSize()
			}
		}
	}
}

private struct UpdatesSettingsSection: View {

	let updates: UpdateChecker

	var body: some View {
		SettingsSection(
			title: "Updates",
			footer: "Your settings and enrolled face survive a rebuild.") {
			SettingRow(
				title: "Version \(updates.currentVersion)",
				detail: updateDetail,
				symbol: "arrow.trianglehead.2.clockwise") {
				Button(updateButtonTitle, action: updateAction)
					.buttonStyle(.accent)
					.disabled(updates.state == .checking || updates.state == .pulling)
			}

			if case .pulled = updates.state {
				RowDivider(inset: 0)
				StatusLine(kind: .warning, message: "Run ./build.sh in the repository to apply the update.")
			}
		}
	}

	private var updateDetail: String {
		switch updates.state {
		case .idle: return "Check whether a newer build is available."
		case .checking: return "Checking the repository…"
		case .upToDate: return "You are on the latest commit."
		case .available(let behind, let latest):
			let plural = behind == 1 ? "commit" : "commits"
			return latest.isEmpty ? "\(behind) new \(plural) available." : "\(behind) new \(plural) — \(latest)"
		case .pulling: return "Pulling the latest commit…"
		case .pulled(let count): return "Pulled \(count) \(count == 1 ? "commit" : "commits")."
		case .failed(let message): return message
		}
	}

	private var updateButtonTitle: String {
		switch updates.state {
		case .available: return "Pull"
		case .pulling: return "Pulling…"
		case .pulled: return "Open Folder"
		default: return "Check"
		}
	}

	private func updateAction() {
		switch updates.state {
		case .available:
			Task { await updates.pull() }
		case .pulled:
			updates.revealRepository()
		default:
			Task { await updates.check() }
		}
	}
}

// MARK: - Information

private struct CreditsSettingsPage: View {

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection(
				title: "Built on other people's work",
				footer: "These projects made Gaze possible.") {
				CreditSettingsRow(
					name: "Sapphire",
					detail: "Recognition model and face matching research",
					symbol: "brain.head.profile",
					url: "https://sapphire-app.tech/")

				RowDivider()
				CreditSettingsRow(
					name: "DynamicLake",
					detail: "Notch panel inspiration",
					symbol: "macbook",
					url: "https://dynamiclake.com")

				RowDivider()
				CreditSettingsRow(
					name: "Atoll",
					detail: "Careful code review and feedback",
					symbol: "hammer.fill",
					url: "https://getatoll.app")
			}

			Text("Thanks to everyone who reviewed the early builds and helped sharpen the settings, light mode, and lock screen experience.")
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 4)
		}
	}
}

private struct CreditSettingsRow: View {

	let name: String
	let detail: String
	let symbol: String
	let url: String

	var body: some View {
		SettingRow(title: name, detail: detail, symbol: symbol, symbolTint: Theme.action) {
			Button("Visit") {
				guard let destination = URL(string: url) else { return }
				NSWorkspace.shared.open(destination)
			}
			.buttonStyle(.quiet)
		}
	}
}

private struct AboutSettingsPage: View {

	let store: FaceEnrollmentStore
	let updates: UpdateChecker

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection(title: "This app") {
				SettingRow(title: "Version", symbol: "info.circle") {
					Text(updates.currentVersion)
						.font(Typography.control)
						.foregroundStyle(Theme.secondaryLabel)
				}

				RowDivider()

				SettingRow(title: "Recognition model", symbol: "brain.head.profile") {
					Text(store.embedder.identifier)
						.font(Typography.control)
						.foregroundStyle(Theme.secondaryLabel)
				}
			}

			VStack(alignment: .leading, spacing: 7) {
				Text("Not Apple's Face ID")
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				Text(
					"Apple's Face ID uses a TrueDepth camera that projects infrared dots to measure the shape of your face. Macs have no such sensor. Gaze recognises you from the ordinary built-in camera, which sees a flat image — so it cannot tell a face from a good photograph of one the way an iPhone can.")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.horizontal, 4)

			SettingsSection(title: "Privacy") {
				SettingRow(
					title: "Faceprints stay on this Mac",
					detail: "The recognition model runs on-device. Images are not kept.",
					symbol: "lock.shield.fill",
					symbolTint: Theme.faceID) { EmptyView() }

				RowDivider()

				SettingRow(
					title: "Your normal password still works",
					detail: "Gaze is a convenience layer, not a replacement for macOS security.",
					symbol: "checkmark.shield.fill",
					symbolTint: Theme.faceID) { EmptyView() }
			}
		}
	}
}
