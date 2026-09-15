import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import Observation
import os

/// Locks the Mac when you walk away from it.
///
/// The obvious implementation — hold the camera open and lock when it stops seeing a face —
/// is the wrong one, and not for a subtle reason. It lights the camera indicator for the
/// entire time the Mac is awake. A privacy feature whose visible signature is "this app is
/// watching you all day" is a feature people turn off in the first hour, and they are right
/// to. It also costs a meaningful amount of battery for a question whose answer is "yes,
/// still here" essentially always.
///
/// So the camera is not the trigger. **Idle is the trigger, and the camera is the
/// confirmation.**
///
/// Nothing runs while you are using the Mac. Once the keyboard and pointer have been quiet
/// for `armIdle`, the camera opens and looks. If it finds you — you are reading, or
/// watching something — it closes again immediately and nothing happens. Only sustained
/// idle *and* sustained absence locks the machine. In normal use the indicator never comes
/// on at all, and when it does it is for a couple of seconds.
///
/// That ordering also fixes the false positive that makes this feature infuriating
/// elsewhere: looking away from the screen, or leaning out of frame to talk to someone, is
/// not walking away — and while you are typing, this never even looks.
@Observable
@MainActor
final class PresenceWatcher {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Presence")

	/// How long the keyboard and pointer must be quiet before the camera is opened at all.
	///
	/// Short enough that walking away is caught promptly, long enough that reading a page
	/// or watching a video does not arm it constantly.
	private static let armIdle: TimeInterval = 20

	/// How often the idle check runs. Cheap — it is one call into the event system and no
	/// camera — so this can be frequent without costing anything.
	private static let tick: Duration = .seconds(5)

	/// How long the camera keeps looking before it gives up and decides nobody is there.
	/// Sampled rather than trusted once: a single frame can miss a face that is present.
	private static let confirmWindow: Duration = .seconds(4)
	private static let sampleInterval: Duration = .milliseconds(400)

	private let store: FaceEnrollmentStore
	private var loop: Task<Void, Never>?
	private var isConfirming = false

	init(store: FaceEnrollmentStore) {
		self.store = store
	}

	func start() {
		guard loop == nil else { return }
		loop = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.tick)
				guard let self, !Task.isCancelled else { return }
				await self.tickOnce()
			}
		}
		Self.logger.notice("Watching for you to walk away.")
	}

	func stop() {
		loop?.cancel()
		loop = nil
	}

	// MARK: - The check

	private func tickOnce() async {
		let preferences = Preferences.shared
		guard preferences.walkAwayLock else { return }
		guard store.isEnrolled else { return }
		// Paused means paused here too. Locking someone's Mac while they have deliberately
		// switched Gaze off would be the rudest possible reading of that switch.
		guard !preferences.isPaused else { return }
		// Nothing to do if it is already locked — and this is what stops the watcher
		// fighting `LockWatcher` for the camera during an unlock attempt.
		guard !Self.screenIsLocked() else { return }
		guard !isConfirming else { return }

		// Watching something is not being away.
		//
		// This is the false positive that makes walk-away lock unusable: a video is minutes
		// of no keyboard and no pointer, so idle time says "gone" while the person is sat
		// there watching. Waiting longer does not fix it, it only makes the interruption
		// rarer and more annoying when it lands.
		//
		// So ask the system instead of guessing. Anything playing video — a browser tab, a
		// player, a video call — holds a power assertion to stop the display dimming, and
		// that assertion is precisely macOS' own answer to "is someone watching this right
		// now?". Borrowing it means Gaze agrees with the rest of the Mac by construction
		// rather than by having its own opinion about timers.
		guard !Self.isPlayingMedia() else { return }

		guard Self.idleSeconds() >= Self.armIdle else { return }

		isConfirming = true
		defer { isConfirming = false }
		if await isNobodyThere() {
			// Re-check everything that could have changed during the four seconds the
			// camera was open. Locking a Mac somebody just started typing on is the one
			// failure this feature cannot be allowed to have.
			guard Preferences.shared.walkAwayLock,
				!Preferences.shared.isPaused,
				!Self.screenIsLocked(),
				Self.idleSeconds() >= Self.armIdle
			else { return }

			Self.logger.notice("Nobody there — locking.")
			ScreenLock.now()
		}
	}

	/// Opens the camera briefly and reports whether it saw a face at any point.
	///
	/// Any single sighting is enough to answer "somebody is there" — the expensive mistake
	/// is locking on a face the detector merely failed to find in one frame, not leaving a
	/// Mac unlocked four seconds longer.
	private func isNobodyThere() async -> Bool {
		let camera = CameraController()
		await camera.start(
			pinnedDeviceID: Preferences.shared.requireBuiltInCamera ? store.pinnedCameraID : nil)
		defer { camera.stop() }

		guard camera.state == .running else {
			// No camera is not evidence of absence. Refusing to guess is the only safe
			// behaviour for something whose action is locking the machine.
			Self.logger.error("Presence check skipped: camera unavailable.")
			return false
		}

		let deadline = ContinuousClock.now.advanced(by: Self.confirmWindow)
		while ContinuousClock.now < deadline {
			if !camera.faceMissing { return false }
			// Someone touching the keyboard mid-check means they are plainly there, and
			// waiting out the rest of the window to say so wastes camera time.
			if Self.idleSeconds() < Self.armIdle { return false }
			try? await Task.sleep(for: Self.sampleInterval)
			if Task.isCancelled { return false }
		}
		return true
	}

	// MARK: - System state

	/// Seconds since the last keyboard or pointer event anywhere in the session.
	private static func idleSeconds() -> TimeInterval {
		// `~0` is the documented "any event type" wildcard; there is no named constant for
		// it, and asking per-type would miss whichever type the user is actually using.
		guard let any = CGEventType(rawValue: ~0) else { return 0 }
		return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
	}

	/// Whether an app is holding the display awake — video, a call, a presentation.
	///
	/// Asked **per process**, and that detail is the whole thing. The obvious call is
	/// `IOPMCopyAssertionsStatus`, which returns a tidy dictionary of type to count — and
	/// it does not report `PreventUserIdleDisplaySleep` at all. What shows up there instead
	/// is powerd's `InternalPreventDisplaySleep`, a system roll-up that is held whenever
	/// the display is on, so a check against it would either never fire or always fire.
	/// Measured while a video was actually playing, the aggregate said "nothing", which
	/// would have made this guard silently useless.
	///
	/// `IOPMCopyAssertionsByProcess` reports what each process actually took out, and there
	/// the browser playing the video plainly holds `PreventUserIdleDisplaySleep`.
	///
	/// Only display assertions count. `caffeinate` and audio playback hold
	/// *system* sleep assertions, and neither means somebody is watching the screen —
	/// music playing while you walk away should still lock the Mac, and so should a Mac
	/// deliberately kept awake to finish a download.
	private static func isPlayingMedia() -> Bool {
		var byProcess: Unmanaged<CFDictionary>?
		guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
			let processes = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
		else {
			// Could not tell. Say yes: failing to lock is a nuisance, locking the Mac of
			// somebody halfway through a film is what gets the feature switched off.
			return true
		}

		let watching: Set<String> = [
			kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
			kIOPMAssertionTypeNoDisplaySleep as String,
		]

		for (_, assertions) in processes {
			for assertion in assertions {
				let type =
					(assertion["AssertionTrueType"] as? String)
					?? (assertion["AssertionType"] as? String)
				if let type, watching.contains(type) { return true }
			}
		}
		return false
	}

	private static func screenIsLocked() -> Bool {
		guard
			let session = CGSessionCopyCurrentDictionary() as? [String: Any],
			let locked = session["CGSSessionScreenIsLocked"] as? Bool
		else { return false }
		return locked
	}
}
