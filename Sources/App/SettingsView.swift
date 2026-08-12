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
			detail
		}
		// A floor, not a fixed size.
		//
		// The window was pinned at exactly 700×540 and non-resizable, which meant a user who
		// found the text small had no recourse, and a long string — a localised footer, a
		// camera driver's error message — had nowhere to go but the clip. System Settings
		// resizes; so does this now.
		.frame(
			minWidth: 660, idealWidth: 700, maxWidth: .infinity,
			minHeight: 480, idealHeight: 560, maxHeight: .infinity)
		// One sheet of glass, dense at the top and thinning as it falls.
		//
		// No divider between sidebar and detail, and no separate scrim on each: a hairline
		// with two different fills either side is what cut the window into a "web app with a
		// sidebar". On one unbroken sheet, the sidebar is just the left margin of the glass —
		// the way the Siri panel and Spotlight treat their edges.
		.background(WindowGlass())
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	// MARK: - Sidebar

	private var sidebar: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element) { index, item in
				SidebarItem(
					pane: item,
					isSelected: pane == item,
					badge: badge(for: item),
					select: { pane = item })
					// ⌘1/⌘2/⌘3, the way every Mac app with tabbed preferences switches
					// panes. The sidebar was mouse-only before this.
					.keyboardShortcut(
						KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
			}
			Spacer(minLength: 0)
		}
		// Arrow keys once the sidebar has focus, matching a real source list.
		.onMoveCommand { direction in
			guard let current = SettingsPane.allCases.firstIndex(of: pane) else { return }
			switch direction {
			case .up where current > 0:
				pane = SettingsPane.allCases[current - 1]
			case .down where current < SettingsPane.allCases.count - 1:
				pane = SettingsPane.allCases[current + 1]
			default:
				break
			}
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Settings panes")
		.padding(.horizontal, 9)
		// Clears the traffic lights, which sit over the sidebar on a hidden title bar.
		.padding(.top, 38)
		.padding(.bottom, 12)
		.frame(width: 168)
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
					.font(Typography.paneTitle)
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
					behaviourSection
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
		// Not `.never`.
		//
		// Hiding the indicator on a pane that scrolls removes the only thing telling the
		// user there is more below the fold — on the General pane there are two groups under
		// it. `.automatic` keeps it out of the way until the content actually moves, which
		// is the behaviour it was presumably reaching for.
		.scrollIndicators(.automatic)
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
				.font(Typography.glyph)
				.foregroundStyle(heroTint)
				.frame(width: 42)
				.animation(.easeOut(duration: 0.25), value: store.isEnrolled)

				VStack(alignment: .leading, spacing: 3) {
					Text(store.isEnrolled ? "Face ID is set up" : "Face ID isn't set up")
						.font(Typography.heroTitle)
						.foregroundStyle(Theme.label)
					Text(heroDetail)
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}

				Spacer(minLength: 8)

				// Equal widths.
				//
				// Two right-aligned buttons whose labels differ in length — "Set Up Again"
				// over "Test Recognition" — left a ragged left edge between them. Matching
				// their widths is what makes them read as a pair.
				VStack(alignment: .trailing, spacing: 6) {
					Button {
						AppActivation.bringToFront()
						openWindow(id: "enrollment")
					} label: {
						Text(store.isEnrolled ? "Set Up Again" : "Set Up Face ID")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(store.isEnrolled ? .accent : .primaryAction)

					if store.isEnrolled {
						Button {
							AppActivation.bringToFront()
							openWindow(id: "test")
						} label: {
							Text("Test Recognition").frame(maxWidth: .infinity)
						}
						.buttonStyle(.quiet)
					}
				}
				.frame(width: 132)
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
			// The recognition model used to be a row here. Nebulark's point in the server was
			// that nobody outside the project can act on `coreml:112x112` — it is a build
			// detail taking up space in the pane you actually use. It lives in About now.
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
				.buttonStyle(AccentButtonStyle.destructive)
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
						.buttonStyle(.accent)
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
				StatusLine(kind: problem.kind, message: problem.message)
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

	private var passwordRow: some View {
		VStack(spacing: 0) {
			SettingRow(
				title: "Account password",
				detail: "Checked against your account before it's stored.",
				symbol: "key.fill"
			) {
				HStack(spacing: 6) {
					SettingsField(placeholder: "Required", text: $passwordEntry)
						.frame(width: 140)
					Button("Store") { storePassword() }
						.buttonStyle(.accent)
						.disabled(passwordEntry.isEmpty)
						.fixedSize()
				}
			}
			if let passwordError {
				StatusLine(kind: .error, message: passwordError)
			}
		}
	}

	// MARK: - Security

	/// Two groups, not one.
	///
	/// Five switches under a single unlabelled heading mixed two different questions — how
	/// hard Face ID is to fool, and how the app behaves on this Mac. Splitting them is also
	/// what lets the icon colours mean something: the first group is the hardening group and
	/// reads as one family, the second is plumbing and stays grey.
	private var securitySection: some View {
		SettingsSection(title: "Hardening", footer: securityFooter) {
			SettingToggle(
				title: "Only trust the built-in camera",
				symbol: "camera.fill",
				isOn: bind(\.requireBuiltInCamera))

			RowDivider()
			SettingToggle(
				title: "Reject photos held up to the camera",
				symbol: "eye.trianglebadge.exclamationmark.fill",
				isEnabled: Liveness.isAvailable,
				isOn: bind(\.livenessEnabled))

			RowDivider()
			SettingToggle(
				title: "Require Touch ID for changes here",
				// Pink because Apple's own Touch ID icon is pink, not because a fifth hue
				// was needed. Every tint in this window now points at a System Settings row
				// that uses the same one.
				symbol: "touchid",
				isEnabled: BiometricGate.isAvailable,
				isOn: bind(\.touchIDFallback))
		}
	}

	private var behaviourSection: some View {
		SettingsSection(title: "This Mac", footer: behaviourFooter) {
			SettingToggle(
				title: "Open at login",
				// Grey, like Login Items in System Settings — and because `Theme.faceID` is
				// documented as Face ID identity only. A power button is not Face ID.
				symbol: "power",
				isOn: Binding(
					get: { LoginItem.isEnabled },
					set: { LoginItem.setEnabled($0) }))

			RowDivider()
			SettingToggle(
				title: "Ask for a password before quitting",
				symbol: "lock.fill",
				isOn: bind(\.tamperProtection))
		}
	}

	/// Only the caveats. Rows that work as expected need no sentence explaining that they do.
	///
	/// Nil rather than empty when there is nothing to say — an empty footer still reserved
	/// its leading and its line height, which left an unexplained gap under the group.
	private var securityFooter: String? {
		var notes: [String] = []
		if !Liveness.isAvailable { notes.append("No anti-spoof model is installed.") }
		if !BiometricGate.isAvailable { notes.append("This Mac has no Touch ID sensor.") }
		return notes.isEmpty ? nil : notes.joined(separator: " ")
	}

	private var behaviourFooter: String {
		var notes: [String] = []
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
				symbol: "arrow.trianglehead.2.clockwise"
			) {
				Button(updateButtonTitle) { updateAction() }
					.buttonStyle(.accent)
					.disabled(updates.state == .checking || updates.state == .pulling)
			}

			if case .pulled = updates.state {
				RowDivider(inset: 0)
				StatusLine(
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
						.font(Typography.glyphLarge)
						.foregroundStyle(Theme.faceID)
					Text("Face ID")
						.font(Typography.heroTitle)
						.foregroundStyle(Theme.label)
					Text("Version \(updates.currentVersion)")
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 22)
			}

			// Said plainly, and said here rather than in a README nobody opens.
			//
			// atmos raised it in the server: the name invites people to assume this is what
			// an iPhone does, and it isn't. The built-in camera has no depth sensor, so the
			// honest version of this app's security claim has to be on its face.
			SettingsSection(
				title: "What this is",
				footer: "Apple's Face ID uses a TrueDepth camera that projects thousands of "
					+ "infrared dots to measure the shape of your face. Macs have no such "
					+ "sensor. This app recognises you from the ordinary built-in camera, "
					+ "which sees a flat image — so it cannot tell a face from a good "
					+ "photograph of one the way an iPhone can."
			) {
				SettingRow(
					title: "Not Apple's Face ID",
					detail: "Built-in camera, no depth sensor.",
					symbol: "exclamationmark.triangle.fill", symbolTint: Theme.warning
				) {
					EmptyView()
				}
				RowDivider()
				SettingRow(title: "Recognition model", symbol: "brain.head.profile") {
					Text(store.embedder.identifier)
						.font(Typography.control)
						.foregroundStyle(Theme.secondaryLabel)
				}
			}

			SettingsSection(title: "Thanks") {
				SettingRow(
					title: "DanFQ",
					detail: "Sapphire, whose recognition model this uses.",
					symbol: "heart.fill"
				) {
					Button("Visit") {
						if let url = URL(string: "https://sapphire-app.tech/") {
							NSWorkspace.shared.open(url)
						}
					}
					.buttonStyle(AccentButtonStyle.quiet)
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
	@FocusState private var isFocused: Bool

	var body: some View {
		Button(action: select) {
			HStack(spacing: 9) {
				IconTile(symbol: pane.symbol)
				Text(pane.title)
					.font(Typography.row)
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
							? Theme.selection
							: (isHovering ? Theme.hoverFill : .clear))
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		// Only the selected row takes focus, so the ring and the highlight are never on two
		// different rows. Making all three focusable put the ring on "General" while the
		// "Face ID" pane was showing, which reads as the sidebar disagreeing with itself.
		.focusable(isSelected)
		.focused($isFocused)
		// AppKit's blue ring on top of the white one drawn above — two rings around one row,
		// and a colour this window otherwise never uses.
		.focusEffectDisabled()
		.onHover { isHovering = $0 }
		// Without this a screen reader announces three unrelated buttons and never says
		// which pane is showing.
		.accessibilityLabel(pane.title)
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
		.accessibilityValue(badge == nil ? "" : "Needs attention")
	}
}
