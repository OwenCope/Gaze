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
				Circle()
					.fill(Theme.accent.opacity(0.14))
					.frame(width: 84, height: 84)
				Image(systemName: "faceid")
					.font(.system(size: 40, weight: .light))
					.foregroundStyle(Theme.accent)
			}

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

			Button(store.isEnrolled ? "Set Up Again" : "Set Up Face ID") {
				AppActivation.bringToFront()
				openWindow(id: "enrollment")
			}
			.buttonStyle(AccentButtonStyle())
		}
		.frame(maxWidth: .infinity)
		.padding(.bottom, 4)
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
						.frame(width: 150)
						.padding(.horizontal, 9)
						.padding(.vertical, 5)
						.background(Theme.surfaceRaised)
						.clipShape(.rect(cornerRadius: 7))
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
						.padding(.horizontal, 9)
						.padding(.vertical, 6)
						.background(Theme.surfaceRaised)
						.clipShape(.rect(cornerRadius: 7))
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
				detail:
					"Refuses virtual and external cameras. Without this, software that feeds a "
					+ "recording into the video pipeline can unlock your Mac.",
				isOn: bind(\.requireBuiltInCamera))

			RowDivider()
			SettingToggle(
				title: "Check for spoofing",
				detail: Liveness.isAvailable
					? "Rejects photos and screens held up to the camera. Adds a moment to each unlock."
					: "Needs an anti-spoof model at Resources/Liveness.mlpackage. None is installed.",
				isEnabled: Liveness.isAvailable,
				isOn: bind(\.livenessEnabled))

			RowDivider()
			SettingToggle(
				title: "Require Touch ID for changes",
				detail: BiometricGate.isAvailable
					? "Confirms it's you before removing your face or storing a password."
					: "This Mac has no Touch ID sensor.",
				isEnabled: BiometricGate.isAvailable,
				isOn: bind(\.touchIDFallback))

			RowDivider()
			SettingToggle(
				title: "Open at login",
				detail: LoginItem.needsApproval
					? "Approve Face ID in System Settings › General › Login Items."
					: "Face ID only watches for your screen locking while it's running.",
				isOn: Binding(
					get: { LoginItem.isEnabled },
					set: { LoginItem.setEnabled($0) }))

			RowDivider()
			SettingToggle(
				title: "Tamper protection",
				detail:
					"Requires administrator authentication to quit Face ID. An administrator can "
					+ "still remove the app, and force-quitting bypasses this entirely.",
				isOn: bind(\.tamperProtection))
		}
	}

	// MARK: - Updates

	private var updatesSection: some View {
		SettingsSection(
			title: "Updates",
			footer: "Your settings and enrolled face are kept across updates, as long as "
				+ "the new build is signed with the same certificate."
		) {
			SettingRow(
				title: "Version \(updates.currentVersion)",
				detail: updateDetail
			) {
				Button(updateButtonTitle) {
					switch updates.state {
					case .available:
						updates.openLatest()
					default:
						Task { await updates.check() }
					}
				}
				.buttonStyle(AccentButtonStyle())
				.disabled(updates.state == .checking)
			}
		}
	}

	private var updateDetail: String {
		switch updates.state {
		case .idle: return "Check whether a newer build has been released."
		case .checking: return "Checking…"
		case .upToDate: return "You're on the latest release."
		case .available(let version, _): return "Version \(version) is available."
		case .failed(let message): return message
		}
	}

	private var updateButtonTitle: String {
		if case .available = updates.state { return "View Release" }
		return "Check"
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
				detail: store.embedder.identifier
			) {
				EmptyView()
			}
			RowDivider()
			SettingRow(title: "Remove enrolled face") {
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
