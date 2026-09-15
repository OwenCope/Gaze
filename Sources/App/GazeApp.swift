import AppKit
import SwiftUI
import os

@main
struct GazeApp: App {

	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	private var store: FaceEnrollmentStore { AppServices.shared.store }
	private var lockout: LockoutManager { AppServices.shared.lockout }

	var body: some Scene {
		MenuBarExtra {
			MenuBarContent(store: store, lockout: lockout)
		} label: {
			// The system symbol, not the drawn mark.
			//
			// This has now been `faceid`, then `eye`, then a drawn mark, then a bare
			// `viewfinder`. The trademark worry that started the churn is real but narrow:
			// it is about an app wearing Apple's glyph as *its own identity* — which is the
			// icon in the Dock and on disk. Using the system symbol inside the interface is
			// what system symbols are for, and `faceid` is the one glyph on macOS that means
			// exactly "a face, being recognised". `eye` said "this watches you"; an empty
			// viewfinder said nothing at all.
			//
			// So: the icon is a drawn keyhole (`Scripts/make_icon_mark.swift`), which is not
			// a face at all and cannot be confused for one; everything inside the app is the
			// system symbol. Fixed rather than changing with state — swapping the icon
			// around makes the item hard to find, and the state is the first line of the
			// menu anyway.
			Image(systemName: "faceid")
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
		}
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
		.windowResizability(.contentSize)

		// Behind a launch flag, and deliberately not in any menu. Collecting an
		// anti-spoof dataset is a job for whoever is building the model, not a
		// feature — but the crops have to come from this pipeline, so the tool has
		// to live in this app.
		Window("Capture Dataset", id: "dataset") {
			DatasetCaptureView()
		}
		.windowResizability(.contentSize)

		Window("Set Up Gaze", id: "enrollment") {
			EnrollmentWindow(store: store)
		}
		.windowResizability(.contentSize)
		// No title bar. The window is a fixed-size panel with its own progress row and its
		// own back button, and a system title bar above that is a second, emptier header
		// competing with the one that means something — "Set Up Gaze" over a screen whose
		// title already says what it is. The traffic lights stay, because they are how a
		// macOS window is closed and inventing our own would be worse; `SetupScaffold`
		// insets its chrome to clear them.
		.windowStyle(.hiddenTitleBar)
		// Opens on launch so a fresh install lands straight in setup. `EnrollmentWindow`
		// closes itself again when there is already a face enrolled.
		.defaultLaunchBehavior(.presented)
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

	static func bringToFront() {
		guard !isBackgroundLaunch else { return }
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

	let store = FaceEnrollmentStore()
	let lockout = LockoutManager()
	let savedApps = SavedAppStore()

	/// The autofill shortcut, and the panel it reports through.
	///
	/// The capsule is owned here rather than made per-fill: it is a window, and building
	/// one on every keypress would leak a window per fill.
	private var autofillHotKey: GlobalHotKey?
	private var autofillCapsule: NotchCapsuleController?
	private var autofillWatcher: AutofillWatcher?

	/// Whether ⌥⌘G is actually held. Read by the Places pane so the state is visible
	/// rather than only knowable from a log line.
	var isAutofillShortcutRegistered: Bool { autofillHotKey?.isRegistered ?? false }

	private var unlockService: UnlockService?
	private var lockWatcher: LockWatcher?
	private var presenceWatcher: PresenceWatcher?
	private var previewCapsule: NotchCapsuleController?
	private var lockScreenShoot: LockScreenShoot?

	private init() {}

	/// Shows the lock screen panel while unlocked, for inspecting it without locking.
	///
	/// Registers ⌥⌘G.
	///
	/// Deliberately *not* gated on there being a face enrolled, which is how this was
	/// written first and why it did not work. `startUnlockTrigger()` runs once at launch,
	/// so the guard was evaluated exactly once — before the enrolment store had finished
	/// reading the keychain — and a false answer there meant the shortcut was never
	/// registered and never retried. Nothing said so; the feature was simply inert.
	///
	/// The argument for the guard was that holding a system-wide shortcut which then does
	/// nothing is worse than not holding it. That is true and it is much the smaller
	/// problem: an unregistered shortcut is invisible, whereas a registered one that finds
	/// nothing saved can say so. `AutofillService` already handles every case — no face, no
	/// savedApp, no password — so let it.
	private func startAutofill() {
		guard autofillHotKey == nil else { return }

		let capsule = NotchCapsuleController()
		autofillCapsule = capsule

		// The shortcut stays, as the manual path: it accepts a plain text field as well as
		// a secure one, and it works in an app that was already frontmost.
		let watcher = AutofillWatcher(savedApps: savedApps, store: store, capsule: capsule)
		watcher.start()
		autofillWatcher = watcher

		let hotKey = GlobalHotKey()
		hotKey.register { [weak self] in
			guard let self else { return }
			Task { @MainActor in
				await AutofillService.fillFrontmost(
					savedApps: self.savedApps, store: self.store, capsule: capsule)
			}
		}
		autofillHotKey = hotKey
	}

	/// Launch with `--preview-capsule`. Cycles the whole sequence the lock screen actually
	/// plays — resting padlock, scan, success, retract — so every state can be watched and
	/// screenshotted without locking the machine.
	func runCapsulePreviewIfRequested() {
		guard CommandLine.arguments.contains("--preview-capsule") else { return }
		let capsule = NotchCapsuleController()
		previewCapsule = capsule
		capsule.show(phase: .locked)
		Task {
			try? await Task.sleep(for: .seconds(3))
			capsule.update(phase: .scanning)
			try? await Task.sleep(for: .seconds(4))
			// The challenge, in the preview cycle too. It only ever appears at the real lock
			// screen otherwise, which is the one savedApp macOS will not let anyone screenshot —
			// so without this the caption and the mark's lean could not be looked at at all.
			capsule.update(
				phase: .challenge(
					prompt: "Turn your head left", symbol: "arrowshape.left.fill",
					hintX: -1, hintY: 0, pulses: false))
			try? await Task.sleep(for: .seconds(5))
			// The tick, while the password goes in.
			capsule.update(phase: .success)
			try? await Task.sleep(for: .seconds(2))
			// Then the Mac opens, and the padlock lets go where it has been sitting. Held for
			// the same three seconds `LockWatcher.unlockAnimationDuration` holds it.
			capsule.update(phase: .unlocked)
			try? await Task.sleep(for: .seconds(3))
			capsule.hide()
		}
	}

	/// Puts a stand-in lock screen on the display, for screenshots.
	///
	/// Launch with `--shoot-lockscreen`. Separate from `--preview-capsule`, which cycles
	/// the panel's phases over the desktop and then hides it: that is for watching the
	/// animation, this is for framing one picture, and it holds until Escape.
	func runLockScreenShootIfRequested() {
		guard CommandLine.arguments.contains("--shoot-lockscreen") else { return }
		let shoot = LockScreenShoot()
		lockScreenShoot = shoot
		shoot.run()
	}

	/// Starts whichever trigger the selected backend needs, stopping the other.
	///
	/// Safe to call repeatedly, and it must be — changing the backend in Settings used to
	/// do nothing until the app was relaunched, which left the user on a setting that
	/// looked active while nothing was watching for the lock. Selecting the plugin without
	/// installing it was the worst case: neither path running, and no indication why.
	func startUnlockTrigger() {
		// Tear down whatever was running before switching.
		lockWatcher?.stop()
		lockWatcher = nil

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
			// Nothing calls us here — we have to notice the lock ourselves.
			guard lockWatcher == nil else { return }
			let watcher = LockWatcher(store: store, lockout: lockout)
			watcher.start()
			lockWatcher = watcher

			// Started unconditionally, not behind the setting.
			//
			// Its loop is one idle check every five seconds and it returns immediately
			// when the setting is off, so leaving it running costs nothing — and reading
			// the preference on each tick means switching walk-away lock on takes effect
			// straight away rather than at the next launch.
			if presenceWatcher == nil {
				let presence = PresenceWatcher(store: store)
				presence.start()
				presenceWatcher = presence
			}

			startAutofill()

		case .none:
			break
		}
	}
}

// MARK: - Lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {

	private var invisibleWindowSweep: Timer?

	func applicationDidFinishLaunching(_ notification: Notification) {
		MainActor.assumeIsolated {
			TamperGuard.shared.start()
			AppServices.shared.startUnlockTrigger()
			// Looks for a new release shortly after launch, then daily. See
			// `startScheduledChecks` for why this is not left to the button in Settings.
			ReleaseUpdateChecker.shared.startScheduledChecks()
			AppServices.shared.runCapsulePreviewIfRequested()
			AppServices.shared.runLockScreenShootIfRequested()
			startInvisibleWindowSweep()
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

	var body: some View {
		if lockout.isLockedOut {
			Text("Locked out — password required")
		} else if preferences.isPaused {
			Text("Paused until \(Self.clock.string(from: preferences.pausedUntil ?? Date()))")
		} else if store.isEnrolled {
			Text("Gaze is ready")
		} else {
			Text("No face enrolled")
		}

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
				SetupRequest.begin()
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
			AppActivation.bringToFront()
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
			// the command line, the same way `--preview-capsule` shows the lock panel.
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

			// Launch presents this window unconditionally; step back out if the user is
			// already set up and simply started the app. Anything opened on purpose —
			// "Add a Face", the menu item — stays, which is the whole point of it.
			if SetupRequest.shouldDismissImmediately(isEnrolled: store.isEnrolled) {
				dismissWindow(id: "enrollment")
				AppActivation.returnToBackgroundIfIdle()
			} else {
				AppActivation.bringToFront()
			}
		}
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}
}
