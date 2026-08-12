import AppKit
import SwiftUI

@main
struct FaceIDApp: App {

	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	private var store: FaceEnrollmentStore { AppServices.shared.store }
	private var lockout: LockoutManager { AppServices.shared.lockout }

	var body: some Scene {
		MenuBarExtra("Face ID", systemImage: menuBarSymbol) {
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

		Window("Face ID", id: "settings") {
			SettingsView(store: store, lockout: lockout)
		}
		// `.contentMinSize`, not `.contentSize`: the view states a floor and an ideal, and
		// the user is allowed to go bigger. A settings window that cannot be resized has no
		// answer for someone who finds the text small.
		.windowResizability(.contentMinSize)
		// The sidebar's vibrancy runs the full height of the window, so a title bar drawn
		// across the top of it would cut it in half. The traffic lights stay; only the bar
		// behind them goes.
		.windowStyle(.hiddenTitleBar)

		Window("Test Recognition", id: "test") {
			RecognitionTestView(store: store)
		}
		.windowResizability(.contentSize)

		Window("Set Up Face ID", id: "enrollment") {
			EnrollmentWindow(store: store)
		}
		.windowResizability(.contentSize)
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
/// Face ID runs as an accessory app so it owns a menu bar item rather than a Dock tile.
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
		for window in NSApp.windows where window.canBecomeKey {
			window.orderFrontRegardless()
		}
	}

	/// Drops back to a menu bar-only app once no windows remain.
	static func returnToBackgroundIfIdle() {
		let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
		guard !hasVisibleWindow else { return }
		NSApp.setActivationPolicy(.accessory)
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
			capsule.update(phase: .success)
			try? await Task.sleep(for: .seconds(4))
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

	func applicationDidFinishLaunching(_ notification: Notification) {
		MainActor.assumeIsolated {
			TamperGuard.shared.start()
			AppServices.shared.startUnlockTrigger()
			AppServices.shared.runCapsulePreviewIfRequested()
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
			Text("Face ID is ready")
		} else {
			Text("No face enrolled")
		}

		Divider()

		if !store.isEnrolled {
			Button("Set Up Face ID…") {
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

		Button("Quit Face ID") { NSApp.terminate(nil) }
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
