import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
	case face, notch, general, about, credits

	static let toolbarPanes: [Self] = [.face, .notch, .general, .about]

	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: return "General"
		case .notch: return "Notch"
		case .face: return "Unlock"
		case .credits: return "Credits"
		case .about: return "About"
		}
	}

	var symbol: String {
		switch self {
		case .general: return "gearshape"
		case .notch: return "macbook"
		case .face: return "faceid"
		case .credits: return "heart.fill"
		case .about: return "info.circle"
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
	/// All one colour. Green means "recognised" everywhere else in the app; spending it on
	/// a sidebar row that is simply *labelled* Gaze diluted that, and made the row look
	/// selected when it wasn't (Jis' note). The sidebar icons are a shape to scan by, not a
	/// palette.
	var tint: Color {
		Theme.grey
	}

	/// One line under the pane's title, saying what the pane is for.
	var summary: String {
		switch self {
		case .general:
			return "How Gaze behaves on this Mac, and how it keeps itself up to date"
		case .notch:
			return "How the panel under the notch looks"
		case .face:
			return "Unlock your Mac by looking at it — and what that's allowed to do"
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

	/// The width of the settings column, matching System Settings' own detail measure.
	/// Wider than this and a row's label and its control stop reading as one row.
	private static let contentWidth: CGFloat = 620

	let store: FaceEnrollmentStore
	let lockout: LockoutManager

	/// `--settings-pane=general|face|credits|about` opens straight onto one pane.
	///
	/// Same reason as `--setup-step`: working on a pane, or photographing one, otherwise
	/// means clicking to it after every rebuild.
	@State private var pane: SettingsPane = {
		guard
			let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--settings-pane=") }),
			let name = argument.split(separator: "=").last,
			let pane = SettingsPane(rawValue: String(name))
		else { return .face }
		return pane
	}()
	@State private var settings = Preferences.shared
	@State private var updates = UpdateChecker.shared
	@State private var releases = ReleaseUpdateChecker.shared
	@State private var passwordEntry = ""
	@State private var passwordError: String?
	/// Whether a password is stored, re-read whenever this window comes forward.
	///
	/// `@State` initialises once, and until "Change" existed that was harmless: the only
	/// things that could store or revoke a password were the two buttons in this row, and
	/// both set this themselves. "Change" hands the job to the setup window, so the password
	/// can now change while Settings is sitting behind it — and the row would still be
	/// showing whatever was true when the window opened, offering to store a password that
	/// is already stored.
	@State private var hasStoredPassword = PasswordVault.hasPassword
	@State private var lockoutPassword = ""
	@State private var lockoutError: String?
	@State private var accessibilityGranted = SetupPermissionStatus.current.isReady
	@State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
	@State private var loginItemEnabled = LoginItem.isEnabled
	@State private var loginItemNeedsApproval = LoginItem.needsApproval
	@State private var loginItemError: String?
	@State private var loginItemFailedRequest: Bool?
	/// The settings search field. Blank means no search: the panes show as before.
	@State private var searchQuery = ""
	@State private var pauseExpiryRevision = 0
	/// The section a search result asked to reveal.
	///
	/// Set together with the destination pane and the cleared query; a `.task(id:)`
	/// on the detail scroll view scrolls to it after layout, then clears it.
	/// Navigation only — it never reads the vault or flips a setting.
	@State private var pendingSearchSection: SettingsSearchItem?

	@Environment(\.openWindow) private var openWindow

	var body: some View {
		let _ = pauseExpiryRevision
		Group {
			// A search replaces the panes while it is nonempty, rather than filtering
			// rows in savedApp: the panes are per-subject groups, and a filtered
			// subset of rows would orphan controls from the footers that explain them.
			if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				detail
			} else {
				searchResults
			}
		}
			.searchable(text: $searchQuery, placement: .toolbar, prompt: "Find a setting")
			.onChange(of: pane) { _, _ in searchQuery = "" }
			.onSubmit(of: .search) {
				if let first = SettingsSearchItem.results(for: searchQuery).first {
					selectSearchResult(first)
				}
			}
			// The pane switcher lives in the window's toolbar, which is where macOS puts
			// one. `.principal` centres it between the traffic lights and the trailing
			// edge — the same slot Finder's view switcher and Xcode's segmented controls
			// use — and AppKit owns the glass, the height and the scroll-edge behaviour.
			.toolbar {
				ToolbarItem(placement: .principal) {
					GazeSettingsPicker(selection: $pane)
						.fixedSize()
				}
			}
		// A floor, not a fixed size.
		//
		// The window was pinned at exactly 700×540 and non-resizable, which meant a user who
		// found the text small had no recourse, and a long string — a localised footer, a
		// camera driver's error message — had nowhere to go but the clip. System Settings
		// resizes; so does this now.
		//
		// `maxWidth: .infinity`, and it has to be — a `maxWidth: 920` here was a real bug.
		//
		// This view *is* the window's content, and `WindowGlass` is its background. Capping
		// the view's width did not cap the window's: dragging past 920 left the view at 920
		// inside a wider window, and the strips either side of it had no view in them at
		// all. `VibrantBackground` sets `window.isOpaque = false` so the material can sample
		// the desktop, so those strips were not merely unpainted, they were see-through —
		// the window's left and right edges became holes onto the wallpaper.
		//
		// The reasonable thing the cap was reaching for — that a 620pt column of settings
		// gains nothing from a 1400pt window — is a limit on the *window*, not on its
		// content. Until it is one, filling is correct: whatever size the window is, the
		// glass reaches its edges.
		.frame(
			minWidth: 660, idealWidth: 720, maxWidth: .infinity,
			minHeight: 480, idealHeight: 600, maxHeight: .infinity)
		// One sheet of glass, dense at the top and thinning as it falls.
		//
		// No divider between panes and no separate scrim on each: a hairline with two
		// different fills either side is what cut the window into a "web app with a
		// sidebar". On one unbroken sheet the chrome is just the edge of the glass — the way
		// the Siri panel and Spotlight treat theirs.
		.background {
			// No `WallpaperBackdrop` here any more.
			//
			// It drew its own copy of the desktop picture inside the window, scaled to the
			// window rather than to the screen — so the wallpaper indoors never lined up
			// with the wallpaper outdoors. Move the window and the picture inside it stayed
			// put; the highlight sweeping across your desktop stopped dead at the window's
			// edge and a different, unrelated gradient carried on inside. That mismatch is
			// what read as fake, and no amount of tuning the scrims above it could fix it,
			// because the thing being tuned was a painting of a wallpaper rather than the
			// wallpaper.
			//
			// A window is made of glass by sampling what is actually behind it, which is
			// `.behindWindow` blending and nothing else. It costs the wallpaper being
			// visible when the window sits over other windows — over a dark app the glass
			// goes dark — but that is what glass does, and it is what every system window
			// on macOS does.
			//
			// `keepsTitle` because the window has a title bar again: `WindowGlass` reaches
			// into the host `NSWindow` and hides it, which was correct while the switcher
			// was drawn in the content view, and would now take the toolbar down with it.
			WindowGlass(keepsTitle: true, extraTranslucent: settings.appTheme == .glass)
		}
		// Nil for "follow system", which is what following the system means — forcing a
		// scheme is the thing this setting exists to make optional.
		.preferredColorScheme(settings.appTheme.colorScheme)
		.onAppear {
			AppActivation.bringToFront()
			refreshExternalState()
		}
		// Both of these can be changed outside this window — the password by the setup flow
		// that "Change" opens, Accessibility in System Settings — and neither sends a
		// notification of its own. Coming back to the app is the moment to ask again.
		.onReceive(
			NotificationCenter.default.publisher(
				for: NSApplication.didBecomeActiveNotification)
		) { _ in
			refreshExternalState()
		}
		.task(id: settings.pausedUntil) {
			guard let until = settings.pausedUntil, until > Date() else { return }
			do { try await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow))) }
			catch { return }
			// Pause expiry changes with time, without changing the stored preference.
			pauseExpiryRevision &+= 1
		}
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}

	// MARK: - Detail

	private var detail: some View {
		ScrollViewReader { proxy in
			ScrollView {
			VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
				// No page header here any more.
				//
				// It was a 44pt tinted glyph, the pane's name, and a sentence describing it,
				// stacked above every pane. The name duplicated the toolbar segment that was
				// already lit to say the same word, and the glyph duplicated the symbol on
				// that segment — so two thirds of it restated the control the user had just
				// clicked. System Settings has no such header for the same reason.
				//
				// The sentence was the one part carrying information, and it has moved to
				// where it applies: a `footer` on the first group of each pane, which is
				// where macOS puts explanatory prose.
				switch pane {
				// Everything about unlocking with your face, in the order it becomes
				// relevant: whether it works, whose face it knows, what it does when it
				// recognises you, what it needs permission to do that, and how strict it
				// is about accepting you.
				//
				// Permissions and Hardening used to sit on General, which put the camera
				// permission three panes away from the camera and the anti-spoof switch
				// nowhere near the faces it accepts or rejects. They were on General for the
				// same reason everything was: General was where anything went that was not
				// obviously a face. That left it carrying five groups while this pane carried
				// three, and split one subject across two panes.
				case .face:
					if lockout.isLockedOut { lockoutSection }
					hero.id("hero")
					if store.isEnrolled { manageSection }
					unlockSection.id("unlockSection")
					permissionsSection.id("permissionsSection")
					securitySection.id("securitySection")
				case .general:
					behaviourSection.id("behaviourSection")
					appearanceSection.id("appearanceSection")
					updatesSection.id("updatesSection")
					onboardingSection.id("onboardingSection")
				case .notch:
					NotchSettingsSection(settings: settings).id("NotchSettingsSection")
				case .credits:
					creditsSection.id("creditsSection")
				case .about:
					aboutSection.id("aboutSection")
					DisclosureGroup("Credits & Acknowledgements") { creditsSection }
				}

				Spacer(minLength: 0)
			}
			// A measure, then centred — not stretched to whatever width the window is.
			//
			// The groups were pinned left at full width, so dragging the window wider pulled
			// every row's control away from its label until a switch could sit 600pt from
			// the word it belonged to, with the right half of the window empty. Settings
			// panes have a column width and keep it; the window growing gives you more rows
			// on screen, not wider ones.
			.frame(maxWidth: Self.contentWidth, alignment: .leading)
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 24)
			// The toolbar owns the traffic-light clearance now, so this is just the gap
			// under the glass rather than a hand-measured dodge around the buttons.
			.padding(.top, 20)
			.padding(.bottom, 24)
		}
		.scrollIndicators(.never)
			// Scrolls to a search result's section after the pane switch lays out,
			// so the anchor exists when it scrolls. Keyed by the destination rather
			// than delayed by a fixed interval; unanimated, and cleared on arrival.
			.task(id: pendingSearchSection?.id) {
				guard let target = pendingSearchSection else { return }
				proxy.scrollTo(target.section, anchor: .top)
				pendingSearchSection = nil
			}
		}
	}

	/// The search results, replacing the panes while the query is nonempty.
	///
	/// One restrained row per match — title and subtitle, nothing more. Each row
	/// only navigates: it switches to the result's pane, clears the query, and
	/// asks the detail scroll view to reveal the matching section. Selecting a
	/// result never reads the vault, toggles a setting, or opens a permission
	/// prompt or enrolment flow.
	private var searchResults: some View {
		let matches = SettingsSearchItem.results(for: searchQuery)
		return ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				if matches.isEmpty {
					Text("No settings match \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\".")
						.font(Typography.detail)
						.foregroundStyle(Theme.secondaryLabel)
						.padding(.horizontal, Theme.rowInset)
						.padding(.vertical, 14)
					Button("Clear search") { searchQuery = "" }
						.gazeButton()
						.padding(.horizontal, Theme.rowInset)
				} else {
					ForEach(matches) { item in
						Button { selectSearchResult(item) } label: {
							VStack(alignment: .leading, spacing: 3) {
								Text(item.title)
									.font(Typography.control)
									.foregroundStyle(Theme.label)
								Text(item.subtitle)
									.font(Typography.detail)
									.foregroundStyle(Theme.secondaryLabel)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, Theme.rowInset)
							.padding(.vertical, 10)
						}
						.buttonStyle(.plain)
						if item.id != matches.last?.id {
							RowDivider(inset: 0)
						}
					}
				}

				Spacer(minLength: 0)
			}
			.frame(maxWidth: Self.contentWidth, alignment: .leading)
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 24)
			.padding(.top, 20)
			.padding(.bottom, 24)
		}
		.scrollIndicators(.never)
	}

	private func selectSearchResult(_ item: SettingsSearchItem) {
		if let next = SettingsPane(rawValue: item.pane) { pane = next }
		searchQuery = ""
		pendingSearchSection = item
	}

	private func revealSettingsSection(_ section: String) {
		guard let item = SettingsSearchItem.all.first(where: { $0.pane == "face" && $0.section == section }) else { return }
		selectSearchResult(item)
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
				Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
					.resizable()
					.interpolation(.high)
					.frame(width: 42, height: 42)
					.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 3) {
					Text(heroTitle)
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
					if settings.isPaused {
						Button("Resume Gaze") { settings.resume() }
							.gazeButton(.primary, size: .large)
							.frame(maxWidth: .infinity)
					}
					if store.isEnrolled, !cameraGranted {
						Button("Review Permissions") { revealSettingsSection("permissionsSection") }
							.gazeButton(.primary, size: .large)
					} else if store.isEnrolled, !settings.isPaused, PasswordReplaySafety.isEnabled,
						settings.unlockBackend != .none, readinessProblem != nil {
						Button("Review Setup") {
							revealSettingsSection(accessibilityGranted ? "unlockSection" : "permissionsSection")
						}
						.gazeButton(.primary, size: .large)
					} else if !store.isEnrolled {
						Button {
							SetupRequest.beginOnboarding()
							AppActivation.bringToFront()
							openWindow(id: "enrollment")
						} label: {
							Text("Set Up Gaze")
								.frame(maxWidth: .infinity)
						}
						.gazeButton(.primary, size: .large)
						.disabled(!store.canAddFace)
						.help(store.canAddFace ? "Add your face to unlock this Mac" : "Remove an enrolled face before adding another")
					}

					if store.isEnrolled {
						Button {
							AppActivation.bringToFront()
							openWindow(id: "test")
						} label: {
							Text("Test Recognition").frame(maxWidth: .infinity)
						}
						.gazeButton(size: .large)
					}
				}
				.frame(width: 168)
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 14)
		}
	}

	private var onboardingSection: some View {
		SettingsSection(title: "Getting Started") {
			SettingRow(title: "Welcome to Gaze", detail: "Reopen the setup walkthrough.") {
				Button("Open Onboarding") {
					SetupRequest.beginOnboarding()
					AppActivation.bringToFront(userInitiated: true)
					openWindow(id: "enrollment")
				}
				.gazeButton()
			}
			RowDivider()
			SettingRow(title: "Movement guide", detail: "Preview the prompts with the camera off.") {
				Button("Open guide") {
					AppActivation.bringToFront(userInitiated: true)
					openWindow(id: "movement-guide")
				}
				.gazeButton()
			}
		}
	}

	private var heroTitle: String {
		if lockout.isLockedOut { return "Gaze is locked out" }
		if !store.isEnrolled { return "Set up Gaze" }
		if settings.isPaused { return "Gaze is paused" }
		if !cameraGranted { return "Camera access needed" }
		if !PasswordReplaySafety.isEnabled { return "Mac unlocking is off" }
		if settings.unlockBackend == .none { return "Recognition only" }
		if readinessProblem != nil { return "Unlock needs attention" }
		return "Gaze is ready"
	}

	private var heroDetail: String {
		if lockout.isLockedOut { return "Enter your account password below to enable Gaze again." }
		if store.isCorrupted { return "Your enrolled face couldn’t be read. Enroll it again." }
		if !store.isEnrolled { return "Add your face to get started." }
		if settings.isPaused, let until = settings.pausedUntil {
			return "Face recognition resumes at \(until.formatted(date: .omitted, time: .shortened)). You can resume it sooner here."
		}
		if !cameraGranted { return "Allow the camera so Gaze can recognise you." }
		if !PasswordReplaySafety.isEnabled { return "Enable Unlock my Mac to use face verification. Your password and Touch ID remain available." }
		if settings.unlockBackend == .none { return "Try Test Recognition below. Nothing runs on the lock screen in this mode." }
		if let problem = readinessProblem { return problem.message }
		return store.faces.count == 1 ? "Your face can unlock this Mac." : "Your enrolled faces can unlock this Mac."
	}

	/// The enrolled faces, one row each.
	///
	/// A list rather than a single "Remove enrolled face" button, because there can
	/// be several now. The footer is the important part: every face here opens
	/// *this* account with *this* password, so a second face is not a second user —
	/// it is giving somebody your login. That has to be said where faces are added,
	/// not buried in a document nobody opens.
	private var manageSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(store.faces.count == 1 ? "Enrolled face" : "Enrolled faces")
				.font(Typography.groupTitle)
				.foregroundStyle(Theme.secondaryLabel)
				.padding(.horizontal, 4)
			// Tiles in a row, the way Touch ID & Password lists fingerprints.
			//
			// Apple has already answered this exact question — several enrolments of
			// the same biometric, each named, added and removed — and the answer is
			// not a list of rows. A tile is the size of the thing it represents, the
			// name sits under it where a name belongs, and adding one is a tile in the
			// same row rather than a button somewhere else in the pane.
			HStack(alignment: .top, spacing: 12) {
				ForEach(store.faces) { face in
					// Touched so the tile redraws when a picture is chosen.
					//
					// Portraits live on disk rather than on `face`, and `portrait(for:)` is
					// a method, so calling it observes nothing — without this read the tile
					// would keep its initials until something else invalidated the body.
					// It was written as `portraitRevision >= 0 ? … : nil`, which did perform
					// the read but is unsigned and therefore always true, leaving a dead
					// branch the compiler rightly complained about.
					let _ = store.portraitRevision
					FaceTile(
						face: face,
						portrait: store.portrait(for: face.id),
						rename: { store.rename(face.id, to: $0) },
						setPortrait: { store.setPortrait($0, for: face.id) },
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
			.frame(maxWidth: .infinity)
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 8)
			if !manageFooter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				Text(manageFooter)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, 4)
			}
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
			VStack(spacing: 0) {
				SettingRow(
					title: "Account password",
					symbol: "exclamationmark.lock.fill", symbolTint: Theme.danger
				) {
					HStack(spacing: 6) {
						SettingsField(placeholder: "Required", text: $lockoutPassword)
							.frame(width: 140)
							.onChange(of: lockoutPassword) { _, value in
								if !value.isEmpty { lockoutError = nil }
							}
						Button("Unlock") { clearLockout() }
							.gazeButton()
							.disabled(lockoutPassword.isEmpty)
					}
				}
				if let lockoutError {
					StatusLine(kind: .error, message: lockoutError)
				}
			}
		}
	}

	/// Opens setup on one screen.
	///
	/// The password and permission screens are skipped during a normal run once they are
	/// satisfied, which is right the first time through and leaves them unreachable ever
	/// after. Settings is where someone goes looking for them, so Settings is what names
	/// them.
	private func openSetup(at step: SetupStep) {
		SetupRequest.begin(at: step)
		AppActivation.bringToFront()
		openWindow(id: "enrollment")
	}

	/// Re-reads the state this window shows but does not own.
	private func refreshExternalState() {
		hasStoredPassword = PasswordVault.hasPassword
		cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
		accessibilityGranted = SetupPermissionStatus.current.isReady
		refreshLoginItemState()
	}

	// MARK: - Unlocking

	private var unlockSection: some View {
		SettingsSection(title: "Unlocking",
			footer: settings.unlockBackend == .authPlugin ? unlockFooter : nil, info: unlockInfo) {
			SettingToggle(title: "Unlock my Mac",
				detail: !PasswordReplaySafety.isEnabled ? "Off — your Mac stays locked" : settings.unlockBackend == .keystroke
					? "Use face recognition on the lock screen"
					: "Off — your Mac stays locked",
				symbol: "faceid", symbolTint: Theme.faceID,
				isOn: Binding(get: { PasswordReplaySafety.isEnabled && settings.unlockBackend == .keystroke },
					set: { unlockBinding.wrappedValue = $0 ? .keystroke : .none }))
				.disabled(AppServices.isUIReview)

		if settings.unlockBackend == .keystroke {
			RowDivider()
			passwordRow
		}

		// A password stored under "Unlock my Mac" survives a step down to
		// recognition-only mode: switching modes never touches the vault. Say so
		// where it applies, with the same Change / Revoke actions — reusing them,
		// not re-enabling unlock. Gated on the `hasStoredPassword` state (re-read
		// whenever this window comes forward), never on a vault read at draw time.
		if settings.unlockBackend == .none, hasStoredPassword {
			RowDivider()
			retainedPasswordRow
		}

			if let problem = readinessProblem, PasswordReplaySafety.isEnabled || settings.unlockBackend == .authPlugin {
				RowDivider(inset: 0)
				StatusLine(kind: problem.kind, message: problem.message)
			}
		}
	}

	private var unlockBinding: Binding<UnlockBackendKind> {
		Binding(
			get: { settings.unlockBackend },
			set: {
				guard !AppServices.isUIReview else { return }
				PasswordReplaySafety.setEnabled($0 == .keystroke)
				settings.unlockBackend = $0
				// Apply immediately rather than at next launch.
				AppServices.shared.startUnlockTrigger()
			})
	}

	private var unlockInfo: String {
		"When enabled, Gaze enters your stored account password after verification. Password and Touch ID remain available. "
			+ "The password is stored on this Mac in recoverable form so Gaze can type it. Turning this off does not delete the stored password; use Revoke to remove it. "
			+ "Use Test Recognition to practice without unlocking anything."
			+ "\n\nLast lock-screen attempt: " + LockScanDiagnostics.shared.summary
	}

	/// Explains the selected option, and the plugin's removal when that is what is selected.
	private var unlockFooter: String? {
		if settings.unlockBackend == .authPlugin {
			return "Legacy authorization is disabled in this source, but existing installations are unchanged. "
				+ "Have an administrator review the installed components and Apple's lock-screen configuration separately."
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

	/// A stored password kept while recognition-only mode is selected.
	///
	/// Same state and same actions as the stored branch of `passwordRow` (Change
	/// opens the setup screen that verifies before saving; Revoke clears the vault
	/// through the existing `authorize(.storePassword)` path). Nothing here flips
	/// the backend back to keystroke, so automatic unlock stays off.
	private var retainedPasswordRow: some View {
		VStack(spacing: 0) {
			SettingRow(
				title: "Stored account password",
				detail: "Kept from Unlock my Mac. Gaze won't use it to unlock in this mode.",
				symbol: "key.fill"
			) {
				HStack(spacing: 6) {
					Label("Stored", systemImage: "checkmark.circle.fill")
						.font(.system(.callout, weight: .medium))
						.foregroundStyle(Theme.faceID)
					Button("Change") { openSetup(at: .password) }
						.gazeButton()
						.fixedSize()
					Button("Revoke", role: .destructive) { revokePassword() }
						.gazeButton()
						.fixedSize()
				}
			}
			if let passwordError {
				StatusLine(kind: .error, message: passwordError)
			}
		}
	}

	private var passwordRow: some View {
		VStack(spacing: 0) {
			SettingRow(
				title: "Account password",
				detail: hasStoredPassword
					? "Encrypted with a key from this Mac's Secure Enclave"
					: "Checked against your account before it's stored",
				symbol: "key.fill"
			) {
				HStack(spacing: 6) {
					// Once it's stored there's nothing to type — the field goes away and a
					// Revoke replaces Store. Leaving an editable field sitting there after
					// the password is saved was the confusing part (Jis' note): it looked
					// unsaved. Revoke clears it and brings the field back.
					if hasStoredPassword {
						Label("Stored", systemImage: "checkmark.circle.fill")
							.font(.system(.callout, weight: .medium))
							.foregroundStyle(Theme.faceID)
						// Change, not just Revoke.
						//
						// Revoke was the only way to a stored password, so changing one meant
						// deleting it first and typing the new one into a settings row with no
						// verification screen around it — and leaving the Mac with no stored
						// password in between. This opens the setup screen built for the job,
						// which checks the password against the account before saving it.
						Button("Change") { openSetup(at: .password) }
							.gazeButton()
							.fixedSize()
						Button("Revoke", role: .destructive) { revokePassword() }
							.gazeButton()
							.fixedSize()
					} else {
						SettingsField(placeholder: "Required", text: $passwordEntry)
							.frame(width: 140)
						Button("Store") { storePassword() }
							.gazeButton()
							.disabled(passwordEntry.isEmpty)
							.fixedSize()
					}

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
							"\"Just recognise me\" does not use an account password to unlock your Mac. "
								+ "Switching modes does not delete an existing password. Use Revoke and "
								+ "check that removal succeeds; saved autofill passwords are separate."
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
	/// What Gaze has been allowed to do, and a way to change it.
	///
	/// There was no such group. Both permissions were asked for once during setup and then
	/// never mentioned again — and because the setup flow skips a step whose answer is
	/// already on disk, the screen that asked for Accessibility became unreachable the
	/// moment it was granted. So the two things the app cannot work without had no status
	/// anywhere in the interface, and revoking one in System Settings left Gaze silently
	/// unable to type a password with nothing on screen saying why.
	///
	/// Refreshed when Settings appears or the app becomes active (see
	/// `refreshExternalState`): both can still be changed in System Settings while
	/// this window is open, so the rows show the last refresh rather than a live read.
	private var permissionsSection: some View {
		SettingsSection(
			title: "Permissions",
			info: "Gaze needs the camera to see you and Accessibility to type your password."
		) {
			SettingRow(
				title: "Camera",
				detail: cameraAccessGranted
					? "Allowed" : "Not allowed — Gaze can't see you",
				symbol: "camera.fill",
				symbolTint: cameraAccessGranted ? nil : Theme.warning
			) {
				Button("Open Settings") {
					openPrivacySettings("Privacy_Camera")
				}
				.gazeButton()
				.fixedSize()
			}

			RowDivider(inset: 0)
			SettingRow(
				title: "Accessibility",
				detail: accessibilityGranted
					? "Allowed" : "Not allowed — review Accessibility access",
				symbol: "accessibility",
				symbolTint: accessibilityGranted ? nil : Theme.warning
			) {
				Button("Review") { openSetup(at: .permission) }
					.gazeButton()
					.fixedSize()
			}
		}
	}

	/// Whether the camera has been granted, refreshed when Settings appears or the app becomes active.
	private var cameraAccessGranted: Bool {
		cameraGranted
	}

	private func openPrivacySettings(_ anchor: String) {
		guard
			let url = URL(
				string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
		else { return }
		NSWorkspace.shared.open(url)
	}

	private var securitySection: some View {
		SettingsSection(title: "Security checks", footer: securityFooter,
			info: "Choose which checks Gaze requires before unlocking. Movement verification asks for a random action each time. Password and Touch ID remain available on the lock screen.") {
			SettingToggle(
				title: "Only trust the built-in camera",
				detail: "Required for password release; the enrolled camera stays pinned",
				symbol: "camera.fill",
				isEnabled: settings.unlockBackend != .keystroke,
				isOn: Binding(get: { settings.unlockBackend == .keystroke || settings.requireBuiltInCamera },
					set: { settings.requireBuiltInCamera = $0 }))

			RowDivider()
			SettingToggle(
				title: "Reject photos held up to the camera",
				symbol: "eye.trianglebadge.exclamationmark.fill",
				isEnabled: SpoofDetector.isAvailable,
				isOn: bind(\.livenessEnabled))

			RowDivider()
			SettingRow(
				title: "Movements to unlock this Mac",
				detail: "One is quicker; two asks for another completed response",
				symbol: "figure.walk.motion"
			) {
				Menu {
					Picker("Movements to unlock this Mac", selection: $settings.unlockMovementCount) {
						ForEach(Preferences.UnlockMovementCount.allCases, id: \.self) { count in
							Text(count.title).tag(count)
						}
					}
					.pickerStyle(.inline)
				} label: {
					Text(settings.unlockMovementCount.title).lineLimit(1)
				}
				.menuStyle(.button)
				.buttonStyle(.glass)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.accessibilityLabel("Movements to unlock this Mac")
				.accessibilityValue(settings.unlockMovementCount.title)
				.fixedSize()
			}

			RowDivider()
			SettingRow(
				title: "Lock when I walk away",
				detail: "Checks for absence after 20 seconds without input",
				symbol: "figure.walk.departure"
			) {
				HStack(spacing: 8) {
					InfoButton(title: "How walk-away lock checks") {
						Text(
							"Opens the camera briefly after 20 seconds without keyboard or pointer input. "
								+ "Any face found counts as someone there, and the check ends."
						)
						Text(
							"While input stays idle, it checks again no more often than every 30 seconds. "
								+ "Any input restarts the 20-second wait."
						)
						Text(
							"Locks after four seconds of fresh no-face evidence. "
								+ "When an app keeps the display awake, checks pause."
						)
						Text(
							"Needs Camera and Accessibility access. If the camera cannot confirm absence, "
								+ "Gaze leaves the Mac unlocked. You can still lock it yourself."
						)
					}
					Toggle("Lock when I walk away", isOn: walkAwayBinding)
						.labelsHidden()
						.accessibilityHint("Checks for absence after 20 seconds without input")
						.toggleStyle(.switch)
						.controlSize(.small)
						.tint(Theme.accent)
				}
			}
			if settings.walkAwayLock && walkAwayNeedsAttention {
				RowDivider(inset: 0)
				walkAwayNotice
			}

		RowDivider()
		// Titled by what the switch actually gates: `BiometricGate.authorize()`
		// (remove-enrolment, store/revoke password) honours it; `require()`
		// (adding a face, trusting an autofill app) always prompts regardless.
		// No-sensor Macs stay opted out, as the footer below states.
		SettingToggle(
			title: "Ask before removing a face or changing the stored password",
			detail: "Adding a face always asks, even when this is off.",
			// Pink because Apple's own Touch ID icon is pink, not because a fifth hue
			// was needed. Every tint in this window now points at a System Settings row
			// that uses the same one.
			symbol: "touchid",
			isEnabled: BiometricGate.isAvailable,
			isOn: bind(\.touchIDFallback))
		}
	}

	// MARK: - Behaviour

	private var behaviourSection: some View {
		SettingsSection(title: "This Mac",
			footer: behaviourFooter,
			info: behaviourFooter) {
			SettingToggle(
				title: "Open at login",
				detail: loginItemNeedsApproval ? "Waiting for approval in System Settings." : nil,
				// Grey, like Login Items in System Settings — and because `Theme.faceID` is
				// documented as Gaze identity only. A power button is not Gaze.
				symbol: "power",
				isOn: Binding(
					get: { loginItemEnabled || loginItemNeedsApproval },
					set: { setLoginItemEnabled($0) }))

			if loginItemNeedsApproval || loginItemError != nil {
				RowDivider()
				SettingRow(
					title: loginItemError == nil ? "Approval needed" : "Open at login couldn’t be changed",
					detail: loginItemError,
					symbol: "exclamationmark.circle"
				) {
					Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
						.gazeButton()
				}
			}

			RowDivider()
			SettingToggle(
				title: "Ask for a password before quitting",
				symbol: "lock.fill",
				isOn: bind(\.tamperProtection))
		}
	}

	private func setLoginItemEnabled(_ requested: Bool) {
		let succeeded = LoginItem.setEnabled(requested)
		loginItemFailedRequest = succeeded ? nil : requested
		loginItemError = succeeded ? nil : "Couldn’t change Open at login. Review Login Items in System Settings, then try again."
		refreshLoginItemState()
	}

	private func refreshLoginItemState() {
		loginItemEnabled = LoginItem.isEnabled
		loginItemNeedsApproval = LoginItem.needsApproval
		if let requested = loginItemFailedRequest,
			requested == (loginItemEnabled || loginItemNeedsApproval) {
			loginItemError = nil
			loginItemFailedRequest = nil
		}
	}

	/// Only the caveats. Rows that work as expected need no sentence explaining that they do.
	///
	/// Nil rather than empty when there is nothing to say — an empty footer still reserved
	/// its leading and its line height, which left an unexplained gap under the group.
	private var securityFooter: String? {
		var notes: [String] = []
		if !SpoofDetector.isAvailable { notes.append("The photo-rejection model is unavailable.") }
		if !BiometricGate.isAvailable { notes.append("This Mac has no Touch ID sensor.") }
		return notes.isEmpty ? nil : notes.joined(separator: " ")
	}

	/// Sync only the presence watcher; changing this switch must not restart unlock.
	private var walkAwayBinding: Binding<Bool> {
		Binding(
			get: { settings.walkAwayLock },
			set: {
				settings.walkAwayLock = $0
				AppServices.shared.syncPresenceWatcher()
			})
	}

	private var walkAwayNeedsAttention: Bool {
		!AppServices.executionPolicy.permitsAutomaticLocking || !cameraGranted || !accessibilityGranted
	}

	@ViewBuilder
	private var walkAwayNotice: some View {
		if !AppServices.executionPolicy.permitsAutomaticLocking {
			StatusLine(
				kind: .warning,
				message: "Automatic locking is disabled for this diagnostic session.")
		} else {
			VStack(alignment: .leading, spacing: 0) {
				StatusLine(kind: .warning, message: walkAwayPermissionMessage)
				HStack(spacing: 6) {
					if !cameraGranted {
						Button("Open Camera Settings") { openPrivacySettings("Privacy_Camera") }
							.gazeButton()
							.fixedSize()
					}
					if !accessibilityGranted {
						Button("Review Accessibility") { openSetup(at: .permission) }
							.gazeButton()
							.fixedSize()
					}
				}
				.padding(.horizontal, Theme.rowInset)
				.padding(.bottom, 10)
			}
		}
	}

	private var walkAwayPermissionMessage: String {
		switch (cameraGranted, accessibilityGranted) {
		case (false, false):
			return "Camera and Accessibility access are off, so walk-away lock can neither check nor lock."
		case (false, true):
			return "Camera access is off, so walk-away lock cannot check."
		case (true, false):
			return "Accessibility access is off, so walk-away lock cannot lock the Mac."
		case (true, true):
			return ""
		}
	}

	private var behaviourFooter: String {
		var notes: [String] = []
		if loginItemNeedsApproval {
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
			info: settings.appTheme == .glass
				? "Semi Liquid Glass uses a dark, translucent surface. Onboarding follows "
					+ "this appearance too. The notch has its own style in Notch settings."
				: "Applies to Settings and onboarding. The recognition test keeps a neutral "
					+ "camera surround. The notch has its own style in Notch settings."
		) {
			SettingRow(title: "Theme", symbol: "circle.lefthalf.filled") {
				Menu {
					Picker("Theme", selection: $settings.appTheme) {
						ForEach(Preferences.AppTheme.allCases, id: \.self) { theme in
							Text(theme.title).tag(theme)
						}
					}
					.pickerStyle(.inline)
				} label: {
					Text(settings.appTheme.title).lineLimit(1)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.accessibilityLabel("Theme")
				.accessibilityValue(settings.appTheme.title)
				.fixedSize()
			}
		}
	}

	// MARK: - Updates

	private var updatesSection: some View {
		VStack(alignment: .leading, spacing: 7) {
			SettingsSection(
				title: "Updates",
				footer: "Downloads open in your browser. Gaze does not install updates automatically."
			) {
				SettingRow(
					title: "Version \(updates.currentVersion)",
					symbol: "arrow.trianglehead.2.clockwise"
				) {
					if updates.repositoryURL != nil {
						Button("Open Source Folder") { updates.revealRepository() }
							.gazeButton()
					}
				}

				RowDivider(inset: 0)
				SettingRow(
					title: releaseRowTitle,
					detail: releaseRowDetail,
					symbol: "sparkles"
				) {
					Button(releaseButtonTitle) { releaseAction() }
						.gazeButton()
						.disabled(releases.state == .checking)
				}

				if case .available(let release) = releases.state,
					!release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				{
					RowDivider(inset: 0)
					DisclosureGroup("Release Notes") {
						Text(release.notes)
							.font(Typography.detail)
							.foregroundStyle(Theme.secondaryLabel)
							.multilineTextAlignment(.leading)
							.frame(maxWidth: .infinity, alignment: .leading)
							.fixedSize(horizontal: false, vertical: true)
							.textSelection(.enabled)
					}
					.padding(.horizontal, Theme.rowInset)
					.padding(.vertical, 11)
				}
			}

			if updates.repositoryURL != nil {
				Text("For source builds, review and rebuild in your trusted checkout.")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.multilineTextAlignment(.leading)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, Theme.rowInset)
			}
		}
	}

	private var releaseRowTitle: String {
		if case .available(let release) = releases.state {
			return "Gaze \(release.tag) is available"
		}
		return "Released version on gazeunlock.com"
	}

	private var releaseRowDetail: String? {
		switch releases.state {
		case .idle: return "Check gazeunlock.com for a new build."
		case .checking: return "Checking gazeunlock.com…"
		case .upToDate: return "You're on the latest release."
		case .available(let release):
			// The release's own title, when it has one worth showing. A tag on its own says
			// a number changed; the title says what changed.
			return release.name.isEmpty ? "A newer build is published." : release.name
		case .failed(let message): return message
		}
	}

	private var releaseButtonTitle: String {
		switch releases.state {
		case .available: return "Download"
		case .checking: return "Checking…"
		default: return "Check"
		}
	}

	private func releaseAction() {
		if case .available = releases.state {
			releases.openDownload()
		} else {
			Task { await releases.check() }
		}
	}

	// MARK: - About

	/// Somebody's own picture, or their app's icon, from the bundle.
	///
	/// Nil is a normal answer, not a failure: the row falls back to its glyph, so a checkout
	/// without `Resources/Credits` still builds and still reads correctly. That matches how
	/// the setup card art behaves, and it is why nothing here throws.
	private func creditPortrait(_ name: String) -> NSImage? {
		guard
			let url = Bundle.main.url(
				forResource: name.lowercased(), withExtension: "png", subdirectory: "Credits")
		else { return nil }
		return NSImage(contentsOf: url)
	}

	/// An app one of the credited people made.
	struct CreditApp {
		let name: String
		/// The app's own one-line description, in its author's words — and nil when nobody
		/// has written one.
		///
		/// Optional because `credits.ts` only carries a description for the two apps Gaze is
		/// actually built on. WallX is listed there as something Unxnown made, with a name,
		/// an icon and a link and no words. Inventing a line for it would be writing someone
		/// else's product description for them, which is how this pane got into trouble the
		/// first time.
		let what: String?
		/// Bundled icon, named `app-<something>` so a person's portrait and an app's icon
		/// cannot collide in the same folder.
		let icon: String
		let href: String
	}

	/// One credited person, and their app underneath them if they have one.
	///
	/// The person is the credit; the app is a fact about the person. Flattening the two into
	/// one row — "cshariq — Sapphire — the recognition model…" — made the app read as the
	/// thing being thanked, which is how DanFQ ended up credited as *Atoll* for work he did
	/// himself. Two rows keep the distinction the site's data already draws: a `name` is
	/// always someone, an `app` is always a product.
	///
	/// Indented and quieter than the person above it, because it is a note attached to that
	/// row rather than a sibling of it.
	private func creditRow(
		name: String, detail: String, symbol: String,
		link: String?, linkName: String?, app: CreditApp?
	) -> some View {
		VStack(spacing: 0) {
			SettingRow(title: name, detail: detail, symbol: symbol, portrait: creditPortrait(name)) {
				if let link, let linkName {
					linkGlyph(linkName) { Self.open(link) }
				}
			}

			if let app {
				HStack(spacing: 10) {
					if let icon = creditPortrait(app.icon) {
						Image(nsImage: icon)
							.resizable()
							.interpolation(.high)
							.aspectRatio(contentMode: .fill)
							.frame(width: 20, height: 20)
							.clipShape(.rect(cornerRadius: 5, style: .continuous))
							.accessibilityHidden(true)
					}

					VStack(alignment: .leading, spacing: 0) {
						// Labelled, so the row cannot be misread as a second person.
						Text("\(app.name) — app")
							.font(Typography.detail)
							.foregroundStyle(Theme.label)
						if let what = app.what {
							Text(what)
								.font(Typography.detail)
								.foregroundStyle(Theme.tertiaryLabel)
						}
					}

					Spacer(minLength: 8)
					linkGlyph(app.name) { Self.open(app.href) }
				}
				// Indented past the portrait column above, so it hangs off the person.
				.padding(.leading, Theme.rowInset + 26 + 12)
				.padding(.trailing, Theme.rowInset)
				.padding(.bottom, 11)
			}
		}
	}

	/// The one link control this pane uses, so every row's is the same width.
	private func linkGlyph(_ name: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: "arrow.up.forward")
		}
		.gazeButton(.standard, size: .small)
		.help("Open \(name)")
		.accessibilityLabel("Open \(name)")
	}

	/// A row whose whole job is to open a link.
	///
	/// Same shape as the credits rows: one glyph button per row rather than the destination's
	/// name on a capsule, so three of them stack without three different widths.
	private func linkRow(
		title: String, detail: String, symbol: String, url: String
	) -> some View {
		SettingRow(title: title, detail: detail, symbol: symbol) {
			Button {
				guard let link = URL(string: url) else { return }
				NSWorkspace.shared.open(link)
			} label: {
				Image(systemName: "arrow.up.forward")
			}
			.gazeButton(.standard, size: .small)
			.help("Open \(title)")
			.accessibilityLabel("Open \(title)")
		}
	}

	/// Where donations go, or nil while there is nowhere to send them.
	///
	/// The row does not appear until this is set. A Support button that opens a
	/// page which does not exist is worse than no button, and this way the app
	/// ships with the feature dormant rather than broken.
	///
	/// A link out, never a form. Taking card details inside a Mac app means a
	/// merchant agreement and PCI obligations for a tip jar; every indie app
	/// sends you to a page that already handles that properly.
	private var donationURL: URL? { nil }

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

			// Where to go next.
			//
			// This pane had two read-only rows and a paragraph, and every route out of the
			// app — the site, the release notes for the version named directly above, the
			// savedApp to report that something is broken — existed only in a README. An About
			// pane is exactly where somebody looks for those, and "Gaze isn't working" with
			// nowhere in the app to say so is how a bug becomes a person quietly giving up.
			SettingsSection(
				title: "Gaze on the web",
				footer: "Release notes list what changed in each version, including this one."
			) {
				linkRow(
					title: "Website",
					detail: "gazeunlock.com",
					symbol: "safari",
					url: "https://gazeunlock.com")
				RowDivider(inset: 0)
				linkRow(
					title: "Release notes",
					detail: "What changed, version by version",
					symbol: "list.bullet.rectangle",
					url: "https://gazeunlock.com/releases")
				RowDivider(inset: 0)
				// The Discord, not the issue tracker.
				//
				// Both candidate repository URLs — the checkout's remote (`OwenCope/FaceID`)
				// and the one the README gives (`OwenCope/Gaze`) — answer 404 to a signed-out
				// request, which is what GitHub returns for a private repository *and* for one
				// that does not exist. Either way, most people clicking this would land on a
				// 404, and a support link that goes nowhere is worse than no support link.
				//
				// The Discord is where the feedback in the credits pane actually came from,
				// and it is the one destination here that was checked and answers 200.
				linkRow(
					title: "Report a problem",
					detail: "Ask in the Discord",
					symbol: "exclamationmark.bubble",
					url: "https://discord.gg/BFgKT5YJH")
			}

			if let donationURL {
				SettingsSection(
					title: "Support",
					footer: "Gaze is free and always will be. This only exists for anyone who wants to."
				) {
					SettingRow(
						title: "Buy me a coffee",
						detail: "Opens in your browser",
						symbol: "heart.fill", symbolTint: Theme.danger
					) {
						Button("Open") { NSWorkspace.shared.open(donationURL) }
							.gazeButton()
					}
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
				// Headed by what this *is*, not by whose trademark it is not.
				//
				// It read "Not Apple's Face ID", which made a registered mark the largest
				// words in the pane and defined the app by a comparison to something it was
				// never trying to be. Leading with the plain description is both more useful
				// to a reader and a smaller target: the honest sentence is "a facial
				// recognition app for Mac", and the Face ID paragraph stays because the
				// difference is worth knowing — as the second thing said, not the first.
				Text("What this is")
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				Text(
					"Gaze is a facial recognition app for Mac. It matches the face at your "
						+ "built-in camera against the one you enrolled, and types your login "
						+ "password when they agree."
				)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)

				Text(
					"It is not Apple's Face ID, and not connected to Apple. Face ID uses a "
						+ "TrueDepth camera that measures the shape of your face with infrared "
						+ "dots; Macs have no such sensor. Gaze sees a flat image from an "
						+ "ordinary camera, so it cannot tell a face from a good photograph of "
						+ "one the way an iPhone can."
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
			// One glyph per row, not the app's name on a capsule.
			//
			// Each of these was a filled button labelled with the app it opens — "Sapphire",
			// "DynamicLake", "Atoll" — which went wrong twice over. The name was already the
			// first word of the row's own subtitle, so the button restated it; and because
			// the three names are different lengths, the three capsules were different
			// widths, leaving a ragged right edge down a group whose rows are otherwise
			// identical in shape. Three mismatched pills is what the eye catches first.
			//
			// They all do the same thing — open a link — so they take the same control, at
			// the same width, and the row's text says which link it is. The name moves to
			// the tooltip and the accessibility label, where a control's purpose belongs.
			// Six people, matching `credits.ts` on the site, which is the list that gets
			// maintained.
			//
			// This pane had three of them, and got one of the three wrong: DanFQ was credited
			// for *Atoll*, with the line "and for reading this code more carefully than I
			// did". The site had already caught and fixed that, and its own note says why —
			// "the app was never built on it, and crediting someone's product for work they
			// did personally is a nicer-sounding kind of wrong." DanFQ gave ideas and
			// feedback, as himself. He has a link to his GitHub, not to an app Gaze does not
			// use.
			//
			// The self-deprecation went with it. "More carefully than I did" is not a credit
			// — it says something about the author in a row that exists to say something
			// about somebody else — and it is the kind of line that reads as charming once
			// and as false modesty every time after.
			//
			// Three of the six are people rather than apps, so `nautey` has no link at all
			// rather than a link invented to fill the column.
			SettingsSection(
				title: "Who helped",
				footer: "One borrowed model, one app this one learned its shape from, "
					+ "and four people who made it better."
			) {
				creditRow(
					name: "cshariq",
					detail: "The recognition model this app matches faces with is theirs",
					symbol: "brain.head.profile",
					link: "https://github.com/cshariq", linkName: "cshariq on GitHub",
					app: .init(
						name: "Sapphire", what: "The notch, reimagined.",
						icon: "app-sapphire", href: "https://sapphire-app.tech/"))

				RowDivider()
				creditRow(
					name: "Aviorrok",
					detail: "The notch panel and this window both follow its lead",
					symbol: "macbook",
					link: nil, linkName: nil,
					app: .init(
						name: "DynamicLake", what: "Dynamic Island for Mac.",
						icon: "app-dynamiclake", href: "https://dynamiclake.com"))

				RowDivider()
				creditRow(
					name: "Vanilla",
					detail: "Built the anti-spoofing pipeline",
					symbol: "eye.slash.fill",
					link: "https://github.com/howjin", linkName: "Vanilla on GitHub",
					app: nil)

				RowDivider()
				creditRow(
					name: "Unxnown",
					detail: "Set up the Discord, where every early build lands",
					symbol: "bubble.left.and.bubble.right.fill",
					link: "https://github.com/UnxnownYT", linkName: "Unxnown on GitHub",
					app: .init(
						name: "WallX", what: nil,
						icon: "app-wallx", href: "https://github.com/UnxnownYT/WallX"))

				RowDivider()
				// Atoll is his, and belongs here — under him, labelled as his app.
				//
				// It was removed from this pane earlier for a good reason and the wrong one.
				// The good reason: Gaze is not built on Atoll, so it cannot be the *credit* —
				// he is credited for ideas and feedback, which is what he actually gave.
				// The wrong one: dropping the app entirely, when the question "who is this
				// person" has an obvious answer that a reader would want.
				creditRow(
					name: "DanFQ",
					detail: "Ideas for the app, and a great deal of feedback on it",
					symbol: "lightbulb.fill",
					link: "https://github.com/danfq", linkName: "DanFQ on GitHub",
					app: .init(
						name: "Atoll", what: nil,
						icon: "app-atoll", href: "https://getatoll.app"))

				RowDivider()
				creditRow(
					name: "nautey",
					// "…on the macOS beta" was in the site's copy and does not survive the trip
					// into a credits row: it reads as a detail about his machine rather than
					// as a thing he did. What he does is find the breakages first.
					detail: "Moderates the Discord, and finds what's broken before anyone else",
					symbol: "checkmark.seal.fill",
					link: nil, linkName: nil,
					app: nil)
			}

			// Plain text, not a group. An empty card with a caption under it is a group that
			// forgot to have any rows.
			//
			// This was headed "And everyone who said what was wrong", over a paragraph
			// listing everything the Discord had criticised — the settings layout, light
			// mode, "what this app should not claim about itself" — ending "most of it was
			// right".
			//
			// Which is the app talking about itself, at length, in the one section that
			// exists to talk about other people. A reader learns nothing about the Discord
			// from it; they learn that the author feels sheepish. Thanks are for the people
			// who gave the feedback, not an inventory of the feedback.
			VStack(alignment: .leading, spacing: 6) {
				Text("And the Discord")
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				Text(
					"Every screenshot in this app was picked apart by people there before it "
						+ "shipped. Most of what they said was right, and most of it is in here."
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
					hasStoredPassword = true
				} else {
					passwordError = "That password didn't match your account."
				}
			} catch {
				passwordError = error.localizedDescription
			}
		}
	}

	/// Clear the stored password. Brings the entry field (and Store) back, so it reads as
	/// a toggle between "stored" and "not stored" rather than a one-way door.
	private func revokePassword() {
		Task {
			guard await BiometricGate.authorize(.storePassword) else { return }
			do {
				try PasswordVault.remove()
				passwordEntry = ""
				passwordError = nil
				hasStoredPassword = false
			} catch {
				passwordError = error.localizedDescription
			}
		}
	}

	private func clearLockout() {
		if PasswordVault.verify(lockoutPassword) {
			lockout.clearAfterPasswordAuth()
			lockoutError = nil
			lockoutPassword = ""
		} else {
			lockoutPassword = ""
			lockoutError = "That password didn’t match. Try again."
		}
	}
}

/// One enrolled face, as a tile.
///
/// Modelled on the fingerprint tiles in Touch ID & Password: the glyph is the
/// object, the name is under it and editable in savedApp, and removal appears on
/// approach rather than sitting there as a permanent invitation to destroy
/// something.
private struct FaceTile: View {

	let face: FaceEnrollment
	/// The picture somebody chose for this person, if they chose one.
	var portrait: NSImage?
	var rename: (String) -> Void
	var setPortrait: (NSImage?) -> Void
	var remove: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false
	/// Keep actions in the focus/accessibility tree even before the pointer arrives.
	@FocusState private var portraitFocused: Bool
	@FocusState private var removeFocused: Bool
	/// The name being typed, committed on Return or when focus leaves.
	///
	/// Bound straight through, every keystroke rewrote the vault and re-encrypted
	/// the whole record — and deleting the last character wrote an empty name that
	/// the store then rejected, so the field could not be cleared to retype.
	@State private var draft: String
	@FocusState private var isEditing: Bool

	init(
		face: FaceEnrollment,
		portrait: NSImage?,
		rename: @escaping (String) -> Void,
		setPortrait: @escaping (NSImage?) -> Void,
		remove: @escaping () -> Void
	) {
		self.face = face
		self.portrait = portrait
		self.rename = rename
		self.setPortrait = setPortrait
		self.remove = remove
		_draft = State(initialValue: face.name)
	}

	var body: some View {
		VStack(spacing: 6) {
			ZStack(alignment: .topTrailing) {
				// A circle with initials in it — the way macOS draws a person.
				//
				// This was a green squircle with the app's own eye glyph in it, and it was
				// wrong twice over.
				//
				// Wrong shape: every savedApp macOS shows a *person* — Users & Groups, the
				// login window, Contacts, Photos' People album — shows a circle. A rounded
				// square is what it uses for apps and files. This row is people.
				//
				// Wrong content, and worse: the glyph was identical on every tile, so a Mac
				// with four enrolled faces showed four indistinguishable green squares and
				// the name underneath did all the work. Initials are what macOS itself falls
				// back to when a person has no picture, and they make the row scannable —
				// which is the entire job of a tile.
				//
				// Wrong colour, too. Green means *recognised* everywhere in this app; a tile
				// that merely carries somebody's name is not a recognition event, and
				// spending the colour here is the same dilution the sidebar tint note warns
				// about. The tile is neutral; the green stays where it means something.
				// A portrait when there is one, initials when there is not.
				//
				// Initials are macOS's own fallback for a person with no picture, and they
				// were the whole improvement over four identical glyphs. A real face is
				// better still: on a Mac with several people enrolled it is the fastest
				// possible way to tell one row from another, and it is the thing every other
				// list of people on this system shows.
				Circle()
					.fill(Theme.surface)
					.frame(width: 52, height: 52)
					.overlay {
						if let portrait {
							Image(nsImage: portrait)
								.resizable()
								.interpolation(.high)
								.aspectRatio(contentMode: .fill)
								.clipShape(.circle)
						} else {
							Text(initials)
								.font(.system(size: 21, weight: .medium, design: .rounded))
								.foregroundStyle(Theme.secondaryLabel)
						}
					}
					.overlay { Circle().strokeBorder(Theme.separator, lineWidth: 1) }
					.contextMenu {
						Button("Choose Photo…") { choosePortrait() }
						if portrait != nil {
							Button("Remove Photo", role: .destructive) { setPortrait(nil) }
						}
					}

			// A camera badge on hover or keyboard focus, because a context menu nobody
			// right-clicks is a feature nobody finds. Bottom-leading so it cannot
			// collide with the remove button in the opposite corner.
			Group {
				Button(action: choosePortrait) {
					Image(systemName: "camera.fill")
						.font(.system(size: 10, weight: .semibold))
						.foregroundStyle(.white)
						.padding(5)
						.background(Circle().fill(.black.opacity(0.55)))
				}
				.buttonStyle(.plain)
				.help("Choose a photo for \(face.name)")
				.accessibilityLabel("Choose a photo for \(face.name)")
				.focused($portraitFocused)
				.opacity(controlsVisible ? 1 : 0)
				.allowsHitTesting(controlsVisible)
				.accessibilityHidden(false)
				.offset(x: -30, y: 30)
				.transition(reduceMotion ? .identity : .opacity)
			}

			// On hover *or* keyboard focus: a control that only exists `if hovering`
			// is in no accessibility tree and unreachable by Tab. Pointer visuals
			// are unchanged; focus joins the same reveal condition.
			Group {
				Button(action: remove) {
					Image(systemName: "minus.circle.fill")
						.font(.system(size: 17))
						.symbolRenderingMode(.palette)
						.foregroundStyle(.white, Theme.danger)
				}
				.buttonStyle(.plain)
				.help("Remove \(face.name)")
				.accessibilityLabel("Remove \(face.name)")
				.focused($removeFocused)
				.opacity(controlsVisible ? 1 : 0)
				.allowsHitTesting(controlsVisible)
				.accessibilityHidden(false)
				.offset(x: 7, y: -7)
				.transition(reduceMotion ? .identity : .opacity)
			}
		}
		.animation(
			reduceMotion || portraitFocused || removeFocused || isEditing
				? nil : .easeOut(duration: 0.12),
			value: controlsVisible)

			TextField("Name", text: $draft)
				.textFieldStyle(.plain)
				.font(Typography.detail)
				.foregroundStyle(Theme.label)
				.multilineTextAlignment(.center)
				.lineLimit(1)
				.frame(width: 84)
				.focused($isEditing)
				.onSubmit(commit)
				.onExitCommand {
					draft = face.name
					isEditing = false
				}
				.accessibilityLabel("Name for \(face.name)")
				.help(face.name)
				.onChange(of: isEditing) { _, editing in if !editing { commit() } }
				// Someone else's edit — a rename from another window, or the record
				// reloading — should show here rather than being overwritten by a
				// draft the user never touched.
				.onChange(of: face.name) { _, name in if !isEditing { draft = name } }
		}
		.onHover { hovering = $0 }
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Enrolled face, \(face.name)")
		.accessibilityAction(named: Text("Remove \(face.name)"), remove)
		.accessibilityAction(named: Text("Choose a photo for \(face.name)"), choosePortrait)
	}

	/// When the overlay actions exist at all.
	///
	/// Hover *or* keyboard focus — including focus on the name field, so Tabbing
	/// into the tile reveals the actions Tab will reach next. Pointer behaviour
	/// is exactly as before.
	private var controlsVisible: Bool {
		hovering || isEditing || portraitFocused || removeFocused
	}

	/// One letter, or two when the name has a surname to take one from.
	///
	/// Taken from the committed `face.name` rather than the draft, so the tile does not
	/// flicker through partial initials while somebody is retyping the name under it.
	/// Opens the system picker and hands back what was chosen.
	///
	/// `NSOpenPanel` rather than a drop target or a `PhotosPicker`: this is a Mac, the file
	/// is on disk, and the panel is the thing people already know. Restricted to images so
	/// the panel cannot return something the store then has to reject.
	private func choosePortrait() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.image]
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.prompt = "Choose"
		panel.message = "Pick a photo for \(face.name)."
		guard panel.runModal() == .OK, let url = panel.url,
			let image = NSImage(contentsOf: url)
		else { return }
		setPortrait(image)
	}

	private var initials: String {
		let words = face.name.split(separator: " ").filter { !$0.isEmpty }
		let letters = words.prefix(2).compactMap(\.first)
		guard !letters.isEmpty else { return "?" }
		return String(letters).uppercased()
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

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			VStack(spacing: 6) {
				// A filled tile that lightens on hover, not a dashed outline.
				//
				// The dashed rectangle is a drop-zone convention borrowed from the web, and
				// it is the one shape on this pane that has no counterpart anywhere in
				// macOS — Photos, Users & Groups and Touch ID all add with a filled well.
				// It also read as a placeholder rather than a control: a dashed box is what
				// an interface draws where something is *missing*, so the tile looked like
				// a gap in the row instead of the way to fill it.
				//
				// Lightening on hover rather than darkening, because a darker chip reads as
				// a hole punched in the surface.
				// A circle, matching the faces it stands beside. A squircle next to a row of
				// round avatars reads as a different kind of thing rather than as the next
				// slot in the same row.
				Circle()
					.fill(Theme.surface.opacity(hovering ? 1.6 : 1))
					.overlay { Circle().strokeBorder(Theme.separator, lineWidth: 1) }
					.frame(width: 52, height: 52)
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

		.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
	}
}
