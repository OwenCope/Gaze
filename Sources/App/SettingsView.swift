import SwiftUI

/// The panes in the sidebar.
///
/// Three, not six. Six meant a sidebar where most panes held a single group — clicking
/// around to find one switch, with the window mostly empty whichever one you landed on.
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
		case .general: return "gearshape.fill"
		case .face: return "faceid"
		case .credits: return "heart.fill"
		case .about: return "info"
		}
	}

	/// The pane header draws much larger than the sidebar tile, and not every symbol
	/// survives the scale. `info` is a bare lowercase i — inside a 24pt tile it reads as the
	/// familiar ⓘ because the tile supplies the enclosure, but at 34pt on open background it
	/// is a stick with a dot over it.
	var headerSymbol: String {
		self == .about ? "info.circle" : symbol
	}

	/// Green for the app's own mark, neutral for everything else.
	///
	/// The one exception to monochrome icons, and it earns it: green means Gaze
	/// everywhere else in this app, so the row that *is* Gaze should carry it.
	var tint: Color {
		self == .face ? Theme.faceID : Theme.grey
	}

	/// One line under the pane's title, saying what the pane is for.
	var summary: String {
		switch self {
		case .general:
			return "How Gaze looks on the lock screen, and what it's allowed to do"
		case .face:
			return "Unlock your Mac by looking at it"
		case .credits:
			return "The people whose work this is built on"
		case .about:
			return "What this app is, and what it isn't"
		}
	}

	/// About sits apart from the panes you actually configure things in.
	var isPrecededBySeparator: Bool { self == .about }
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
		.background(WindowGlass(extraTranslucent: settings.appTheme == .glass))
		// Nil for "follow system", which is what following the system means — forcing a
		// scheme is the thing this setting exists to make optional.
		.preferredColorScheme(settings.appTheme.colorScheme)
		.onAppear { AppActivation.bringToFront() }
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	// MARK: - Sidebar

	private var sidebar: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element) { index, item in
				if item.isPrecededBySeparator {
					Rectangle()
						.fill(Theme.separator)
						.frame(height: 1)
						.padding(.horizontal, 10)
						.padding(.vertical, 7)
				}
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
		case .credits, .about:
			return nil
		}
	}

	// MARK: - Detail

	private var detail: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
				// The pane's own mark and a line saying what it is for.
				//
				// A bare word at the top of a column tells you which tab you clicked, which
				// you already knew. The icon carries the app's identity and the sentence
				// tells someone opening this for the first time what they are looking at.
				HStack(alignment: .top, spacing: 14) {
					Image(systemName: pane.headerSymbol)
						.font(Typography.glyph)
						.foregroundStyle(pane.tint)
						.frame(width: 44, height: 44)

					VStack(alignment: .leading, spacing: 2) {
						Text(pane.title)
							.font(Typography.paneTitle)
							.foregroundStyle(Theme.label)
						Text(pane.summary)
							.font(Typography.detail)
							.foregroundStyle(Theme.secondaryLabel)
							.fixedSize(horizontal: false, vertical: true)
					}
					Spacer(minLength: 0)
				}
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
					appearanceSection
				case .credits:
					creditsSection
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
					Text(store.isEnrolled ? "Gaze is set up" : "Gaze isn't set up")
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
						SetupRequest.begin()
						AppActivation.bringToFront()
						openWindow(id: "enrollment")
					} label: {
						Text(store.isEnrolled ? "Add a Face" : "Set Up Gaze")
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
			return "Your enrolled face couldn't be read and has been ignored"
		}
		switch store.faces.count {
		case 0: return "Enroll your face to unlock this Mac by looking at it"
		case 1: return "One face can open this Mac"
		default: return "\(store.faces.count) faces can open this Mac"
		}
	}

	/// The enrolled faces, one row each.
	///
	/// A list rather than a single "Remove enrolled face" button, because there can
	/// be several now. The footer is the important part: every face here opens
	/// *this* account with *this* password, so a second face is not a second user —
	/// it is giving somebody your login. That has to be said where faces are added,
	/// not buried in a document nobody opens.
	private var manageSection: some View {
		SettingsSection(
			title: store.faces.count == 1 ? "Enrolled face" : "Enrolled faces",
			footer: manageFooter
		) {
			// Tiles in a row, the way Touch ID & Password lists fingerprints.
			//
			// Apple has already answered this exact question — several enrolments of
			// the same biometric, each named, added and removed — and the answer is
			// not a list of rows. A tile is the size of the thing it represents, the
			// name sits under it where a name belongs, and adding one is a tile in the
			// same row rather than a button somewhere else in the pane.
			HStack(alignment: .top, spacing: 16) {
				ForEach(store.faces) { face in
					FaceTile(
						face: face,
						rename: { store.rename(face.id, to: $0) },
						remove: {
							Task {
								guard await BiometricGate.authorize(.removeEnrollment) else { return }
								store.remove(face.id)
							}
						})
				}

				if store.canAddFace {
					AddFaceTile {
						SetupRequest.begin()
						AppActivation.bringToFront()
						openWindow(id: "enrollment")
					}
				}

				Spacer(minLength: 0)
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 16)
		}
	}

	private var manageFooter: String {
		var lines: [String] = []
		if store.faces.count > 1 {
			lines.append(
				"Any of these faces unlocks this Mac with your password. "
					+ "They are not separate accounts.")
		}
		if !store.canAddFace {
			lines.append("Gaze holds up to \(FaceEnrollmentStore.maximumFaces) faces.")
		}
		if store.embedder.identifier.hasPrefix("landmark") {
			lines.append(
				"No recognition model is installed, so Gaze is matching face geometry only. "
					+ "That tells you from a stranger but is much weaker than a trained model.")
		}
		return lines.joined(separator: " ")
	}

	// MARK: - Lockout

	private var lockoutSection: some View {
		SettingsSection(
			title: "Locked out",
			footer: "Gaze is disabled after \(LockoutManager.maxAttempts) failed attempts."
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
		SettingsSection(title: "Use Gaze for", footer: unlockFooter) {
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
				detail: "Checked against your account before it's stored",
				symbol: "key.fill"
			) {
				HStack(spacing: 6) {
					SettingsField(placeholder: "Required", text: $passwordEntry)
						.frame(width: 140)
					Button("Store") { storePassword() }
						.buttonStyle(.accent)
						.disabled(passwordEntry.isEmpty)
						.fixedSize()

					// The answer where the question gets asked.
					//
					// "How is my password stored?" is the first thing anyone security-minded
					// wants to know, and it was only answered in a file on GitHub. It belongs
					// at the field you type the password into, at the moment you are deciding
					// whether to.
					InfoButton(title: "How your password is stored") {
						Text(
							"It's encrypted with a key generated inside this Mac's Secure "
								+ "Enclave, which never leaves it. Copied to another Mac, the "
								+ "stored file is useless."
						)
						Text(
							"It is not hashed. The app has to reproduce your exact password in "
								+ "order to type it, so it keeps something it can decrypt — and "
								+ "anything running as your user account could decrypt it too. "
								+ "Your face decides when it gets typed; it isn't part of the "
								+ "encryption."
						)
						Text(
							"Choose \"Just recognise me\" instead and no password is asked for "
								+ "or stored at all."
						)
					}
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
	/// hard Gaze is to fool, and how the app behaves on this Mac. Splitting them is also
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
				// documented as Gaze identity only. A power button is not Gaze.
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
			notes.append("Approve Gaze in System Settings › General › Login Items.")
		}
		notes.append("Gaze only watches for your screen locking while it's running.")
		return notes.joined(separator: " ")
	}

	// MARK: - Appearance

	/// The app's own look, at the foot of the pane.
	///
	/// Last on purpose: everything above it configures what Gaze *does*, and this
	/// configures what the window you are reading is made of. It is the one setting whose
	/// effect you can see the instant you change it, so it does not need to be found first.
	private var appearanceSection: some View {
		SettingsSection(
			title: "Appearance",
			footer: settings.appTheme == .glass
				? "The same material as the notch panel: dark at the top, thinning to clear at "
					+ "the bottom. Always dark, since the gradient is."
				: "Applies to this window. Setup and the recognition test stay dark so the "
					+ "camera preview has a neutral surround, and the lock screen panel has "
					+ "its own Style above."
		) {
			SettingRow(title: "Theme", symbol: "circle.lefthalf.filled") {
				Picker("", selection: $settings.appTheme) {
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

	// MARK: - Updates

	private var updatesSection: some View {
		SettingsSection(
			title: "Updates",
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
			// No second identity block.
			//
			// This pane used to open with a centred glyph, the app's name and its version in
			// a card of its own — directly beneath a header carrying the same glyph and the
			// same name. Two of them stacked, and the card was mostly empty space. The facts
			// are facts; they belong in rows.
			SettingsSection(title: "This app") {
				SettingRow(title: "Version") {
					Text(updates.currentVersion)
						.font(Typography.control)
						.foregroundStyle(Theme.secondaryLabel)
				}
				RowDivider(inset: Theme.rowInset)
				SettingRow(title: "Recognition model") {
					Text(store.embedder.identifier)
						.font(Typography.control)
						.foregroundStyle(Theme.secondaryLabel)
				}
			}

			// Said plainly, and said here rather than in a README nobody opens.
			//
			// atmos raised it in the server: the name invites people to assume this is what
			// an iPhone does, and it isn't. The built-in camera has no depth sensor, so the
			// honest version of this app's security claim has to be on its face.
			//
			// Text, not a row with a warning triangle. An orange hazard icon reads as
			// something having gone wrong; this is a permanent, unalarming fact about how the
			// hardware works, and dressing it as an error is its own kind of dishonesty.
			VStack(alignment: .leading, spacing: 6) {
				Text("Not Apple's Face ID")
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				Text(
					"Apple's Face ID uses a TrueDepth camera that projects thousands of "
						+ "infrared dots to measure the shape of your face. Macs have no such "
						+ "sensor. This app recognises you from the ordinary built-in camera, "
						+ "which sees a flat image — so it cannot tell a face from a good "
						+ "photograph of one the way an iPhone can."
				)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.horizontal, 4)

		}
	}

	// MARK: - Credits

	/// Its own pane rather than a group tucked under About.
	///
	/// Not ceremony: nearly everything specific about this app came from someone else — the
	/// recognition model, and most of what the settings window looks like. A line at the
	/// bottom of an About page is not where you put that.
	private var creditsSection: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection(
				title: "Built on other people's work",
				footer: "All three of them build Mac apps worth your time. Go and look at them."
			) {
				SettingRow(
					title: "cshariq",
					detail: "Sapphire — the recognition model this app matches faces with",
					symbol: "brain.head.profile"
				) {
					Button("Sapphire") { Self.open("https://sapphire-app.tech/") }
						.buttonStyle(AccentButtonStyle.quiet)
				}

				RowDivider()
				SettingRow(
					title: "Aviorrok",
					detail: "DynamicLake — the notch panel and this window follow its lead",
					symbol: "macbook"
				) {
					Button("DynamicLake") { Self.open("https://dynamiclake.com") }
						.buttonStyle(AccentButtonStyle.quiet)
				}

				RowDivider()
				SettingRow(
					title: "DanFQ",
					detail: "Atoll — and for reading this code more carefully than I did",
					symbol: "hammer.fill"
				) {
					Button("Atoll") { Self.open("https://getatoll.app") }
						.buttonStyle(AccentButtonStyle.quiet)
				}
			}

			// Plain text, not a group. An empty card with a caption under it is a group that
			// forgot to have any rows.
			VStack(alignment: .leading, spacing: 6) {
				Text("And everyone who said what was wrong")
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				Text(
					"The Discord picked apart every screenshot: the settings layout, light mode, "
						+ "what the notch panel should look like at rest, and what this app should "
						+ "not claim about itself. Most of it was right."
				)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.horizontal, 4)
		}
	}

	private static func open(_ address: String) {
		guard let url = URL(string: address) else { return }
		NSWorkspace.shared.open(url)
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
				IconTile(symbol: pane.symbol, tint: pane.tint)
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
		// "Gaze" pane was showing, which reads as the sidebar disagreeing with itself.
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

/// One enrolled face, as a tile.
///
/// Modelled on the fingerprint tiles in Touch ID & Password: the glyph is the
/// object, the name is under it and editable in place, and removal appears on
/// approach rather than sitting there as a permanent invitation to destroy
/// something.
private struct FaceTile: View {

	let face: FaceEnrollment
	var rename: (String) -> Void
	var remove: () -> Void

	@State private var hovering = false
	/// The name being typed, committed on Return or when focus leaves.
	///
	/// Bound straight through, every keystroke rewrote the vault and re-encrypted
	/// the whole record — and deleting the last character wrote an empty name that
	/// the store then rejected, so the field could not be cleared to retype.
	@State private var draft: String
	@FocusState private var isEditing: Bool

	init(face: FaceEnrollment, rename: @escaping (String) -> Void, remove: @escaping () -> Void) {
		self.face = face
		self.rename = rename
		self.remove = remove
		_draft = State(initialValue: face.name)
	}

	var body: some View {
		VStack(spacing: 8) {
			ZStack(alignment: .topTrailing) {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(Theme.faceID.opacity(0.16))
					.frame(width: 68, height: 68)
					.overlay {
						Image(systemName: "faceid")
							.font(.system(size: 30, weight: .regular))
							.foregroundStyle(Theme.faceID)
					}
					.overlay {
						RoundedRectangle(cornerRadius: 16, style: .continuous)
							.strokeBorder(Theme.faceID.opacity(0.28), lineWidth: 1)
					}

				if hovering {
					Button(action: remove) {
						Image(systemName: "minus.circle.fill")
							.font(.system(size: 17))
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, Theme.danger)
					}
					.buttonStyle(.plain)
					.help("Remove this face")
					.offset(x: 7, y: -7)
					.transition(.scale.combined(with: .opacity))
				}
			}
			.animation(.easeOut(duration: 0.15), value: hovering)

			TextField("Name", text: $draft)
				.textFieldStyle(.plain)
				.font(Typography.detail)
				.foregroundStyle(Theme.label)
				.multilineTextAlignment(.center)
				.lineLimit(1)
				.frame(width: 84)
				.focused($isEditing)
				.onSubmit(commit)
				.onChange(of: isEditing) { _, editing in if !editing { commit() } }
				// Someone else's edit — a rename from another window, or the record
				// reloading — should show here rather than being overwritten by a
				// draft the user never touched.
				.onChange(of: face.name) { _, name in if !isEditing { draft = name } }
		}
		.onHover { hovering = $0 }
	}

	private func commit() {
		let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
		// An empty name is a slip, not an instruction. Put the old one back rather
		// than leaving a tile with no label under it.
		guard !trimmed.isEmpty else {
			draft = face.name
			return
		}
		guard trimmed != face.name else { return }
		rename(trimmed)
	}
}

/// The tile that starts another enrolment.
///
/// In the row with the faces, not off in a corner of the pane: adding one is the
/// same kind of act as removing one, and Touch ID puts its "Add Fingerprint" in
/// exactly this position.
private struct AddFaceTile: View {

	var action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			VStack(spacing: 8) {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.strokeBorder(
						Theme.secondaryLabel.opacity(hovering ? 0.55 : 0.3),
						style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
					.frame(width: 68, height: 68)
					.overlay {
						Image(systemName: "plus")
							.font(.system(size: 22, weight: .medium))
							.foregroundStyle(Theme.secondaryLabel)
					}

				Text("Add a Face")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.lineLimit(1)
					.frame(width: 84)
			}
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.15), value: hovering)
	}
}
