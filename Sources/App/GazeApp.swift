import AppKit
import SwiftUI
import os

@main
struct GazeApp: App {

	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	private var store: FaceEnrollmentStore { AppServices.shared.store }
	private var lockout: LockoutManager { AppServices.shared.lockout }

	var body: some Scene {
		MenuBarExtra("Gaze", systemImage: menuBarSymbol) {
			MenuBarContent(store: store, lockout: lockout)
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
		.defaultSize(width: 840, height: 640)
		.defaultPosition(.center)
		// Use the same unified title bar model as Xcode: AppKit owns the traffic lights,
		// title, toolbar material, and the full-width drag region. SettingsView owns only
		// the sidebar and detail content below it.
		.windowToolbarStyle(.unified)
		// Let SwiftUI/AppKit own the title-bar drag behavior. This keeps the full window
		// background draggable without a hand-rolled hit target in the content view.
		.windowBackgroundDragBehavior(.enabled)

		Window("Test Recognition", id: "test") {
		RecognitionTestView(store: store)
		}
		.windowResizability(.contentSize)
		.defaultSize(width: 720, height: 520)
		.defaultPosition(.center)
		.windowBackgroundDragBehavior(.enabled)

		Window("Set Up Gaze", id: "enrollment") {
		EnrollmentWindow(store: store)
		}
		.windowResizability(.contentSize)
		.defaultSize(width: 700, height: 590)
		.defaultPosition(.center)
		.windowBackgroundDragBehavior(.enabled)
		// Opens on launch so a fresh install lands straight in setup. `EnrollmentWindow`
		// closes itself again when there is already a face enrolled.
		.defaultLaunchBehavior(.presented)
	}

	/// Always Apple's Face ID glyph — it's what the app is, and swapping the icon around
	/// makes the menu bar item hard to find. State is shown in the menu instead.
	private let menuBarSymbol = "faceid"
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
		NSApp.activate(ignoringOtherApps: true)

		// `openWindow` can create its NSWindow after this method returns. Do the second
		// activation on the next run-loop turn so a settings window opened from the menu
		// bar cannot remain behind the app the user was using.
		DispatchQueue.main.async {
			guard !isBackgroundLaunch else { return }
			NSApp.activate(ignoringOtherApps: true)
			for window in NSApp.windows where window.canBecomeKey {
				if window.title == "Gaze", (!window.isOnActiveSpace || window.screen == nil) {
					window.center()
				}
				window.makeKeyAndOrderFront(nil)
			}
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

	private var unlockService: UnlockService?
	private var lockWatcher: LockWatcher?
	private var previewCapsule: NotchCapsuleController?

	private init() {}

	/// Shows the lock screen panel while unlocked, for inspecting it without locking.
	///
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

		switch Preferences.shared.unlockBackend {
		case .authPlugin:
			// The plugin calls us; we only need to be listening.
			guard unlockService == nil else { return }
			let service = UnlockService(store: store, lockout: lockout)
			service.start()
			unlockService = service

		case .keystroke:
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

	func applicationDidFinishLaunching(_ notification: Notification) {
		MainActor.assumeIsolated {
			TamperGuard.shared.start()
			AppServices.shared.startUnlockTrigger()
			AppServices.shared.runCapsulePreviewIfRequested()
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

	let store: FaceEnrollmentStore
	let lockout: LockoutManager

	@Environment(\.openWindow) private var openWindow

	var body: some View {
		if lockout.isLockedOut {
			Text("Locked out — password required")
		} else if store.isEnrolled {
			Text("Gaze is ready")
		} else {
			Text("No face enrolled")
		}

		Divider()

		if !store.isEnrolled {
			Button("Set Up Gaze…") {
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
		EnrollmentView(store: store) {
			dismissWindow(id: "enrollment")
		}
		.task {
			// Settings has no way in but the menu bar, which makes it the one window that
			// cannot be opened from a script — so checking a change to it meant clicking
			// through the menu by hand every rebuild. `--settings` opens it straight from
			// the command line, the same way `--preview-capsule` shows the lock panel.
			//
			// It lives here because this window is the only scene guaranteed to exist at
			// launch, so it is the only place holding an `openWindow` this early.
			if CommandLine.arguments.contains("--settings") {
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

			// Launch presents this window unconditionally; step back out if the user is
			// already set up and simply started the app.
			// Also close on a background launch: a launchd-started agent must not put a
			// setup window on screen, whatever the enrolment state.
			if store.isEnrolled || AppActivation.isBackgroundLaunch {
				dismissWindow(id: "enrollment")
				AppActivation.returnToBackgroundIfIdle()
			} else {
				AppActivation.bringToFront()
			}
		}
		.onDisappear { AppActivation.returnToBackgroundIfIdle() }
	}
}
