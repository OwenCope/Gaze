import SwiftUI

/// The panes in the sidebar.
///
/// Three, not six. Six meant a sidebar where most panes held a single group — clicking
/// around to find one switch, with the window mostly empty whichever one you landed on.
enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
	case general
	case face
	case about

	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: return "General"
		case .face: return "Face ID"
		case .about: return "About"
		}
	}

	var symbol: String {
		switch self {
		case .general: return "gearshape.fill"
		case .face: return "faceid"
		case .about: return "info"
		}
	}

	var tint: Color {
		switch self {
		case .general: return Theme.grey
		case .face: return Theme.faceID
		case .about: return Theme.blue
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
		HStack(spacing: 0) {
			sidebar
			Divider().overlay(Theme.separator)
			detail
		}
		.frame(width: 700, height: 540)
		// One vibrancy layer behind the whole window, scrimmed differently on each side.
		// Two separate effect views produced a visible seam where their samples disagreed.
		.background(VibrantBackground())
		.preferredColorScheme(.dark)
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	// MARK: - Sidebar

	private var sidebar: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(SettingsPane.allCases) { item in
				SidebarItem(
					pane: item,
					isSelected: pane == item,
					badge: badge(for: item),
					select: { pane = item })
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 9)
		// Clears the traffic lights, which sit over the sidebar on a hidden title bar.
		.padding(.top, 38)
		.padding(.bottom, 12)
		.frame(width: 168)
		.background(Theme.sidebarScrim)
	}

	/// A dot on the panes that want attention, so a problem is visible from any pane.
	private func badge(for pane: SettingsPane) -> Color? {
		switch pane {
		case .face:
			if lockout.isLockedOut { return Theme.danger }
			return store.isEnrolled ? nil : Theme.warning
		case .general:
			if case .available = updates.state { return Theme.faceID }
			return nil
		case .about:
			return nil
		}
	}

	// MARK: - Detail

	private var detail: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
				Text(pane.title)
					.font(.system(size: 20, weight: .bold))
					.foregroundStyle(Theme.label)
					.padding(.bottom, 2)

				switch pane {
				case .face:
					if lockout.isLockedOut { lockoutSection }
					hero
					unlockSection
					if store.isEnrolled { manageSection }
				case .general:
					NotchSettingsSection(settings: settings)
					securitySection
					updatesSection
				case .about:
					aboutSection
				}

				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 22)
			.padding(.top, 38)
			.padding(.bottom, 26)
		}
		.scrollIndicators(.never)
		.background(Theme.contentScrim)
	}

	// MARK: - Overview

	/// The glyph, the state, and the two things you can do about it.
	private var hero: some View {
		SettingsSection {
			// Laid out sideways, not as a centred stack.
			//
			// Centred, the glyph and its two buttons left a column of empty card either
			// side and the pane opened on a mostly blank box. A status row reads as part of
			// the settings rather than as a splash screen.
			HStack(spacing: 14) {
				Image(
					systemName: store.isEnrolled
						? "faceid" : "person.crop.circle.badge.questionmark"
				)
				.font(.system(size: 34, weight: .thin))
				.foregroundStyle(heroTint)
				.frame(width: 42)
				.animation(.easeOut(duration: 0.25), value: store.isEnrolled)

				VStack(alignment: .leading, spacing: 3) {
					Text(store.isEnrolled ? "Face ID is set up" : "Face ID isn't set up")
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(Theme.label)
					Text(heroDetail)
						.font(.system(size: 11))
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}

				Spacer(minLength: 8)

				VStack(alignment: .trailing, spacing: 6) {
					Button(store.isEnrolled ? "Set Up Again" : "Set Up Face ID") {
						AppActivation.bringToFront()
						openWindow(id: "enrollment")
					}
					.buttonStyle(AccentButtonStyle())

					if store.isEnrolled {
						Button("Test Recognition") {
							AppActivation.bringToFront()
							openWindow(id: "test")
						}
						.buttonStyle(AccentButtonStyle(role: .cancel))
					}
				}
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 14)
		}
	}

	/// Red while locked out, grey when unenrolled, green when ready — so the glyph itself
	/// carries the state rather than relying on the text below it.
	private var heroTint: Color {
		if lockout.isLockedOut { return Theme.danger }
		return store.isEnrolled ? Theme.faceID : Theme.tertiaryLabel
	}

	private var heroDetail: String {
		if store.isCorrupted {
			return "Your enrolled face couldn't be read and has been ignored."
		}
		if let enrollment = store.enrollment {
			return "\(enrollment.prints.count) angles captured on \(enrollment.enrolledAt.formatted(date: .abbreviated, time: .shortened))."
		}
		return "Enrol your face to unlock this Mac by looking at it."
	}

	private var manageSection: some View {
		SettingsSection(
			title: "Enrolled face",
			footer: store.embedder.identifier.hasPrefix("landmark")
				? "No recognition model is installed, so Face ID is matching face geometry only. "
					+ "That tells you from a stranger but is much weaker than a trained model."
				: nil
		) {
			SettingRow(title: "Recognition model", symbol: "brain.head.profile", symbolTint: Theme.purple) {
				Text(store.embedder.identifier)
					.font(.system(size: 12))
					.foregroundStyle(Theme.secondaryLabel)
			}
			RowDivider()
			SettingRow(
				title: "Remove enrolled face",
				symbol: "trash.fill", symbolTint: Theme.danger
			) {
				Button("Remove", role: .destructive) {
					Task {
						guard await BiometricGate.authorize(.removeEnrollment) else { return }
						store.removeEnrollment()
					}
				}
				.buttonStyle(AccentButtonStyle(role: .destructive))
			}
		}
	}

	// MARK: - Lockout

	private var lockoutSection: some View {
		SettingsSection(
			title: "Locked out",
			footer: "Face ID is disabled after \(LockoutManager.maxAttempts) failed attempts."
		) {
			SettingRow(
				title: "Account password",
				symbol: "exclamationmark.lock.fill", symbolTint: Theme.danger
			) {
				HStack(spacing: 6) {
					SettingsField(placeholder: "Required", text: $lockoutPassword)
						.frame(width: 140)
					Button("Unlock") { clearLockout() }
						.buttonStyle(AccentButtonStyle())
						.disabled(lockoutPassword.isEmpty)
				}
			}
		}
	}

	// MARK: - Unlocking

	private var unlockSection: some View {
		SettingsSection(footer: unlockFooter) {
			// A pop-up menu, not three cards with icons and checkmarks.
			//
			// The cards spent a third of the window explaining options the user picks once
			// and never revisits. A menu states the current choice in one line and explains
			// only that one, underneath.
			SettingRow(title: "When your face is recognised", symbol: "faceid", symbolTint: Theme.faceID) {
				Picker("", selection: unlockBinding) {
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

			if settings.unlockBackend == .keystroke {
				RowDivider()
				passwordRow
			}

			if let problem = readinessProblem {
				RowDivider(inset: 0)
				StatusPill(kind: problem.kind, message: problem.message)
			}
		}
	}

	private var unlockBinding: Binding<UnlockBackendKind> {
		Binding(
			get: { settings.unlockBackend },
			set: {
				settings.unlockBackend = $0
				// Apply immediately rather than at next launch.
				AppServices.shared.startUnlockTrigger()
			})
	}

	/// Explains the selected option, and the plugin's removal when that is what is selected.
	private var unlockFooter: String? {
		if settings.unlockBackend == .authPlugin {
			return "The authorization plugin was removed because it can lock you out. "
				+ "Restore Apple's lock screen before selecting another option: run "
				+ "Plugin/uninstall.sh as an administrator."
		}
		return UnlockBackendKind.selectableCases
			.first { $0 == settings.unlockBackend }?.detail
	}

	/// The readiness line, but only when there is something wrong with it.
	///
	/// A green "Ready." sitting permanently in the window is noise: the state it reports is
	/// the state the user already expects.
	private var readinessProblem: (kind: StatusPill.Kind, message: String)? {
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

	private var passwordRow: some View {
		VStack(spacing: 0) {
			SettingRow(
				title: "Account password",
				detail: "Checked against your account before it's stored.",
				symbol: "key.fill", symbolTint: Theme.orange
			) {
				HStack(spacing: 6) {
					SettingsField(placeholder: "Required", text: $passwordEntry)
						.frame(width: 140)
					Button("Store") { storePassword() }
						.buttonStyle(AccentButtonStyle())
						.disabled(passwordEntry.isEmpty)
						.fixedSize()
				}
			}
			if let passwordError {
				StatusPill(kind: .error, message: passwordError)
			}
		}
	}

	// MARK: - Security

	private var securitySection: some View {
		SettingsSection(footer: securityFooter) {
			SettingToggle(
				title: "Only trust the built-in camera",
				symbol: "camera.fill", symbolTint: Theme.blue,
				isOn: bind(\.requireBuiltInCamera))

			RowDivider()
			SettingToggle(
				title: "Reject photos held up to the camera",
				symbol: "eye.trianglebadge.exclamationmark.fill", symbolTint: Theme.orange,
				isEnabled: Liveness.isAvailable,
				isOn: bind(\.livenessEnabled))

			RowDivider()
			SettingToggle(
				title: "Require Touch ID for changes here",
				symbol: "touchid", symbolTint: Theme.pink,
				isEnabled: BiometricGate.isAvailable,
				isOn: bind(\.touchIDFallback))

			RowDivider()
			SettingToggle(
				title: "Open at login",
				symbol: "power", symbolTint: Theme.faceID,
				isOn: Binding(
					get: { LoginItem.isEnabled },
					set: { LoginItem.setEnabled($0) }))

			RowDivider()
			SettingToggle(
				title: "Ask for a password before quitting",
				symbol: "lock.fill", symbolTint: Theme.indigo,
				isOn: bind(\.tamperProtection))
		}
	}

	/// Only the caveats. Rows that work as expected need no sentence explaining that they do.
	private var securityFooter: String {
		var notes: [String] = []
		if !Liveness.isAvailable { notes.append("No anti-spoof model is installed.") }
		if !BiometricGate.isAvailable { notes.append("This Mac has no Touch ID sensor.") }
		if LoginItem.needsApproval {
			notes.append("Approve Face ID in System Settings › General › Login Items.")
		}
		notes.append("Face ID only watches for your screen locking while it's running.")
		return notes.joined(separator: " ")
	}

	// MARK: - Updates

	private var updatesSection: some View {
		SettingsSection(
			footer: "\(updateDetail) Your settings and enrolled face survive a rebuild."
		) {
			SettingRow(
				title: "Version \(updates.currentVersion)",
				symbol: "arrow.trianglehead.2.clockwise", symbolTint: Theme.blue
			) {
				Button(updateButtonTitle) { updateAction() }
					.buttonStyle(AccentButtonStyle())
					.disabled(updates.state == .checking || updates.state == .pulling)
			}

			if case .pulled = updates.state {
				RowDivider(inset: 0)
				StatusPill(
					kind: .warning,
					message: "Run ./build.sh in the repository to apply the update.")
			}
		}
	}

	private var updateDetail: String {
		switch updates.state {
		case .idle: return "Check whether there are new commits."
		case .checking: return "Checking…"
		case .upToDate: return "You're on the latest commit."
		case .available(let behind, let latest):
			let plural = behind == 1 ? "commit" : "commits"
			return latest.isEmpty
				? "\(behind) new \(plural)."
				: "\(behind) new \(plural) — latest: \(latest)"
		case .pulling: return "Pulling…"
		case .pulled(let count):
			return "Pulled \(count) \(count == 1 ? "commit" : "commits")."
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

	// MARK: - About

	private var aboutSection: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection {
				VStack(spacing: 10) {
					Image(systemName: "faceid")
						.font(.system(size: 40, weight: .thin))
						.foregroundStyle(Theme.faceID)
					Text("Face ID")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Theme.label)
					Text("Version \(updates.currentVersion)")
						.font(.system(size: 11))
						.foregroundStyle(Theme.secondaryLabel)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 22)
			}

			SettingsSection(title: "Thanks") {
				SettingRow(
					title: "DanFQ",
					detail: "Sapphire, whose recognition model this uses.",
					symbol: "heart.fill", symbolTint: Theme.pink
				) {
					Button("Visit") {
						if let url = URL(string: "https://sapphire-app.tech/") {
							NSWorkspace.shared.open(url)
						}
					}
					.buttonStyle(AccentButtonStyle(role: .cancel))
				}
			}
		}
	}

	// MARK: - Actions

	private func bind(_ path: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
		Binding(
			get: { settings[keyPath: path] },
			set: { settings[keyPath: path] = $0 })
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
			lockoutPassword = ""
		} else {
			lockoutPassword = ""
		}
	}
}

// MARK: - Sidebar row

private struct SidebarItem: View {

	let pane: SettingsPane
	let isSelected: Bool
	let badge: Color?
	let select: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: select) {
			HStack(spacing: 9) {
				IconTile(symbol: pane.symbol, tint: pane.tint)
				Text(pane.title)
					.font(.system(size: 13))
					.foregroundStyle(Theme.label)
					.lineLimit(1)
				Spacer(minLength: 4)
				if let badge {
					Circle()
						.fill(badge)
						.frame(width: 6, height: 6)
				}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.background {
				RoundedRectangle(cornerRadius: 8, style: .continuous)
					.fill(
						isSelected
							? Color.white.opacity(0.14)
							: (isHovering ? Color.white.opacity(0.06) : .clear))
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
	}
}
