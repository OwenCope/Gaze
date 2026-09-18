import AppKit
import AVFoundation
import SwiftUI
import os

// MARK: - Startup diagnostics

/// Opt-in per-phase startup timing. Enabled only with `--startup-diagnostics`.
///
/// Measures startup phases without reordering or deferring any startup work.
/// Logs only fixed phase labels and numeric durations — never names, paths,
/// enrollment contents, identifiers, passwords, or camera data. Never logs on
/// repeating timers; startup only.
@MainActor
fileprivate enum StartupTiming {
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Startup")

	static var isEnabled: Bool {
		CommandLine.arguments.contains("--startup-diagnostics")
	}

	static func start() -> TimeInterval? {
		isEnabled ? ProcessInfo.processInfo.systemUptime : nil
	}

	static func finish(label: String, start: TimeInterval?) {
		guard let start, isEnabled else { return }
		let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
		logger.notice("\(label, privacy: .public): \(Int(elapsedMs), privacy: .public)ms")
	}

	/// Runs `operation` directly with no timing or logging when disabled; otherwise
	/// logs the elapsed milliseconds under the fixed `label` after completion.
	static func measure<T>(label: String, operation: () -> T) -> T {
		guard isEnabled else { return operation() }
		let start = ProcessInfo.processInfo.systemUptime
		let result = operation()
		let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
		logger.notice("\(label, privacy: .public): \(Int(elapsedMs), privacy: .public)ms")
		return result
	}
}

@main
struct GazeApp: App {

	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	private var store: FaceEnrollmentStore { AppServices.shared.store }
	private var lockout: LockoutManager { AppServices.shared.lockout }
	private let presentsSettingsAtLaunch: Bool

	init() {
		let totalStart = StartupTiming.start()
		let enrolled = StartupTiming.measure(label: "services") { AppServices.shared.store.isEnrolled }
		if enrolled { OnboardingHistory.markPresented() }
		presentsSettingsAtLaunch = !AppActivation.isBackgroundLaunch
			&& !OnboardingHistory.presentsSetup(isEnrolled: enrolled, arguments: CommandLine.arguments)
		StartupTiming.finish(label: "gazeapp-init-total", start: totalStart)
	}

	var body: some Scene {
		MenuBarExtra {
			MenuBarContent(store: store, lockout: lockout)
		} label: {
			GazeStatusItemLabel()
		}
		// A real menu, not a window.
		//
		// Left to `.automatic`, SwiftUI backed this with a panel — and that panel stayed
		// alive at alpha 0, layer 101, parked under the menu bar item in the top-right of the
		// screen. An invisible window above normal windows eats every click inside its
		// rectangle, so clicks near the top-right corner intermittently did nothing *in other
		// applications*. The content here is a list of buttons; it wants an NSMenu.
		.menuBarExtraStyle(.menu)

		Window("Gaze", id: "settings") {
			SettingsView(store: store, lockout: lockout)
				.scrollIndicators(.never)
				.safeAreaInset(edge: .bottom, spacing: 0) {
					if AppServices.isUIReview {
						Label(AppServices.safetyNotice, systemImage: "lock.shield")
							.font(.caption).foregroundStyle(.secondary)
							.padding(10).frame(maxWidth: .infinity).background(.bar)
					}
				}
		}
		.defaultLaunchBehavior(presentsSettingsAtLaunch ? .presented : .suppressed)
		// `.contentMinSize`, not `.contentSize`: the view states a floor and an ideal, and
		// the user is allowed to go bigger. A settings window that cannot be resized has no
		// answer for someone who finds the text small.
		.windowResizability(.contentMinSize)
		// Opens at the size the view asks for rather than at whatever it was last dragged
		// to. Without this the frame AppKit had saved won — including a frame left behind
		// by resizing it once during development — so the window could open enormous and
		// mostly empty and stay that way for good.
		.defaultSize(width: 720, height: 600)
		// A real title bar, carrying a real `NSToolbar`.
		//
		// This was `.hiddenTitleBar`, and that one line is what forced everything above the
		// content to be hand-made. With no title bar there is nowhere for a toolbar to live,
		// so the pane switcher became a control floating in the content area, and the
		// content then needed `.padding(.top, 30)` to duck under the traffic lights that
		// were now sitting on top of it. The result read as a web page's tab strip: a bar of
		// words across the top of a window, which is the shape of the *system* menu bar.
		//
		// The window's own toolbar is the thing macOS puts a pane switcher in, and on
		// macOS 26 it is Liquid Glass without being asked — the real material, with the
		// scroll-edge effect and the traffic-light spacing handled by AppKit. None of that
		// can be reproduced by drawing a capsule in the content view, which is why the
		// previous two attempts at drawing it both ended up looking like a drawing of it.
		.windowToolbarStyle(.unified(showsTitle: false))

		Window("Test Recognition", id: "test") {
			RecognitionTestView(store: store)
		}
		.windowResizability(.contentMinSize)
		.defaultSize(width: 560, height: 820)

		// Behind a launch flag, and deliberately not in any menu. Collecting an
		// anti-spoof dataset is a job for whoever is building the model, not a
		// feature — but the crops have to come from this pipeline, so the tool has
		// to live in this app.
		Window("Capture Dataset", id: "dataset") {
			DatasetCaptureView()
				.scrollIndicators(.never)
		}
		.windowResizability(.contentSize)

		Window("Set Up Gaze", id: "enrollment") {
			EnrollmentWindow(store: store)
				.scrollIndicators(.never)
		}
		.windowResizability(.contentSize)
		.defaultSize(width: 720, height: 560)
		.restorationBehavior(.disabled)
		.windowStyle(.hiddenTitleBar)
		.defaultLaunchBehavior(!AppActivation.isBackgroundLaunch && !presentsSettingsAtLaunch ? .presented : .suppressed)
	}

}

// MARK: - Activation

/// Brings the app forward when it shows a window.
///
/// Gaze runs as an accessory app so it owns a menu bar item rather than a Dock tile.
/// The cost is that its windows open behind whatever the user was doing, and — worse —
/// system prompts it raises, like Touch ID, can't come to the front either. Both are
/// fixed by switching to a regular app for as long as a window is on screen.
@MainActor
enum AppActivation {
	static var openSettings: (() -> Void)?

	/// True when launchd started us rather than the user.
	///
	/// A background launch must never take focus. Pairing an unconditional `activate()`
	/// with a `KeepAlive` LaunchAgent produced a process that grabbed focus every few
	/// seconds and was resurrected each time it exited — which makes the machine
	/// effectively unusable. Focus is only ever appropriate when the user asked for a
	/// window.
	static var isBackgroundLaunch: Bool {
		CommandLine.arguments.contains("--agent")
	}

	static func bringToFront(userInitiated: Bool = false) {
		guard userInitiated || !isBackgroundLaunch else { return }
		NSApp.setActivationPolicy(.regular)
		NSApp.activate()
		// `activate()` alone can lose the race against a window that is still being
		// created, so order it up explicitly once it exists.
		//
		// Only windows already on screen, and only the key-capable ones.
		//
		// SwiftUI does not destroy a `Window` scene when it is dismissed — it orders it out
		// and keeps it — so `NSApp.windows` holds every window the app has ever shown.
		// Raising all of them meant opening any one window dragged every previously-closed
		// window back up with it: open Settings and the setup flow you finished last week
		// reappears on top of it.
		//
		// This filter was removed once already, on the theory that the loop is what presents
		// a freshly-created window and so must not skip invisible ones. That was wrong twice
		// over: SwiftUI's `openWindow` and `.defaultLaunchBehavior(.presented)` do the
		// presenting, this loop only wins a race against them; and the evidence for the
		// theory was a test harness that had stopped activating the app before listing
		// windows, so it reported every window as missing whatever the code did.
		for window in NSApp.windows where window.canBecomeKey && window.isVisible {
			window.orderFrontRegardless()
		}
	}

	/// Drops back to a menu bar-only app once no windows remain.
	///
	/// Deferred, and deliberately.
	///
	/// unxnown reported the Dock icon appearing and then, on clicking it, "shows something
	/// then vanishes instantly". This was why. Windows close and open in the same runloop
	/// turn — the enrolment window dismisses itself at launch, Settings opens from the menu
	/// while another window is still tearing down — and `onDisappear` fires in the gap where
	/// the closing window is gone and the opening one is not yet on screen. Seeing no
	/// windows, this dropped the app to `.accessory`, and switching activation policy while
	/// a window is coming up orders it straight back out.
	///
	/// Waiting a beat and asking again means the question is answered once the runloop has
	/// settled, rather than in the middle of a handover.
	static func returnToBackgroundIfIdle() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
			MainActor.assumeIsolated {
				// `canBecomeKey` excludes the lock screen panel, which must never hold the
				// app in `.regular` — it is on screen for most of the time the Mac is locked.
				let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
				guard !hasWindow else { return }
				NSApp.setActivationPolicy(.accessory)
			}
		}
	}
}

// MARK: - Services

/// The long-lived objects, owned outside the view tree.
///
/// They used to be `@State` on the App with startup hung off a `.task` on the menu bar
/// content — which only runs when the menu is *opened*. That meant the lock watcher, the
/// thing responsible for noticing your screen lock, never started unless you happened to
/// click the menu bar first.
@MainActor
final class AppServices {

	static let shared = AppServices()
	static let executionPolicy = UnlockExecutionPolicy.current
	static var isUIReview: Bool { executionPolicy != .normal }
	static var safetyNotice: String {
		if executionPolicy == .browserOnly {
			return "Browser approvals only · Mac locking and password entry are off for this run"
		}
		return executionPolicy == .scanOnly
			? "Scanning enabled on lock and wake · No password entry or automatic locking"
			: "UI review · Automatic locking and unlocking are off for this run"
	}

	let store = FaceEnrollmentStore()
	let lockout = LockoutManager()

	private var unlockService: UnlockService?
	private var lockWatcher: LockWatcher?
	private var presenceWatcher: PresenceWatcher?
	private var lockScreenShoot: LockScreenShoot?
	private var browserApprovals: GazeBrowserApproval?

	private init() {}

	/// Puts a stand-in lock screen on the display, for screenshots.
	///
	/// Launch with `--shoot-lockscreen`. Separate from the developer preview, which cycles
	/// the panel's phases over the desktop and then hides it: that is for watching the
	/// animation, this is for framing one picture, and it holds until Escape.
	func runLockScreenShootIfRequested() {
		guard !Self.isUIReview else { return }
		guard CommandLine.arguments.contains("--shoot-lockscreen") else { return }
		let shoot = LockScreenShoot()
		lockScreenShoot = shoot
		shoot.run()
	}

	/// Starts or stops walk-away locking to match the launch policy and the setting.
	///
	/// Deliberately independent of the unlock backend: automatic locking needs
	/// neither password storage nor replay, so backend `none` with replay
	/// disabled still locks when the setting is on. Only the normal launch
	/// policy permits it — scan-only, UI review, browser-only and any other
	/// prohibited policy stop and clear the watcher instead.
	///
	/// Idempotent: calling it when the watcher already matches the desired
	/// state neither starts a second watcher nor disturbs the running one. It
	/// touches only the presence watcher, so flipping the walk-away toggle
	/// never restarts an unlock attempt.
	func syncPresenceWatcher() {
		let shouldRun =
			Self.executionPolicy.permitsAutomaticLocking && Preferences.shared.walkAwayLock
		if shouldRun {
			guard presenceWatcher == nil else { return }
			let presence = PresenceWatcher(store: store)
			presence.start()
			presenceWatcher = presence
		} else {
			presenceWatcher?.stop()
			presenceWatcher = nil
		}
	}

	/// Starts whichever trigger the selected backend needs, stopping the other.
	///
	/// Safe to call repeatedly, and it must be — changing the backend in Settings used to
	/// do nothing until the app was relaunched, which left the user on a setting that
	/// looked active while nothing was watching for the lock. Selecting the plugin without
	/// installing it was the worst case: neither path running, and no indication why.
	func startUnlockTrigger() {
		// Walk-away locking first, before any early return below: prohibited
		// policies must stop a watcher left over from a mode switch, and an
		// enabled setting must start one even with backend none / replay off.
		syncPresenceWatcher()
		if Self.executionPolicy.permitsBrowserApproval(passwordReplayEnabled: PasswordReplaySafety.isEnabled), browserApprovals == nil {
			let service = GazeBrowserApproval(store: store, lockout: lockout)
			service.start()
			browserApprovals = service
		}
		// Tear down whatever was running before switching.
		lockWatcher?.stop()
		lockWatcher = nil
		if Self.executionPolicy == .scanOnly {
			_ = LockScreenSpace.shared
			let watcher = LockWatcher(store: store, lockout: lockout)
			lockWatcher = watcher
			watcher.start()
			return
		}
		guard !Self.isUIReview else { return }

		// The lock screen space, built now rather than when the screen first locks.
		//
		// `LockScreenSpace.shared` is a lazy static, and the only thing that touched it was
		// `adopt(window)` inside the capsule's `show()`. So on the first lock after launch
		// the space was created, levelled and shown *after* the window had already been
		// ordered in — all in one runloop turn, racing the window server. Measured at 407ms
		// after "Screen locked", which is the wrong side of the moment it is needed.
		//
		// Touching it at startup costs one space that sits empty until something is put in
		// it, and removes the race entirely.
		_ = LockScreenSpace.shared

		// The answering service runs whatever the backend is.
		//
		// It was started only for `.authPlugin`, on the reasoning that the plugin was the
		// only thing that would ever ask. That is no longer true: the PAM module that
		// authorises `sudo` is a second client of the same service, and it is useful with
		// the keystroke backend — which is the one most people are on, because the plugin
		// costs Touch ID and Apple Watch unlock to install.
		//
		// Starting it costs an idle XPC listener. It answers questions; it does not open a
		// camera until something asks one.
		if unlockService == nil {
			let service = UnlockService(store: store, lockout: lockout)
			service.start()
			unlockService = service
		}

		switch Preferences.shared.unlockBackend {
		case .authPlugin:
			// The plugin calls us; the listener above is all that is needed.
			break

		case .keystroke:
			guard PasswordReplaySafety.isEnabled else { return }
			// Nothing calls us here — we have to notice the lock ourselves.
			guard lockWatcher == nil else { return }
			let watcher = LockWatcher(store: store, lockout: lockout)
			watcher.start()
			lockWatcher = watcher

		case .none:
			break
		}
	}
}

// MARK: - Lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {

	private var invisibleWindowSweep: Timer?

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		MainActor.assumeIsolated {
			guard let openSettings = AppActivation.openSettings else { return true }
			openSettings()
			return false
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		MainActor.assumeIsolated {
			let totalStart = StartupTiming.start()
			StartupTiming.measure(label: "tamper-guard") { TamperGuard.shared.start() }
			StartupTiming.measure(label: "unlock-triggers") { AppServices.shared.startUnlockTrigger() }
			// Looks for a new release shortly after launch, then daily. See
			// `startScheduledChecks` for why this is not left to the button in Settings.
			StartupTiming.measure(label: "update-scheduling") { ReleaseUpdateChecker.shared.startScheduledChecks() }
			StartupTiming.measure(label: "screenshot-mode") { AppServices.shared.runLockScreenShootIfRequested() }
			StartupTiming.measure(label: "invisible-window-sweep") { self.startInvisibleWindowSweep() }
			// Native TipKit guidance, normal launches only: review, scan-only and
			// browser-only modes neither configure TipKit nor mutate tip history.
			if AppServices.executionPolicy == .normal {
				StartupTiming.measure(label: "tips") { GazeTips.configure() }
			}
			StartupTiming.finish(label: "did-finish-launching-total", start: totalStart)
		}
	}

	/// Makes any invisible window of ours click-through, for as long as the app runs.
	///
	/// SwiftUI's `MenuBarExtra` leaves a window behind at alpha 0, layer 101, parked under
	/// the menu bar item — 191×128 of dead screen in the top-right corner. Layer 101 is above
	/// every ordinary window and an invisible window still swallows clicks, so that rectangle
	/// stops working *in other applications* until this app quits.
	///
	/// Two earlier attempts did not hold. `.menuBarExtraStyle(.menu)` removed the panel that
	/// was there permanently but not this one, which arrives when the menu is used; and
	/// hanging the cleanup off `NSMenu.didEndTrackingNotification` assumed a notification that
	/// evidently does not always arrive. Guessing at *when* it appears has been wrong twice,
	/// so this stops guessing and simply checks.
	///
	/// It does not order the window out — SwiftUI owns that window and closing something it
	/// thinks is open invites a different bug. Making it click-through fixes precisely the
	/// reported problem and changes nothing anyone can see, since the window is invisible.
	///
	/// The window is found through the window server rather than `NSApp.windows`, because it
	/// is not reliably in that list, then matched back to an `NSWindow` by number.
	@MainActor
	private func startInvisibleWindowSweep() {
		Self.clearInvisibleWindows()
		let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
			MainActor.assumeIsolated {
				Self.clearInvisibleWindows()
				if CommandLine.arguments.contains("--debug-windows") {
					Self.logAppWindows("tick")
				}
			}
		}
		// Common modes, or it stops firing while a menu is open — which is exactly when the
		// window in question appears.
		RunLoop.main.add(timer, forMode: .common)
		invisibleWindowSweep = timer
	}

	/// Dumps what `NSApp.windows` actually contains, for diagnosing windows we cannot reach.
	@MainActor
	static func logAppWindows(_ note: String) {
		let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Windows")
		logger.notice("--- NSApp.windows (\(note, privacy: .public)) ---")
		for w in NSApp.windows {
			logger.notice(
				"num=\(w.windowNumber) level=\(w.level.rawValue) alpha=\(w.alphaValue) visible=\(w.isVisible) ignoresMouse=\(w.ignoresMouseEvents) class=\(String(describing: type(of: w)), privacy: .public) frame=\(NSStringFromRect(w.frame), privacy: .public)"
			)
		}
	}

	@MainActor
	static func clearInvisibleWindows() {
		let pid = ProcessInfo.processInfo.processIdentifier
		guard
			let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
				as? [[String: Any]]
		else { return }

		for entry in list {
			guard
				(entry[kCGWindowOwnerPID as String] as? Int32) == pid,
				let alpha = entry[kCGWindowAlpha as String] as? Double, alpha < 0.01,
				let number = entry[kCGWindowNumber as String] as? Int,
				let window = NSApp.window(withWindowNumber: number),
				!window.ignoresMouseEvents
			else { continue }

			window.ignoresMouseEvents = true
			Logger(subsystem: "com.gazeunlock.Gaze", category: "Windows")
				.notice("Made an invisible window click-through: \(number)")
		}
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		MainActor.assumeIsolated {
			TamperGuard.shared.authorizeQuit() ? .terminateNow : .terminateCancel
		}
	}
}

// MARK: - Menu bar

private struct GazeStatusItemLabel: View {
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		Image(nsImage: GazeBrand.menuBarIcon)
			.renderingMode(.template)
			.accessibilityLabel("Gaze")
			.onAppear {
				AppActivation.openSettings = {
					AppActivation.bringToFront(userInitiated: true)
					openWindow(id: "settings")
				}
			}
	}
}

struct MenuBarContent: View {

	/// Just the time, in whatever form this Mac writes times. Built once — a
	/// `DateFormatter` per menu redraw is a surprising amount of work for six characters.
	private static let clock: DateFormatter = {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		formatter.dateStyle = .none
		return formatter
	}()

	let store: FaceEnrollmentStore
	let lockout: LockoutManager

	@Environment(\.openWindow) private var openWindow
	@State private var preferences = Preferences.shared

	private var menuStatus: String {
		switch AppServices.executionPolicy {
		case .uiReview: return "UI review — unlocking is off"
		case .scanOnly: return "Scan-only mode — unlocking is off"
		case .browserOnly: return "Browser approvals only"
		case .normal: break
		}
		if lockout.isLockedOut { return "Locked out — password required" }
		if !store.isEnrolled { return "No face enrolled" }
		if preferences.isPaused {
			return "Paused until \(Self.clock.string(from: preferences.pausedUntil ?? Date()))"
		}
		if AVCaptureDevice.authorizationStatus(for: .video) != .authorized { return "Camera access needed" }
		if !PasswordReplaySafety.isEnabled { return "Mac unlocking is off" }
		if preferences.unlockBackend == .none { return "Recognition only" }
		let backend: UnlockBackend = switch preferences.unlockBackend {
		case .none: NoUnlockBackend()
		case .authPlugin: AuthPluginUnlockBackend()
		case .keystroke: KeystrokeUnlockBackend()
		}
		switch backend.readiness() {
		case .ready: return "Gaze is ready"
		case .needsSetup, .unavailable: return "Unlock needs attention — open Settings"
		}
	}

	var body: some View {
		Text(menuStatus)

		Divider()

		// Quick actions, above the windows that open. Locking is the thing you came here
		// to do; the rest is configuration.
		if store.isEnrolled {
			if preferences.isPaused {
				Button("Resume Gaze") { preferences.resume() }
			} else {
				Menu("Pause Gaze") {
					ForEach(Preferences.PauseSpan.allCases) { span in
						Button(span.title) { preferences.pause(for: span.seconds) }
					}
				}
			}
			Button("Lock Screen Now") { ScreenLock.now() }
				.keyboardShortcut("l")

			Divider()
		}

		// Shown whether or not a face is enrolled — there can be more than one now,
		// and the menu was the only way in for anyone who never opens Settings.
		if store.canAddFace {
			Button(store.isEnrolled ? "Add a Face…" : "Set Up Gaze…") {
				if store.isEnrolled { SetupRequest.begin() } else { SetupRequest.beginOnboarding() }
				AppActivation.bringToFront()
				openWindow(id: "enrollment")
			}
		}
		if store.isEnrolled {
			Button("Test Recognition…") {
				AppActivation.bringToFront()
				openWindow(id: "test")
			}
		}
		Button("Settings…") {
			AppActivation.bringToFront(userInitiated: true)
			openWindow(id: "settings")
		}

		Divider()

		Button("Quit Gaze") { NSApp.terminate(nil) }
			.keyboardShortcut("q")
	}
}

/// Wraps the enrolment flow so it can dismiss its own window.
struct EnrollmentWindow: View {

	let store: FaceEnrollmentStore

	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		// One setup flow, whether or not FaceIDKit is linked.
		//
		// It used to branch here, so a checkout without the framework got a
		// completely different setup screen — the first thing every user sees being
		// the one part no contributor could look at. `SetupMark` absorbs the
		// difference now: same flow, plainer animations.
		SetupFlow(store: store) {
			dismissWindow(id: "enrollment")
		}
		.task {
			// Settings has no way in but the menu bar, which makes it the one window that
			// cannot be opened from a script — so checking a change to it meant clicking
			// through the menu by hand every rebuild. `--settings` opens it straight from
			// the command line.
			//
			// It lives here because this window is the only scene guaranteed to exist at
			// launch, so it is the only savedApp holding an `openWindow` this early.
			// Same trick as `--settings`: this window is the only scene guaranteed to
			// exist at launch, so it is the only savedApp holding an `openWindow` early
			// enough to hand off to another one.
			//
			// Launch flags apply to the presentation launch made, not to every one.
			//
			// `CommandLine.arguments` never changes, and this `task` runs each time the
			// window is presented — so reading the flags unguarded let a debug argument
			// hijack every later opening for the life of the process. Under `--settings`,
			// pressing "Add a Face" opened this window, whose task found `--settings` still
			// set, dismissed itself and re-opened Settings: the flow vanished the instant it
			// appeared. `SetupFlow.consumeLaunchStep` carries the same fix for
			// `--setup-step`, for the same reason.
			//
			// Asked as "did somebody ask for this window", not as "is this the first time it
			// has appeared". Counting presentations was the obvious version and it broke the
			// flags outright: the task runs more than once at launch, so the first run spent
			// the one permitted use and was then torn down before it could act, leaving the
			// second run with nothing to do. A deliberate open always announces itself
			// through `SetupRequest.begin()`, which is a fact about intent rather than about
			// ordering, and cannot be raced.
			let isLaunchPresentation = !SetupRequest.isDeliberateOpen

			if isLaunchPresentation, CommandLine.arguments.contains("--capture-dataset") {
				try? await Task.sleep(for: .milliseconds(200))
				AppActivation.bringToFront()
				openWindow(id: "dataset")
				dismissWindow(id: "enrollment")
				return
			}

			if isLaunchPresentation, CommandLine.arguments.contains("--settings") {
				// One runloop turn before opening. `openWindow` called while the scene graph
				// is still being set up is dropped silently — the flag looked ignored.
				//
				// Open first, dismiss second, too: dismissing this window tears down the
				// view running this very task, so anything after it never runs.
				try? await Task.sleep(for: .milliseconds(200))
				AppActivation.bringToFront()
				openWindow(id: "settings")
				dismissWindow(id: "enrollment")
				return
			}

			// `--setup` keeps this window open even when a face is already enrolled.
			// Without it, working on the setup flow means clicking the menu bar item
			// after every rebuild, because launch dismisses the window for anyone who is
			// already set up — which, once you have tested it once, is you.
			if isLaunchPresentation, CommandLine.arguments.contains("--setup") {
				AppActivation.bringToFront()
				return
			}

			AppActivation.bringToFront(userInitiated: SetupRequest.isDeliberateOpen)
		}
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}
}
