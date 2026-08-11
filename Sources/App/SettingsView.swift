import SwiftUI

struct SettingsView: View {

	let store: FaceEnrollmentStore
	let lockout: LockoutManager

	@State private var settings = Preferences.shared
	@State private var updates = UpdateChecker.shared
	@State private var passwordEntry = ""
	@State private var passwordError: String?
	@State private var lockoutPassword = ""

	@Environment(\.openWindow) private var openWindow

	var body: some View {
		ScrollView {
			VStack(spacing: Theme.sectionSpacing) {
				hero
				if lockout.isLockedOut { lockoutSection }
				unlockSection
				NotchSettingsSection(settings: settings)
				securitySection
				updatesSection
				if store.isEnrolled { manageSection }
			}
			.padding(.horizontal, 26)
			.padding(.top, 26)
			.padding(.bottom, 32)
		}
		.scrollIndicators(.never)
		.frame(width: 540, height: 660)
		.background(Theme.background)
		.preferredColorScheme(.dark)
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	// MARK: - Hero

	private var hero: some View {
		VStack(spacing: 14) {
			ZStack {
				// A soft bloom behind the glyph, and a ring around it. Together they make
				// the mark read as active rather than as a flat icon sitting on black.
				Circle()
					.fill(
						RadialGradient(
							colors: [heroTint.opacity(0.28), heroTint.opacity(0)],
							center: .center, startRadius: 4, endRadius: 62))
					.frame(width: 124, height: 124)

				Circle()
					.strokeBorder(heroTint.opacity(0.30), lineWidth: 1)
					.frame(width: 92, height: 92)

				Circle()
					.fill(heroTint.opacity(0.14))
					.frame(width: 78, height: 78)

				Image(systemName: store.isEnrolled ? "faceid" : "person.crop.circle.badge.questionmark")
					.font(.system(size: 36, weight: .light))
					.foregroundStyle(heroTint)
			}
			.animation(.easeOut(duration: 0.25), value: store.isEnrolled)

			VStack(spacing: 5) {
				Text(store.isEnrolled ? "Face ID Is Set Up" : "Face ID Isn't Set Up")
					.font(.system(size: 19, weight: .semibold))
					.foregroundStyle(Theme.label)

				Text(heroDetail)
					.font(.system(size: 12))
					.foregroundStyle(Theme.secondaryLabel)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack(spacing: 8) {
				Button(store.isEnrolled ? "Set Up Again" : "Set Up Face ID") {
					AppActivation.bringToFront()
					openWindow(id: "enrollment")
				}
				.buttonStyle(AccentButtonStyle())

				if store.isEnrolled {
					Button("Test") {
						AppActivation.bringToFront()
						openWindow(id: "test")
					}
					.buttonStyle(AccentButtonStyle(role: .cancel))
				}
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.bottom, 4)
	}

	/// Red while locked out, grey when unenrolled, green when ready — so the hero itself
	/// carries the state rather than relying on the text below it.
	private var heroTint: Color {
		if lockout.isLockedOut { return Theme.danger }
		return store.isEnrolled ? Theme.accent : Theme.tertiaryLabel
	}

	private var heroDetail: String {
		if store.isCorrupted {
			return "Your enrolled face couldn't be read and has been ignored."
		}
		if let enrollment = store.enrollment {
			return "\(enrollment.prints.count) angles captured on \(enrollment.enrolledAt.formatted(date: .abbreviated, time: .shortened))"
		}
		return "Enrol your face to unlock this Mac by looking at it."
	}

	// MARK: - Lockout

	private var lockoutSection: some View {
		SettingsSection(title: "Locked Out") {
			StatusPill(
				kind: .warning,
				message:
					"Face ID is disabled after \(LockoutManager.maxAttempts) failed attempts. "
					+ "Enter your account password to re-enable it.")
			RowDivider()
			SettingRow(title: "Account password") {
				HStack(spacing: 8) {
					SecureField("Required", text: $lockoutPassword)
						.textFieldStyle(.plain)
						.font(.system(size: 13))
						.frame(width: 150)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background {
							Capsule()
								.fill(Theme.surfaceRaised)
								.overlay(
									Capsule().strokeBorder(Theme.cardHighlight, lineWidth: 1))
						}
					Button("Unlock") { clearLockout() }
						.buttonStyle(AccentButtonStyle())
						.disabled(lockoutPassword.isEmpty)
				}
			}
		}
	}

	// MARK: - Unlocking

	private var unlockSection: some View {
		SettingsSection(
			title: "When Your Face Is Recognised",
			footer: settings.unlockBackend == .authPlugin
				? "Restore Apple's lock screen before selecting another option: run "
					+ "Plugin/uninstall.sh as an administrator."
				: nil
		) {
			if settings.unlockBackend == .authPlugin {
				StatusPill(
					kind: .error,
					message: "The authorization plugin was removed because it can lock you out."
				)
				RowDivider()
			}

			ForEach(Array(UnlockBackendKind.selectableCases.enumerated()), id: \.element) { index, kind in
				if index > 0 { RowDivider() }
				SettingChoice(
					title: kind.title,
					detail: kind.detail,
					symbol: kind.symbol,
					isSelected: settings.unlockBackend == kind
				) {
					settings.unlockBackend = kind
					// Apply immediately rather than at next launch.
					AppServices.shared.startUnlockTrigger()
				}
			}

			if settings.unlockBackend != .authPlugin {
				RowDivider()
				readiness
			}

			if settings.unlockBackend == .keystroke {
				RowDivider()
				passwordRow
			}
		}
	}

	@ViewBuilder
	private var readiness: some View {
		let backend: UnlockBackend = {
			switch settings.unlockBackend {
			case .none: return NoUnlockBackend()
			case .authPlugin: return AuthPluginUnlockBackend()
			case .keystroke: return KeystrokeUnlockBackend()
			}
		}()

		switch backend.readiness() {
		case .ready:
			StatusPill(kind: .ok, message: "Ready.")
		case .needsSetup(let message):
			StatusPill(kind: .warning, message: message)
		case .unavailable(let message):
			StatusPill(kind: .error, message: message)
		}
	}

	private var passwordRow: some View {
		VStack(spacing: 0) {
			// Laid out as a full-width row rather than a trailing accessory: the field plus
			// the button need more room than a trailing slot gives them, and squeezing
			// them in wraps the button's label one letter per line.
			VStack(alignment: .leading, spacing: 8) {
				Text("Account password")
					.font(.system(size: 13))
					.foregroundStyle(Theme.label)
				Text("Checked against your account before it's stored.")
					.font(.system(size: 11))
					.foregroundStyle(Theme.secondaryLabel)

				HStack(spacing: 8) {
					SecureField("Required", text: $passwordEntry)
						.textFieldStyle(.plain)
						.font(.system(size: 13))
						.padding(.horizontal, 14)
						.padding(.vertical, 9)
						.background {
							Capsule()
								.fill(Theme.surfaceRaised)
								.overlay(
									Capsule().strokeBorder(Theme.cardHighlight, lineWidth: 1))
						}
					Button("Store") { storePassword() }
						.buttonStyle(AccentButtonStyle())
						.disabled(passwordEntry.isEmpty)
						.fixedSize()
				}
			}
			.padding(Theme.rowPadding)
			if let passwordError {
				StatusPill(kind: .error, message: passwordError)
			}
		}
	}

	// MARK: - Security

	private var securitySection: some View {
		SettingsSection(title: "Security") {
			SettingToggle(
				title: "Only trust the built-in camera",
				detail: "Refuses virtual and external cameras.",
				symbol: "camera.fill",
				isOn: bind(\.requireBuiltInCamera))

			RowDivider()
			SettingToggle(
				title: "Check for spoofing",
				detail: Liveness.isAvailable
					? "Rejects photos held up to the camera."
					: "No anti-spoof model installed.",
				symbol: "eye.trianglebadge.exclamationmark.fill",
				isEnabled: Liveness.isAvailable,
				isOn: bind(\.livenessEnabled))

			RowDivider()
			SettingToggle(
				title: "Require Touch ID for changes",
				detail: BiometricGate.isAvailable
					? "Confirms it's you before making changes here."
					: "This Mac has no Touch ID sensor.",
				symbol: "touchid",
				isEnabled: BiometricGate.isAvailable,
				isOn: bind(\.touchIDFallback))

			RowDivider()
			SettingToggle(
				title: "Open at login",
				detail: LoginItem.needsApproval
					? "Approve Face ID in System Settings › General › Login Items."
					: "Face ID only watches for your screen locking while it's running.",
				symbol: "power",
				isOn: Binding(
					get: { LoginItem.isEnabled },
					set: { LoginItem.setEnabled($0) }))

			RowDivider()
			SettingToggle(
				title: "Tamper protection",
				detail: "Asks for an administrator password before quitting.",
				symbol: "lock.shield.fill",
				isOn: bind(\.tamperProtection))
		}
	}

	// MARK: - Updates

	private var updatesSection: some View {
		SettingsSection(
			title: "Updates",
			footer: "Your settings and enrolled face survive a rebuild."
		) {
			SettingRow(
				title: "Version \(updates.currentVersion)",
				detail: updateDetail,
				symbol: "arrow.trianglehead.2.clockwise"
			) {
				Button(updateButtonTitle) { updateAction() }
					.buttonStyle(AccentButtonStyle())
					.disabled(updates.state == .checking || updates.state == .pulling)
			}

			if case .pulled = updates.state {
				RowDivider()
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

	// MARK: - Manage

	private var manageSection: some View {
		SettingsSection(
			title: "Enrolled Face",
			footer: store.embedder.identifier.hasPrefix("landmark")
				? "No recognition model is installed, so Face ID is matching face geometry only. "
					+ "That tells you from a stranger but is much weaker than a trained model."
				: nil
		) {
			SettingRow(
				title: "Recognition model",
				detail: store.embedder.identifier,
				symbol: "brain.head.profile"
			) {
				EmptyView()
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
