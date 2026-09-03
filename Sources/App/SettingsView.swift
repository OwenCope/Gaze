import AppKit
import SwiftUI

/// The main areas of Gaze's control center.
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
		self == .face ? Theme.faceID : Theme.grey
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
			return "A clear look at what Gaze can do"
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

	var body: some View {
		HStack(spacing: 0) {
			SettingsSidebar(
				selection: $pane,
				store: store,
				lockout: lockout,
				updates: updates)

			Rectangle()
				.fill(Theme.softSeparator)
				.frame(width: 1)
				.padding(.vertical, 18)

			SettingsDetail(
				pane: pane,
				store: store,
				lockout: lockout,
				settings: settings,
				updates: updates,
				passwordEntry: $passwordEntry,
				passwordError: $passwordError,
				lockoutPassword: $lockoutPassword,
				onStorePassword: storePassword,
				onClearLockout: clearLockout)
		}
		.frame(
			minWidth: 820, idealWidth: 920, maxWidth: .infinity,
			minHeight: 560, idealHeight: 650, maxHeight: .infinity)
		.background(WindowGlass(extraTranslucent: settings.appTheme == .glass))
		.preferredColorScheme(settings.appTheme.colorScheme)
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
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

// MARK: - Sidebar

private struct SettingsSidebar: View {

	@Binding var selection: SettingsPane
	let store: FaceEnrollmentStore
	let lockout: LockoutManager
	let updates: UpdateChecker

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 11) {
				GazeMark(size: 40)
				VStack(alignment: .leading, spacing: 1) {
					Text("Gaze")
						.font(.system(.title3, weight: .bold))
						.foregroundStyle(Theme.label)
					Text("Secure glance unlock")
						.font(Typography.caption)
						.foregroundStyle(Theme.secondaryLabel)
				}
			}
			.padding(.horizontal, 8)

			SidebarStatusCard(
				isEnrolled: store.isEnrolled,
				isLockedOut: lockout.isLockedOut)
			.padding(.top, 22)
			.padding(.bottom, 24)

			Text("CONTROL CENTER")
				.font(.system(.caption2, weight: .bold))
				.foregroundStyle(Theme.tertiaryLabel)
				.tracking(1.0)
				.padding(.horizontal, 10)
				.padding(.bottom, 8)

			ForEach([SettingsPane.general, .face], id: \.self) { item in
				SettingsSidebarItem(
					pane: item,
					isSelected: selection == item,
					badge: badge(for: item),
					select: { selection = item })
			}

			Rectangle()
				.fill(Theme.softSeparator)
				.frame(height: 1)
				.padding(.horizontal, 10)
				.padding(.vertical, 13)

			Text("MORE")
				.font(.system(.caption2, weight: .bold))
				.foregroundStyle(Theme.tertiaryLabel)
				.tracking(1.0)
				.padding(.horizontal, 10)
				.padding(.bottom, 8)

			ForEach([SettingsPane.credits, .about], id: \.self) { item in
				SettingsSidebarItem(
					pane: item,
					isSelected: selection == item,
					badge: badge(for: item),
					select: { selection = item })
			}

			Spacer(minLength: 0)

			HStack(spacing: 8) {
				Circle()
					.fill(store.isEnrolled && !lockout.isLockedOut ? Theme.faceID : Theme.warning)
					.frame(width: 7, height: 7)
				Text("Gaze \(updates.currentVersion)")
					.font(Typography.caption)
					.foregroundStyle(Theme.tertiaryLabel)
			}
			.padding(.horizontal, 10)
			.padding(.bottom, 4)
		}
		.padding(.horizontal, 12)
		.padding(.top, 30)
		.padding(.bottom, 16)
		.frame(width: 220)
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Gaze settings navigation")
	}

	private func badge(for pane: SettingsPane) -> Color? {
		switch pane {
		case .face:
			if lockout.isLockedOut { return Theme.danger }
			return store.isEnrolled ? nil : Theme.warning
		case .general:
			if case .available = updates.state { return Theme.action }
			return nil
		case .credits, .about:
			return nil
		}
	}
}

private struct SidebarStatusCard: View {

	let isEnrolled: Bool
	let isLockedOut: Bool

	private var title: String {
		if isLockedOut { return "Action required" }
		return isEnrolled ? "Protection is ready" : "Finish setup"
	}

	private var detail: String {
		if isLockedOut { return "Enter your password to resume" }
		return isEnrolled ? "Watching for your screen to lock" : "Enroll your face to begin"
	}

	private var tint: Color {
		if isLockedOut { return Theme.danger }
		return isEnrolled ? Theme.faceID : Theme.warning
	}

	var body: some View {
		HStack(alignment: .top, spacing: 9) {
			Circle()
				.fill(tint)
				.frame(width: 8, height: 8)
				.padding(.top, 5)

			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(Theme.label)
				Text(detail)
					.font(Typography.caption)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background {
			RoundedRectangle(cornerRadius: 13, style: .continuous)
				.fill(tint.opacity(0.10))
				.overlay {
					RoundedRectangle(cornerRadius: 13, style: .continuous)
						.strokeBorder(tint.opacity(0.18), lineWidth: 1)
				}
		}
	}
}

private struct SettingsSidebarItem: View {

	let pane: SettingsPane
	let isSelected: Bool
	let badge: Color?
	let select: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: select) {
			HStack(spacing: 10) {
				IconTile(symbol: pane.symbol, tint: pane.tint)
				Text(pane.title)
					.font(Typography.row)
					.foregroundStyle(Theme.label)
				Spacer(minLength: 4)
				if let badge {
					Circle()
						.fill(badge)
						.frame(width: 7, height: 7)
				}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 7)
			.background {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(isSelected ? Theme.selection : (isHovering ? Theme.hoverFill : .clear))
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.focusable(isSelected)
		.focusEffectDisabled()
		.onHover { isHovering = $0 }
		.accessibilityLabel(pane.title)
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
		.accessibilityValue(badge == nil ? "" : "Needs attention")
	}
}

// MARK: - Detail routing

private struct SettingsDetail: View {

	let pane: SettingsPane
	let store: FaceEnrollmentStore
	let lockout: LockoutManager
	@Bindable var settings: Preferences
	let updates: UpdateChecker

	@Binding var passwordEntry: String
	@Binding var passwordError: String?
	@Binding var lockoutPassword: String

	let onStorePassword: () -> Void
	let onClearLockout: () -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 22) {
				SettingsDetailHeader(
					pane: pane,
					isEnrolled: store.isEnrolled,
					isLockedOut: lockout.isLockedOut)

				switch pane {
				case .face:
					FaceSettingsPane(
						store: store,
						lockout: lockout,
						settings: settings,
						passwordEntry: $passwordEntry,
						passwordError: $passwordError,
						lockoutPassword: $lockoutPassword,
						onStorePassword: onStorePassword,
						onClearLockout: onClearLockout)
				case .general:
					GeneralSettingsPane(settings: settings, updates: updates)
				case .credits:
					CreditsSettingsPane()
				case .about:
					AboutSettingsPane(store: store, updates: updates)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 28)
			.padding(.top, 34)
			.padding(.bottom, 30)
		}
		.scrollIndicators(.automatic)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

private struct SettingsDetailHeader: View {

	let pane: SettingsPane
	let isEnrolled: Bool
	let isLockedOut: Bool

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			VStack(alignment: .leading, spacing: 5) {
				Text("GAZE CONTROL CENTER")
					.font(.system(.caption2, weight: .bold))
					.foregroundStyle(pane == .face ? Theme.faceID : Theme.tertiaryLabel)
					.tracking(1.1)
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
				StatusBadge(
					title: isLockedOut ? "LOCKED OUT" : (isEnrolled ? "PROTECTED" : "NOT SET UP"),
					symbol: isLockedOut ? "lock.fill" : (isEnrolled ? "checkmark" : "exclamationmark"),
					tint: isLockedOut ? Theme.danger : (isEnrolled ? Theme.faceID : Theme.warning))
				.padding(.top, 7)
			}
		}
	}
}

// MARK: - Gaze pane

private struct FaceSettingsPane: View {

	let store: FaceEnrollmentStore
	let lockout: LockoutManager
	@Bindable var settings: Preferences
	@Binding var passwordEntry: String
	@Binding var passwordError: String?
	@Binding var lockoutPassword: String
	let onStorePassword: () -> Void
	let onClearLockout: () -> Void

	@Environment(\.openWindow) private var openWindow

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			if lockout.isLockedOut {
				LockoutRecoveryCard(
					password: $lockoutPassword,
					onUnlock: onClearLockout)
			}

			GazeOverviewCard(
				isEnrolled: store.isEnrolled,
				isCorrupted: store.isCorrupted,
				isLockedOut: lockout.isLockedOut,
				detail: enrollmentDetail,
				onSetup: {
					AppActivation.bringToFront()
					openWindow(id: "enrollment")
				},
				onTest: {
					AppActivation.bringToFront()
					openWindow(id: "test")
				})

			HStack(spacing: 12) {
				DashboardMetric(
					label: "ENROLLED ANGLES",
					value: store.enrollment.map { "\($0.prints.count)" } ?? "—",
					detail: store.isEnrolled ? "Across two setup passes" : "Complete setup to add yours",
					symbol: "viewfinder",
					tint: Theme.faceID)

				DashboardMetric(
					label: "RECOGNITION",
					value: store.embedder.identifier.hasPrefix("coreml") ? "Core ML" : "Geometry",
					detail: store.embedder.identifier.hasPrefix("coreml") ? "On-device model" : "Limited confidence",
					symbol: "brain.head.profile",
					tint: store.embedder.identifier.hasPrefix("coreml") ? Theme.action : Theme.warning)

				DashboardMetric(
					label: "ATTEMPTS",
					value: lockout.isLockedOut ? "0" : "\(lockout.attemptsRemaining)",
					detail: lockout.isLockedOut ? "Password required" : "Until lockout",
					symbol: lockout.isLockedOut ? "lock.trianglebadge.exclamationmark" : "shield.fill",
					tint: lockout.isLockedOut ? Theme.danger : Theme.faceID)
			}

			UnlockConfigurationCard(
				settings: settings,
				passwordEntry: $passwordEntry,
				passwordError: passwordError,
				onStorePassword: onStorePassword,
				isEnrolled: store.isEnrolled)

			if store.isEnrolled {
				FaceManagementCard(store: store)
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
		return "Enroll your face to unlock this Mac by looking at it."
	}
}

private struct GazeOverviewCard: View {

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

	private var badgeTitle: String {
		if isLockedOut { return "ACTION REQUIRED" }
		if isCorrupted || !isEnrolled { return "SETUP NEEDED" }
		return "READY TO RECOGNISE"
	}

	private var badgeSymbol: String {
		if isLockedOut { return "lock.fill" }
		if isCorrupted || !isEnrolled { return "sparkles" }
		return "checkmark"
	}

	var body: some View {
		ZStack(alignment: .topTrailing) {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(
					LinearGradient(
						colors: [Theme.surfaceRaised, Theme.surface],
						startPoint: .topLeading,
						endPoint: .bottomTrailing))

			Circle()
				.fill(tint.opacity(0.14))
				.frame(width: 190, height: 190)
				.blur(radius: 12)
				.offset(x: 76, y: -82)

			VStack(alignment: .leading, spacing: 16) {
				HStack {
					StatusBadge(title: badgeTitle, symbol: badgeSymbol, tint: tint)
					Spacer(minLength: 12)
					GazeMark(size: 56, tint: tint)
				}

				VStack(alignment: .leading, spacing: 6) {
					Text(title)
						.font(.system(.title, weight: .bold))
						.foregroundStyle(Theme.label)
					Text(detail)
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}

				HStack(spacing: 9) {
					Button(isEnrolled ? "Set Up Again" : "Start Setup", action: onSetup)
						.buttonStyle(.primaryAction)

					if isEnrolled {
						Button("Test Recognition", action: onTest)
							.buttonStyle(.quiet)
					}
				}
			}
			.padding(20)
		}
		.clipped()
		.overlay {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.strokeBorder(tint.opacity(0.22), lineWidth: 1)
		}
	}
}

private struct LockoutRecoveryCard: View {

	@Binding var password: String
	let onUnlock: () -> Void

	var body: some View {
		DashboardCard {
			HStack(spacing: 12) {
				Image(systemName: "lock.trianglebadge.exclamationmark.fill")
					.font(.system(size: 23, weight: .medium))
					.foregroundStyle(Theme.danger)
				VStack(alignment: .leading, spacing: 3) {
					Text("Gaze is temporarily locked")
						.font(.system(.headline, weight: .semibold))
						.foregroundStyle(Theme.label)
					Text("Enter your account password to clear the failed-attempt limit.")
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: 8)
				HStack(spacing: 7) {
					SettingsField(placeholder: "Password", text: $password)
						.frame(width: 150)
					Button("Unlock", action: onUnlock)
						.buttonStyle(.accent)
						.disabled(password.isEmpty)
				}
			}
		}
		.overlay {
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.strokeBorder(Theme.danger.opacity(0.30), lineWidth: 1)
		}
	}
}

private struct UnlockConfigurationCard: View {

	@Bindable var settings: Preferences
	@Binding var passwordEntry: String
	let passwordError: String?
	let onStorePassword: () -> Void
	let isEnrolled: Bool

	var body: some View {
		DashboardCard(
			title: "After recognition",
			detail: "Choose what Gaze should do when it recognises you.") {
			VStack(alignment: .leading, spacing: 14) {
				HStack(spacing: 12) {
					Image(systemName: settings.unlockBackend.symbol)
						.font(.system(.title3, weight: .medium))
						.foregroundStyle(settings.unlockBackend == .keystroke ? Theme.action : Theme.faceID)
						.frame(width: 28)

					VStack(alignment: .leading, spacing: 2) {
						Text("Action")
							.font(Typography.row)
							.foregroundStyle(Theme.label)
						Text(selectedBackendDetail)
							.font(Typography.detail)
							.foregroundStyle(Theme.secondaryLabel)
							.fixedSize(horizontal: false, vertical: true)
					}

					Spacer(minLength: 8)

					Picker("Action after recognition", selection: $settings.unlockBackend) {
						if settings.unlockBackend == .authPlugin {
							Text("Authorization plugin").tag(UnlockBackendKind.authPlugin)
						}
						ForEach(UnlockBackendKind.selectableCases, id: \.self) { kind in
							Text(kind.title).tag(kind)
						}
					}
					.pickerStyle(.menu)
					.controlSize(.small)
					.tint(Theme.label)
					.onChange(of: settings.unlockBackend) { _, _ in
						AppServices.shared.startUnlockTrigger()
					}
				}

				if settings.unlockBackend == .keystroke {
					Rectangle()
						.fill(Theme.softSeparator)
						.frame(height: 1)

					HStack(spacing: 12) {
						IconTile(symbol: "key.fill", tint: Theme.action)
						VStack(alignment: .leading, spacing: 2) {
							Text("Account password")
								.font(Typography.row)
								.foregroundStyle(Theme.label)
							Text(PasswordVault.hasPassword ? "A password is stored on this Mac" : "Required before unlock can work")
								.font(Typography.detail)
								.foregroundStyle(Theme.secondaryLabel)
						}
						Spacer(minLength: 8)
						HStack(spacing: 7) {
							SettingsField(placeholder: "Password", text: $passwordEntry)
								.frame(width: 150)
							Button("Store", action: onStorePassword)
								.buttonStyle(.accent)
								.disabled(passwordEntry.isEmpty)
							InfoButton(title: "How your password is stored") {
								Text("It is encrypted with a key generated inside this Mac's Secure Enclave, which never leaves it.")
								Text("It is not hashed. Gaze must be able to reproduce the password to type it, so anything running as your user account could decrypt it.")
								Text("Choose Just recognise me if you do not want a password stored at all.")
							}
						}
					}

					if let passwordError {
						StatusLine(kind: .error, message: passwordError)
					}
				}

				if let problem = readinessProblem {
					StatusLine(kind: problem.kind, message: problem.message)
				}
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

private struct FaceManagementCard: View {

	let store: FaceEnrollmentStore

	var body: some View {
		DashboardCard(
			title: "Enrolled face",
			detail: store.embedder.identifier.hasPrefix("landmark")
				? "No recognition model is installed, so Gaze is using face geometry only."
				: "Your faceprints stay on this Mac and are protected by the Secure Enclave.") {
			HStack {
				Label("Remove enrolled face", systemImage: "trash")
					.font(Typography.row)
					.foregroundStyle(Theme.label)
				Spacer()
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

// MARK: - General pane

private struct GeneralSettingsPane: View {

	@Bindable var settings: Preferences
	let updates: UpdateChecker

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			NotchSettingsSection(settings: settings)
			SecuritySettingsCard(settings: settings)
			MacBehaviorCard(settings: settings)
			AppearanceCard(settings: settings)
			UpdatesCard(updates: updates)
		}
	}
}

private struct SecuritySettingsCard: View {

	@Bindable var settings: Preferences

	var body: some View {
		SettingsSection(title: "Hardening", footer: footer) {
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

private struct MacBehaviorCard: View {

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

private struct AppearanceCard: View {

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

private struct UpdatesCard: View {

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

// MARK: - Information panes

private struct CreditsSettingsPane: View {

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			DashboardCard(
				title: "Built with great work",
				detail: "Gaze stands on the shoulders of projects that make Mac utilities feel thoughtful.") {
				CreditRow(
					name: "Sapphire",
					detail: "Recognition model and face matching research",
					symbol: "brain.head.profile",
					url: "https://sapphire-app.tech/")

				Rectangle().fill(Theme.softSeparator).frame(height: 1)

				CreditRow(
					name: "DynamicLake",
					detail: "Notch panel inspiration",
					symbol: "macbook",
					url: "https://dynamiclake.com")

				Rectangle().fill(Theme.softSeparator).frame(height: 1)

				CreditRow(
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

private struct CreditRow: View {

	let name: String
	let detail: String
	let symbol: String
	let url: String

	var body: some View {
		HStack(spacing: 12) {
			IconTile(symbol: symbol, tint: Theme.action)
			VStack(alignment: .leading, spacing: 3) {
				Text(name)
					.font(.system(.headline, weight: .semibold))
					.foregroundStyle(Theme.label)
				Text(detail)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
			}
			Spacer(minLength: 8)
			Button("Visit") {
				guard let destination = URL(string: url) else { return }
				NSWorkspace.shared.open(destination)
			}
			.buttonStyle(.quiet)
		}
	}
}

private struct AboutSettingsPane: View {

	let store: FaceEnrollmentStore
	let updates: UpdateChecker

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			DashboardCard {
				HStack(spacing: 14) {
					GazeMark(size: 58)
					VStack(alignment: .leading, spacing: 3) {
						Text("Gaze")
							.font(.system(.title2, weight: .bold))
							.foregroundStyle(Theme.label)
						Text("Version \(updates.currentVersion)")
							.font(Typography.detail)
							.foregroundStyle(Theme.secondaryLabel)
					}
					Spacer()
				}
			}

			DashboardCard(
				title: "What Gaze does",
				detail: "It recognises you from the ordinary camera built into your Mac and can type your password when you choose that mode.") {
				AboutFact(symbol: "lock.shield.fill", title: "Local by design", detail: "Faceprints and any stored password stay on this Mac.")
				AboutFact(symbol: "camera.fill", title: "Camera-based", detail: "This is convenience, not Apple's TrueDepth Face ID.")
				AboutFact(symbol: "checkmark.shield.fill", title: "Always recoverable", detail: "Your normal password and Touch ID remain available.")
			}

			DashboardCard(
				title: "Recognition engine",
				detail: store.embedder.identifier) {
				Text("The model runs on-device. Changing the model invalidates existing enrolments so faceprints from different feature spaces are never compared.")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

private struct AboutFact: View {

	let symbol: String
	let title: String
	let detail: String

	var body: some View {
		HStack(alignment: .top, spacing: 11) {
			Image(systemName: symbol)
				.font(.system(.body, weight: .medium))
				.foregroundStyle(Theme.faceID)
				.frame(width: 23)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(Theme.label)
				Text(detail)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}
