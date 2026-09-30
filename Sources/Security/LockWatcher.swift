import AppKit
import CoreVideo
import Foundation
import IOKit
import IOKit.pwr_mgt
import Observation
import os

/// Watches for the screen locking and drives a face unlock attempt.
///
/// This is the trigger the keystroke backend needs. The authorization-plugin path gets
/// invoked by macOS itself, but password replay has no such hook — the app has to notice
/// the lock screen appear, look for a face, and type the password. Nothing else calls it.
///
/// Deliberately does nothing until the screen is actually locked. Running the camera
/// speculatively would burn battery and light the recording indicator for no reason.
@Observable
@MainActor
final class LockWatcher {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "LockWatcher")
	private static let renderTimingLogger = Logger(subsystem: "com.gazeunlock.Gaze", category: "RenderTiming")

	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager

	private var attempt: Task<Void, Never>?
	private var attemptID: UUID?
	private var diagnosticID: UUID?
	/// Whether this lock produced a recognised face and a submitted password.
	///
	/// The unlock animation must only play when *we* did it. The screen unlocking is not by
	/// itself evidence of that — Touch ID, a typed password and a paired Watch all raise the
	/// same notification, and playing "Gaze opened this" over someone else's unlock is a
	/// claim the app has no basis for.
	private var didSubmitPassword = false
	private var submissionID: UUID?
	private static var submissionBudget = LockScreenSubmissionBudget()
	private static var manualInputObserved = false
	/// When the last wake trigger was honoured, so the pair of them counts as one.
	private var lastWakeTrigger: Date?
	/// Block-observer tokens, so `stop()` can actually unregister them.
	private var observers: [NSObjectProtocol] = []
	private(set) var isWatching = false
	private(set) var isLocked = false
	/// Whether the screen saver is currently running. While it covers the screen,
	/// scanning would light the camera with no panel visible.
	private var screenSaverRunning = false
	/// When a look last had to turn the dark-room light on.
	private static var lightNeededAt: Date?
	/// Listens for Space on the lock screen so it retries the scan. Started with the
	/// lock, stopped with the unlock; never runs otherwise.
	private let spaceMonitor = SpaceKeyMonitor()
	/// When the monitor last saw Space. A press it saw is a retry request, not typing:
	/// the input guard forgives exactly one keyDown within 300 ms of it.
	private var lastSpaceAt: Date?

	private let capsule = NotchCapsuleController()
	/// Checks the window server while the Mac is locked, in case the unlock notification
	/// never arrives or arrives before the session stops reporting locked.
	private var unlockWatchdog: Task<Void, Never>?
	/// After a scan ends with the Mac still locked, waits for the pointer to move and
	/// looks again, so trying once more does not mean closing the lid.
	private var pointerRetry: Task<Void, Never>?
	/// Set by the attempt when the camera never started or stopped sending frames, the
	/// one failure worth an automatic second try.
	private var cameraFailed = false
	/// The most recent matched print this lock, learned only after the Mac confirms
	/// the unlock was ours. A match alone is not a confirmed Gaze unlock, and learning
	/// from anything less would let a near-miss write itself into the vault.
	private var pendingLearnedPrint: (print: Faceprint, faceID: UUID)?
	/// When the current attempt began, for unlock timing and durations.
	private var attemptStartedAt: ContinuousClock.Instant?
	private var cameraRunningAt: ContinuousClock.Instant?
	private var firstFrameAt: ContinuousClock.Instant?
	private var firstMatchAt: ContinuousClock.Instant?
	private var passwordSubmittedAt: ContinuousClock.Instant?
	/// When the movement prompt was shown, for unlock timing bookkeeping.
	private var movementPresentedAt: ContinuousClock.Instant?
	/// Seconds from the movement prompt appearing to it being completed.
	private var movementDuration: TimeInterval?
	/// The prompt text shown for the movement challenge.
	private var movementPrompt: String?
	/// The Follow-the-light per-pass scores at completion, for the attempts log.
	private var movementLookPasses: [String]?
	/// The last face frame seen this lock, kept for the attempts log only.
	private var lastFacePixelBuffer: CVPixelBuffer?
	/// Whether this lock already filed an ended-without-Gaze attempt. One
	/// per lock: retries must not each file one.
	private var closedAttemptLogged = false

	/// How long to keep looking after the screen locks before giving up.
	///
	/// Bounded on purpose: a camera that runs for the whole time the Mac sits locked is a
	/// battery and privacy problem. If the user isn't there in the first few seconds they
	/// have walked away, and they can wake the screen to try again.
	private let searchWindow: TimeInterval = 12

	/// How long the face must keep matching, continuously, before the Mac unlocks.
	///
	/// Both a security and a feel decision. Recognition alone completes in under 200ms,
	/// which is fast enough that someone walking past the camera could unlock the machine
	/// before they had registered it happening — and fast enough that the animation reads
	/// as a glitch. Requiring the match to hold means a deliberate look unlocks and a
	/// glance does not.
	///
	/// 0.3 s: people who turn movements off chose speed. It still has to
	/// be a steady look, every frame of it still passes the photo and screen checks, and a
	/// face merely passing through the frame breaks the hold and starts it again.
	private static let requiredMatchDuration: TimeInterval = 0.3

	/// The hold when a movement challenge is configured. The challenge itself is the
	/// proof of presence, so the hold can be shorter and the unlock feel sooner — but
	/// only on that path. With the challenge off, the full hold above is all that stands
	/// between a match and the password, and it stays.
	private static let requiredMatchDurationWithChallenge: TimeInterval = 0.8

	/// How long a face must match before the movement is asked for. The full hold above
	/// still has to complete before the password goes in; this only starts the movement
	/// sooner, so the hold and the movement run at the same time.
	private static let challengeLead: Duration = .milliseconds(200)

	/// How long the opened padlock stays before the panel goes home.
	///
	/// Three seconds, not one. The Mac is already unlocked by this point, so the padlock is
	/// costing nobody anything — and it is the only part of the sequence you get to look at
	/// without a login window in front of it.
	private static let unlockAnimationDuration: TimeInterval = 3.0

	/// Waking posts a system wake and a displays wake, moments apart. Both mean "look
	/// now", and honouring both would tear the camera down and rebuild it mid-attempt.
	private static let wakeDebounce: TimeInterval = 3.0
	/// A beat for the camera to actually be awake before the first frame is asked for.
	/// Opening it immediately after a wake returns a device that reports running and then
	/// delivers black frames, which reads to the recogniser as "nobody there". Shorter
	/// than it once was: the camera restarts itself after a wake now, so a device that
	/// is genuinely not ready gets a second chance without costing every unlock 700 ms.
	private static let wakeSettle = Duration.milliseconds(450)

	/// Shorter settle after opening the lid. The full settle above exists so the key
	/// press or Escape that woke the Mac is taken before the input snapshot; opening
	/// the lid involves no key press, so there is nothing to let pass.
	private static let lidOpenSettle = Duration.milliseconds(150)

	/// Whether the lid is currently open. Desktops report no clamshell state and read
	/// false here, so they always keep the full settle.
	private static func lidOpenedRecently() -> Bool {
		let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
		guard service != IO_OBJECT_NULL else { return false }
		defer { IOObjectRelease(service) }
		guard let state = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else { return false }
		return !state
	}

	/// How long to wait for the Mac to actually unlock before giving up on it.
	private static let unlockGracePeriod: TimeInterval = 3.0

	/// How long a face has to be looked at, without matching, before it counts as rejected.
	///
	/// Comfortably longer than `requiredMatchDuration`, or a face that needs a moment to be
	/// recognised would be turned away before it had the chance.
	private static let rejectAfter: TimeInterval = 4.0

	/// The pause between a rejection and the next attempt.
	private static let retryCooldown: TimeInterval = 2.0

	/// Below this overlap a match counts as a different physical subject, even for the
	/// same enrolled face, and restarts the hold rather than inheriting it.
	private static let subjectChangeOverlap: CGFloat = 0.2

	/// Intersection over union of two Vision-normalized boxes. Same space on both sides
	/// is all it needs; the values never leave this comparison.
	private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
		let intersection = a.intersection(b)
		guard !intersection.isNull, !intersection.isEmpty else { return 0 }
		let union = a.width * a.height + b.width * b.height - intersection.width * intersection.height
		guard union > 0 else { return 0 }
		return (intersection.width * intersection.height) / union
	}

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
		// Main thread only: the monitor's callback runs on the main run loop.
		spaceMonitor.onSpaceKeyDown = { [weak self] in
			MainActor.assumeIsolated { self?.handleSpaceKey() }
		}
	}

	func start() {
		guard !isWatching else { return }
		if AutofillConsoleSession.current() != nil {
			Self.submissionBudget.resetAfterVerifiedUnlock()
			Self.manualInputObserved = false
		}
		isWatching = true

		// Tokens are kept because these are block observers.
		//
		// `removeObserver(self)` was never removing them: the block API registers an
		// opaque token as the observer, not `self`, so `stop()` left both observers live
		// and a later `start()` added a second pair. Two observers means `screenLocked()`
		// runs twice, and the second run cancels the attempt the first one started.
		let centre = DistributedNotificationCenter.default()
		observers.append(
			centre.addObserver(
				forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated { self?.screenLocked() }
			})
		observers.append(
			centre.addObserver(
				forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated { self?.screenUnlocked() }
			})

		// Wake is a workspace notification, not a distributed one, so it needs its own
		// centre. Both are observed: `didWake` is the machine, `screensDidWake` is the
		// displays, and which arrives first depends on how the Mac was woken — a lid, a
		// key press, or a Bluetooth mouse are not the same sequence.
		let workspace = NSWorkspace.shared.notificationCenter
		for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
			observers.append(
				workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
					MainActor.assumeIsolated { self?.wokeUp() }
				})
		}

		observers.append(
			workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
				[weak self] _ in
				MainActor.assumeIsolated { self?.displaysSlept() }
			})

		// The screen saver covers everything, so a lock reported while it runs must
		// not start a scan. Dismissing it starts one only if a password is required.
		observers.append(
			centre.addObserver(
				forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated { self?.screenSaverStarted() }
			})
		observers.append(
			centre.addObserver(
				forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated { self?.screenSaverStopped() }
			})

		Self.logger.notice("Watching for screen lock and wake.")
	}

	func stop() {
		if let diagnosticID { LockScanDiagnostics.shared.cancel(for: diagnosticID) }
		submissionID = nil
		didSubmitPassword = false
		attemptStartedAt = nil
		cameraRunningAt = nil
		firstFrameAt = nil
		firstMatchAt = nil
		passwordSubmittedAt = nil
		movementPresentedAt = nil
		movementDuration = nil
		movementPrompt = nil
		movementLookPasses = nil
		lastFacePixelBuffer = nil
		closedAttemptLogged = false
		attempt?.cancel()
		attempt = nil
		attemptID = nil
		unlockWatchdog?.cancel()
		unlockWatchdog = nil
		pointerRetry?.cancel()
		pointerRetry = nil
		capsule.hide()
		LockScreenLight.shared.hide()
		isWatching = false
		lastWakeTrigger = nil
		screenSaverRunning = false
		spaceMonitor.stop()
		for token in observers {
			DistributedNotificationCenter.default().removeObserver(token)
			NSWorkspace.shared.notificationCenter.removeObserver(token)
		}
		observers.removeAll()
	}

	// MARK: - Events

	private func screenLocked() {
		guard Self.screenIsLocked() else { return }
		// Warm the models now, while the camera is still off, so the first scan does
		// not stall loading them mid-loop. Off the main actor, in parallel with the
		// attempt below; warmUp reloads them if they were unloaded while idle.
		Task.detached(priority: .userInitiated) { [embedder = store.embedder] in
			embedder.warmUp()
			SpoofDetector.shared?.warmUp()
			IrisLocator.warmUp()
		}
		isLocked = true
		spaceMonitor.start()
		closedAttemptLogged = false
		lastFacePixelBuffer = nil
		// The screen saver covers the panel, so a lock reported while it runs is
		// not a moment anyone can see or answer. Dismissing it starts the scan.
		guard !screenSaverRunning else {
			Self.logger.notice("Screen locked with the screen saver running; not scanning until it's dismissed.")
			return
		}
		// An idle Mac usually locks as its display turns off. Scanning then found the
		// person sitting there and asked for a movement on a black screen, which timed out
		// and counted as a miss again and again. The display waking starts the scan instead.
		guard !Self.displaysAreAsleep() else {
			Self.logger.notice("Screen locked with the display off; waiting for it to wake.")
			return
		}
		beginAttempt(trigger: "Screen locked")
	}

	/// The display went dark mid-scan. Nobody can see the panel or answer it, so stop
	/// without counting anything; waking the display starts again.
	private func displaysSlept() {
		lastWakeTrigger = nil
		// Nobody can see it, and the brightness it boosted should come back down.
		LockScreenLight.shared.hide()
		pointerRetry?.cancel()
		pointerRetry = nil
		guard attempt != nil else { return }
		Self.logger.notice("Display turned off during a scan; stopping until it wakes.")
		logAttemptTiming(outcome: "display-slept")
		recordEndedWithoutGaze(.leftLocked)
		attempt?.cancel()
		attempt = nil
		attemptID = nil
		capsule.hide()
	}

	/// The screen saver started and covers everything. Stop like the display
	/// going dark: nobody can see the panel, so there is nothing to answer.
	private func screenSaverStarted() {
		screenSaverRunning = true
		LockScreenLight.shared.hide()
		pointerRetry?.cancel()
		pointerRetry = nil
		guard attempt != nil else { return }
		Self.logger.notice("Screen saver started; not scanning until it's dismissed.")
		logAttemptTiming(outcome: "screen-saver-started")
		recordEndedWithoutGaze(.leftLocked)
		attempt?.cancel()
		attempt = nil
		attemptID = nil
		capsule.hide()
	}

	/// The screen saver was dismissed. Scan only if a password is actually
	/// required now; otherwise the camera stays off.
	private func screenSaverStopped() {
		screenSaverRunning = false
		guard Self.screenIsLocked() else { return }
		guard !Self.displaysAreAsleep() else { return }
		isLocked = true
		spaceMonitor.start()
		// The key or mouse that dismissed it must not count as input, same as wake.
		beginAttempt(trigger: "Screen saver dismissed", settle: Self.wakeSettle)
	}

	/// Whether the screen saver engine is running, in case its start
	/// notification was never delivered.
	private static func screenSaverIsRunning() -> Bool {
		guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSaver.Engine"
			|| !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenSaver.Engine").isEmpty
		else { return false }
		return true
	}

	private static func displaysAreAsleep() -> Bool {
		CGDisplayIsAsleep(CGMainDisplayID()) != 0
	}

	/// The Mac woke up. If it woke to a locked screen, look for a face.
	///
	/// This is the common case the app used to miss entirely. `com.apple.screenIsLocked`
	/// fires when the screen *becomes* locked — which, for a Mac that was closed and
	/// carried somewhere, happened before it went to sleep. Waking it posts no such
	/// notification, because nothing changed: it was locked then and it is locked now. So
	/// the most ordinary way anyone meets their lock screen — open the lid — was the one
	/// way Gaze never ran.
	private func wokeUp() {
		// The notification says the machine woke, not that the screen is locked. Ask the
		// window server rather than assuming, for the same reason the replay path does:
		// the failure to avoid is typing a password at a screen that is already open.
		guard Self.screenIsLocked() else { return }
		// The machine can wake before its display does; the display's own wake follows.
		guard !Self.displaysAreAsleep() else { return }

		// Waking posts more than one notification — the system wakes, then the displays
		// do — and both mean the same thing here. Without this, the second one cancels
		// the attempt the first one started and the camera is torn down and rebuilt.
		if let last = lastWakeTrigger, Date().timeIntervalSince(last) < Self.wakeDebounce {
			return
		}
		lastWakeTrigger = Date()

		isLocked = true
		spaceMonitor.start()
		// The wake arrived while the screen saver still covers everything.
		guard !screenSaverRunning else {
			Self.logger.notice("Woke with the screen saver running; not scanning until it's dismissed.")
			return
		}
		// Opening the lid involves no key press, so when the lid is open and nothing
		// was typed or clicked to wake the Mac, the shorter settle is enough before
		// the input snapshot is taken.
		let settle: Duration
		if Self.lidOpenedRecently(),
			CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) > 1.0,
			CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown) > 1.0 {
			settle = Self.lidOpenSettle
			Self.logger.notice("Woke with the lid open and no recent input; using the shorter settle.")
		} else {
			settle = Self.wakeSettle
			Self.logger.notice("Woke via key or mouse; using the full settle.")
		}
		beginAttempt(trigger: "Woke to a locked screen", settle: settle)
	}

	/// Everything both triggers do. Shared so the two cannot drift apart.
	///
	/// - Parameter settle: how long to wait before opening the camera. Zero when the
	///   screen locks in front of us, because the hardware is already awake; a beat after
	///   a wake, because it is not — asking too early returns a camera that reports
	///   running and delivers black frames for the first second.
	private func beginAttempt(trigger: String, settle: Duration = .zero) {
		// Fallback in case the screen saver's start notification never arrived.
		if Self.screenSaverIsRunning() { screenSaverRunning = true }
		guard !screenSaverRunning else {
			Self.logger.notice("\(trigger, privacy: .public) with the screen saver running; not scanning until it's dismissed.")
			return
		}
		// A wake can arrive without a prior lock notification, so warm here too, in
		// parallel with the camera start. Off the main actor; a no-op if already warm.
		Task.detached(priority: .userInitiated) { [embedder = store.embedder] in
			embedder.warmUp()
			SpoofDetector.shared?.warmUp()
			IrisLocator.warmUp()
		}
		guard UnlockExecutionPolicy.current.permitsScanning(passwordReplayEnabled: PasswordReplaySafety.isEnabled,
			keystrokeSelected: Preferences.shared.unlockBackend == .keystroke) else { return }
		guard submissionID == nil, Self.submissionBudget.maySubmit, !Self.manualInputObserved else { return }
		guard attempt == nil else { return }
		guard store.isEnrolled else { return }
		// Paused means paused: no camera, no panel, no indicator light. Checked here
		// rather than inside the attempt so a pause costs nothing at all — the point of
		// the switch is that Gaze is not looking, and a green camera light that turns
		// itself off again would say otherwise.
		guard !Preferences.shared.isPaused else {
			Self.logger.notice("\(trigger, privacy: .public) while paused; not looking.")
			return
		}
		guard lockout.mayAttempt() else {
			Self.logger.notice("\(trigger, privacy: .public) while locked out; not looking.")
			StateBroadcast.post(.lockedOut)
			return
		}
		if UnlockExecutionPolicy.current == .scanOnly {
			Self.logger.notice("Scan-only diagnostic started. No credential will be read or typed.")
		}

		Self.logger.notice("\(trigger, privacy: .public) — looking for a face.")
		pointerRetry?.cancel()
		pointerRetry = nil

		// A padlock, immediately. It is a statement about the Mac's state, not a claim
		// that the camera is looking at anyone — that distinction is why the compact
		// locked phase exists separately from scanning.
		didSubmitPassword = false
		pendingLearnedPrint = nil
		capsule.show(phase: .locked)
		startUnlockWatchdog()
		// Every broadcast below is posted beside the capsule update that shows the same
		// thing, so the panel and any subscriber can never disagree about the state.
		StateBroadcast.reset()
		StateBroadcast.post(.locked)

		let identifier = UUID()
		attemptID = identifier
		diagnosticID = identifier
		attemptStartedAt = .now
		cameraRunningAt = nil
		firstFrameAt = nil
		firstMatchAt = nil
		passwordSubmittedAt = nil
		movementPresentedAt = nil
		movementDuration = nil
		movementPrompt = nil
		movementLookPasses = nil
		LockScanDiagnostics.shared.begin(identifier)
		attempt = Task {
			defer {
				LockScanDiagnostics.shared.finishScanning(for: identifier)
				if self.attemptID == identifier {
					self.attempt = nil
					self.attemptID = nil
				}
			}
			// A screen saver that asks for a password locks the session a moment before
			// it reports starting, so the lock alone raced it and the camera light came
			// on under the saver. Wait that moment out, with the camera still off.
			// Only an idle lock can be the screen saver's. A lock right after a key press or
			// click (Control-Command-Q, the menu, closing the lid) skips the wait, which was
			// adding 0.6 s before the panel opened on every manual lock.
			let idle = min(
				CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
				CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
				CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved))
			if trigger == "Screen locked", idle > 5 {
				try? await Task.sleep(for: .milliseconds(600))
				if Self.screenSaverIsRunning() { self.screenSaverRunning = true }
				guard !Task.isCancelled, !self.screenSaverRunning else {
					Self.logger.notice("Screen saver took over the lock; not scanning until it's dismissed.")
					return
				}
			}
			// If the last look needed the light a few minutes ago, the room is still dark:
			// light it straight away instead of waiting a second and a half to find out.
			if Preferences.shared.screenGlowInDark, let at = Self.lightNeededAt,
				Date().timeIntervalSince(at) < 15 * 60, !LockScreenLight.shared.isShowing {
				LockScreenLight.shared.show()
			}
			// Open the panel now, while the camera starts, rather than on its first frame:
			// the camera takes most of a second, and a panel that waited for it felt slow.
			self.capsule.update(phase: .scanning)
			// Keep the display awake while looking. The lock screen dims and sleeps the
			// display on its own short timer, which could cut a scan off mid-movement.
			// Held only for this attempt, so an ignored lock screen still sleeps.
			var displayAssertion = IOPMAssertionID(0)
			let holdsDisplay = IOPMAssertionCreateWithName(
				kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
				IOPMAssertionLevel(kIOPMAssertionLevelOn),
				"Gaze is checking for your face" as CFString,
				&displayAssertion) == kIOReturnSuccess
			defer { if holdsDisplay { IOPMAssertionRelease(displayAssertion) } }
			// The camera starts now, alongside the settle, instead of after it. Starting a
			// session takes about as long as the settle itself, so running them one after
			// the other cost every lid-open unlock roughly half a second. The frames that
			// arrive during the settle are the dark ones it exists to skip, and the scan
			// loop only begins after it, so nothing looks at them.
			var early: (camera: CameraController, started: Task<Void, Never>)?
			if settle > .zero {
				let allowExternal = Preferences.shared.allowExternalCamera
				let available = CameraDevice.candidates(allowExternal: allowExternal).map(\.uniqueID)
				if let pinned = self.store.unlockCamera(allowExternal: allowExternal, available: available)?.cameraID,
					!pinned.isEmpty {
					let camera = CameraController(accessScope: .lockScreen)
					early = (camera, Task { await camera.start(pinnedDeviceID: pinned) })
				}
				try? await Task.sleep(for: settle)
				guard !Task.isCancelled else {
					early?.camera.stop()
					return
				}
			}
			// Taken after the settle, so the key press or Escape that woke the Mac, or
			// came with opening the lid, does not read as someone typing a password.
			let inputSnapshot = LockScreenInputSnapshot.current()
			// A camera that fails right after a wake usually works a second later, so it
			// gets one restart. The input snapshot is kept, so a click during the first try
			// still stops the second.
			for retry in 0..<2 {
				self.cameraFailed = false
				await self.attemptUnlock(inputSnapshot: inputSnapshot, identifier: identifier,
					prestarted: retry == 0 ? early : nil)
				if retry == 0 { early = nil }
				guard self.cameraFailed, retry == 0, !Task.isCancelled, self.isLocked else { break }
				Self.logger.notice("Camera failed; restarting it once.")
				try? await Task.sleep(for: .seconds(1))
				guard !Task.isCancelled else { return }
			}
			if !Task.isCancelled, self.isLocked { self.watchPointerForRetry() }
		}
	}

	/// Space on the lock screen means "look again". Stamped first, so the press never
	/// counts as typing even when a scan is already running; only a still screen with
	/// no scan in progress starts one.
	private func handleSpaceKey() {
		lastSpaceAt = Date()
		guard isLocked, !Self.displaysAreAsleep(), !screenSaverRunning, attempt == nil else { return }
		beginAttempt(trigger: "Space pressed on a locked screen")
	}

	/// Moving the mouse or trackpad after a scan has ended starts a new one. Clicks and
	/// key presses still stop Gaze for this lock (see `LockScreenInputGuard`).
	private func watchPointerForRetry() {
		pointerRetry?.cancel()
		let moves = CGEventSource.counterForEventType(.hidSystemState, eventType: .mouseMoved)
		pointerRetry = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(500))
				guard let self, !Task.isCancelled, self.isLocked, !Self.manualInputObserved else { return }
				guard self.attempt == nil,
					CGEventSource.counterForEventType(.hidSystemState, eventType: .mouseMoved) != moves
				else { continue }
				self.pointerRetry = nil
				self.beginAttempt(trigger: "Pointer moved on a locked screen")
				return
			}
		}
	}

	/// Two unlocked readings a second apart end the attempt as if the notification had come.
	private func startUnlockWatchdog() {
		unlockWatchdog?.cancel()
		unlockWatchdog = Task { [weak self] in
			var unlockedReadings = 0
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(1))
				guard let self, !Task.isCancelled, self.isLocked else { return }
				unlockedReadings = Self.screenIsLocked() ? 0 : unlockedReadings + 1
				if unlockedReadings >= 2 {
					Self.logger.notice("Screen is unlocked but no unlock notification was handled; tidying up.")
					self.screenUnlocked()
					return
				}
			}
		}
	}

	private func screenUnlocked(retry: Int = 0) {
		guard AutofillConsoleSession.current() != nil else {
			// The notification can arrive while the session still reports locked. Returning
			// here left the panel on the desktop and the camera running, so check again.
			if retry < 8 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
					MainActor.assumeIsolated { self?.screenUnlocked(retry: retry + 1) }
				}
			} else if !Self.screenIsLocked() {
				Self.logger.notice("Unlocked into a session Gaze cannot verify; hiding the panel.")
				isLocked = false
				spaceMonitor.stop()
				submissionID = nil
				didSubmitPassword = false
				logAttemptTiming(outcome: "unverified")
				recordEndedWithoutGaze(.openedAnotherWay)
				lastFacePixelBuffer = nil
				attempt?.cancel()
				attempt = nil
				attemptID = nil
				unlockWatchdog?.cancel()
				unlockWatchdog = nil
				capsule.hide()
			}
			return
		}
		unlockWatchdog?.cancel()
		unlockWatchdog = nil
		pointerRetry?.cancel()
		pointerRetry = nil
		if let diagnosticID {
			if didSubmitPassword { LockScanDiagnostics.shared.record(.unlocked, for: diagnosticID) }
			else { LockScanDiagnostics.shared.finishScanning(for: diagnosticID) }
		}
		Self.submissionBudget.resetAfterVerifiedUnlock()
		Self.manualInputObserved = false
		submissionID = nil
		isLocked = false
		spaceMonitor.stop()
		StateBroadcast.post(.idle)
		// Whatever unlocked the Mac, we are done. Cancelling releases the camera promptly
		// rather than leaving the indicator lit after the user has typed their password.
		attempt?.cancel()
		attempt = nil
		attemptID = nil

		guard didSubmitPassword else {
			// Unlocked by other means. Nothing to celebrate — just get out of the way.
			logAttemptTiming(outcome: "other")
			recordEndedWithoutGaze(.openedAnotherWay)
			lastFacePixelBuffer = nil
			capsule.hide()
			return
		}
		let unlockDuration = attemptStartedAt.map(Self.seconds(since:))
		let steps = attemptSteps()
		logAttemptTiming(outcome: "unlocked")
		UnlockAttemptLog.shared.record(.unlocked, duration: unlockDuration, steps: steps,
			photo: lastFacePixelBuffer)
		lastFacePixelBuffer = nil
		closedAttemptLogged = false
		didSubmitPassword = false
		lockout.recordSuccess()
		// Ours, confirmed: this is the only moment learning may happen. The print is
		// the frame that matched, never a mask-path one — learned prints must stay in
		// the same space as the originals they are guarded against.
		if let pending = pendingLearnedPrint {
			store.learn(pending.print, for: pending.faceID)
		}
		pendingLearnedPrint = nil
		StateBroadcast.post(.succeeded)

		// The Mac agreed. Retract to the resting bar and let the padlock open there, which
		// is the last beat of the sequence and the only one the user is still looking at.
		capsule.update(phase: .unlocked)
		capsule.hide(after: Self.unlockAnimationDuration)
	}

	/// The lock ended without Gaze doing it: someone got in another way, or the
	/// display went dark first. Filed once per lock, even with no face frame.
	private func recordEndedWithoutGaze(_ result: UnlockAttempt.Result) {
		guard !closedAttemptLogged else { return }
		closedAttemptLogged = true
		UnlockAttemptLog.shared.record(result, photo: lastFacePixelBuffer)
	}

	/// One timing line per attempt, when it ends. Measurement only: nothing here
	/// is read by any branch, so unlock behaviour is identical either way.
	private func logAttemptTiming(outcome: String) {
		guard let start = attemptStartedAt else { return }
		func ms(_ instant: ContinuousClock.Instant?) -> String {
			guard let instant else { return "-" }
			let parts = start.duration(to: instant).components
			let whole: Int64 = parts.seconds * 1_000
			let fraction: Int64 = parts.attoseconds / 1_000_000_000_000_000
			return String(whole + fraction) + "ms"
		}
		let line = "outcome=\(outcome) camera=\(ms(self.cameraRunningAt)) firstFrame=\(ms(self.firstFrameAt))"
			+ " firstMatch=\(ms(self.firstMatchAt)) submitted=\(ms(self.passwordSubmittedAt))"
		Self.logger.notice("timing attempt ended \(line, privacy: .public)")
		attemptStartedAt = nil
		cameraRunningAt = nil
		firstFrameAt = nil
		firstMatchAt = nil
		passwordSubmittedAt = nil
		movementPresentedAt = nil
		movementDuration = nil
		movementPrompt = nil
		movementLookPasses = nil
	}

	/// The unlock split into its stages, for the Unlock Attempts list.
	private func attemptSteps() -> UnlockAttempt.Steps? {
		guard let start = attemptStartedAt else { return nil }
		func between(_ a: ContinuousClock.Instant?, _ b: ContinuousClock.Instant?) -> TimeInterval? {
			guard let a, let b, a <= b else { return nil }
			let parts = a.duration(to: b).components
			return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
		}
		return UnlockAttempt.Steps(
			camera: between(start, cameraRunningAt),
			recognise: between(cameraRunningAt, firstMatchAt),
			check: between(firstMatchAt, passwordSubmittedAt),
			macOS: between(passwordSubmittedAt, .now),
			movement: movementDuration,
			movementPrompt: movementPrompt,
			lookPasses: movementLookPasses)
	}

	private static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
		let parts = start.duration(to: .now).components
		return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
	}

	/// Asks the window server whether the screen is locked, right now.
	///
	/// The authoritative answer, unlike the `com.apple.screenIsLocked` notification, which
	/// tells us what was true when it was posted. Before replaying a password we need the
	/// current state, not a recent one.
	private static func screenIsLocked() -> Bool {
		guard
			let session = CGSessionCopyCurrentDictionary() as? [String: Any],
			let locked = session["CGSSessionScreenIsLocked"] as? Bool
		else {
			// Unknown state: assume unlocked, because the failure we must avoid is typing
			// a password when we should not have.
			return false
		}
		return locked
	}

	// MARK: - Attempt

	private func attemptUnlock(inputSnapshot: LockScreenInputSnapshot, identifier: UUID,
		prestarted: (camera: CameraController, started: Task<Void, Never>)? = nil) async {
		// Any early return below must not leave the early-started camera running.
		var adoptedPrestarted = false
		defer {
			if !adoptedPrestarted, let prestarted {
				prestarted.camera.stop()
				// Its start may still be in flight; stop again once it lands so a session
				// that finished starting after the first stop doesn't stay on.
				Task { @MainActor in
					await prestarted.started.value
					prestarted.camera.stop()
				}
			}
		}
		// Whatever ends the scan — an unlock, a rejection, the lockout, a camera that
		// died — the edge light goes out with it.
		SceneBrightness.reset()
		defer { LockScreenLight.shared.hide() }
		func report(_ outcome: LockScanDiagnostics.Outcome) {
			LockScanDiagnostics.shared.record(outcome, for: identifier)
		}
		guard UnlockGuard.embedderBlocker() == nil, store.isEnrolled, !store.isCorrupted,
			let lockedSession = LockedConsoleSession.current() else { report(.verificationUnavailable); return }
		// Only switched-on faces may unlock; a face turned off mid-attempt ends the attempt.
		let allowExternal = Preferences.shared.allowExternalCamera
		let available = CameraDevice.candidates(allowExternal: allowExternal).map(\.uniqueID)
		guard let choice = store.unlockCamera(allowExternal: allowExternal, available: available), !choice.cameraID.isEmpty else { report(.cameraUnavailable); return }
		let pinnedCamera = choice.cameraID
		let enrolledFaces = choice.faceIDs
		let movementCount = Preferences.shared.unlockMovementCount
		// First matching frame unlocks, when chosen for this movement count. Every frame
		// still passes the photo and screen check, and movements are still asked for.
		let instantUnlock = Preferences.shared.instantUnlock(for: movementCount)
		// Mask matching only runs alongside a movement challenge, so an upper-face
		// match is never the sole proof of presence. With the challenge off, the
		// setting does nothing at the lock screen rather than weakening anything.
		let maskUnlock = Preferences.shared.unlockWithMask && movementCount != .none
		let entryEmbedder = Embedders.best().identifier
		var inputGuard = LockScreenInputGuard(initial: inputSnapshot)
		// Baseline for the Space forgiveness below. Tracks the re-baseline, so a second
		// Space mid-scan is forgiven against the first one rather than the attempt start.
		var spaceBaseline = inputSnapshot
		func contextIsCurrent() -> Bool {
			guard !Task.isCancelled, isLocked, !Self.manualInputObserved,
				LockedConsoleSession.current() == lockedSession,
				lockout.mayAttempt(), !Preferences.shared.isPaused,
				UnlockExecutionPolicy.current.permitsScanning(passwordReplayEnabled: PasswordReplaySafety.isEnabled,
					keystrokeSelected: Preferences.shared.unlockBackend == .keystroke),
				Preferences.shared.unlockMovementCount == movementCount,
				(Preferences.shared.unlockWithMask && Preferences.shared.unlockMovementCount != .none) == maskUnlock,
				Embedders.best().identifier == entryEmbedder,
				!store.isCorrupted, Preferences.shared.allowExternalCamera == allowExternal else { return false }
			guard let current = store.unlockCamera(allowExternal: allowExternal, available: available),
				current.cameraID == pinnedCamera, current.faceIDs == enrolledFaces else { return false }
			return true
		}
		func requestIsCurrent() -> Bool {
			guard contextIsCurrent() else { return false }
			let current = LockScreenInputSnapshot.current()
			guard inputGuard.permits(current) else {
				// Space the monitor saw is a retry request, not typing: forgive exactly
				// one keyDown within 300 ms of it and re-baseline. Anything else stops
				// Gaze as before.
				if let pressed = lastSpaceAt, Date().timeIntervalSince(pressed) < 0.3,
					current.keys == spaceBaseline.keys + 1,
					current.leftClicks == spaceBaseline.leftClicks,
					current.rightClicks == spaceBaseline.rightClicks {
					lastSpaceAt = nil
					spaceBaseline = current
					inputGuard = LockScreenInputGuard(initial: current)
					return contextIsCurrent()
				}
				if !Self.manualInputObserved {
					Self.logger.notice("Manual input observed; yielding to macOS authentication until the next unlock.")
				}
				Self.manualInputObserved = true
				report(.manualInput)
				capsule.hide()
				return false
			}
			return true
		}
		guard requestIsCurrent() else { capsule.hide(); return }
		let antiSpoof: AntiSpoofGate? = AntiSpoofGate(spoof: SpoofDetector.shared)
		if let antiSpoof, !antiSpoof.isActive {
			report(.verificationUnavailable)
			Self.logger.error("Anti-spoof protection was requested but its model is unavailable. Refusing password submission.")
			capsule.update(phase: .notRecognised)
			return
		}
		guard requestIsCurrent() else { capsule.hide(); return }
		// The first recognition used to load both models mid-scan, stalling the loop for
		// over a second right after the first frame, which the stall check read as a dead
		// camera. They load here instead, while the camera is still starting.
		let embedder = store.embedder
		let warmUp = Task.detached(priority: .userInitiated) {
			embedder.warmUp()
			SpoofDetector.shared?.warmUp()
			IrisLocator.warmUp()
		}
		let camera = prestarted?.camera ?? CameraController(accessScope: .lockScreen)
		adoptedPrestarted = true
		let cameraRequestedAt = ContinuousClock.now
		if let prestarted {
			await prestarted.started.value
		} else {
			await camera.start(pinnedDeviceID: pinnedCamera)
		}
		await warmUp.value
		defer { camera.stop() }

		guard camera.state == .running, camera.boundDeviceID == pinnedCamera, requestIsCurrent() else {
			if contextIsCurrent() {
				report(.cameraUnavailable)
				cameraFailed = true
			}
			Self.logger.error("Camera unavailable: \(String(describing: camera.state))")
			return
		}
		cameraRunningAt = .now
		// The panel drops as soon as the camera is on, not when its first frame arrives,
		// so it never lags a second or more behind the camera light.
		capsule.update(phase: .scanning)
		var freshFrames = RecognitionFrameGate()
		var evaluatedContinuity: UInt64?
		let evaluator = UnlockFrameEvaluator(embedder: store.embedder, faces: store.faces.filter { $0.isEnabled && enrolledFaces.contains($0.id) }, antiSpoof: antiSpoof, allowsMaskUnlock: maskUnlock)
		let challenge: LivenessChallenge? = LivenessChallenge()
		var challengeGate = UnlockChallengeGate(requiredActions: movementCount.rawValue)
		// Opt-in render timing (GAZE_RENDER_DIAGNOSTICS=1). Measurement and logging only:
		// no branch below reads these values, so unlock behaviour is identical either way.
		// drawableWaitMs stays 0: this loop never acquires a drawable; the field exists
		// so windows correlate with the renderer's drawable-wait counters.
		let renderDiagnostics = RenderTiming.enabled
		let renderAttempt = String(identifier.uuidString.prefix(8))
		var renderTiming = RenderTiming(attemptID: renderAttempt)
		var renderPhase = "locked"
		let renderClockStart = ContinuousClock.now
		var renderPreviousTick: ContinuousClock.Instant?
		var tickCapsuleMs = 0.0
		var tickInferenceMs = 0.0
		func renderMs(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant) -> Double {
			let parts = from.duration(to: to).components
			return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
		}
		func updateCapsule(_ name: String, _ phase: NotchCapsuleModel.Phase) {
			guard renderDiagnostics else { capsule.update(phase: phase); return }
			let started = ContinuousClock.now
			capsule.update(phase: phase)
			tickCapsuleMs += renderMs(started, ContinuousClock.now)
			renderPhase = name
		}
		func resetMovementGuidance(reason: String) {
			challenge?.reset()
			guard challengeGate.reset() else { return }
			report(.scanning)
			updateCapsule("retry", .challenge(prompt: "Face the camera to retry", symbol: "viewfinder",
				hintX: 0, hintY: 0, pulses: false))
			StateBroadcast.post(.detecting)
			Self.logger.notice("Movement guidance withdrawn; reacquiring face. reason=\(reason, privacy: .public)")
		}

		var shownAt: Date?
		/// When the current unbroken run of matching frames began.
		var matchingHold = RecognitionMatchHold()
		var rejectionHold = RecognitionRejectionHold()
		/// The last moment anybody was in front of the camera.
		var lastFaceAt = Date()
		/// Set after a rejection, so the next try starts from a clean slate.
		var cooldownUntil: Date?
		/// When the current run of too-blurred frames began, so a second of them
		/// can ask for light before the search gives up on the face.
		var blurredSince: Date?
		/// Box of the last matched face. The next frame's candidates are tried in
		/// overlap order so the tracked subject is re-found without embedding the
		/// other faces when it is still there.
		var trackedBox: CGRect?

		// Counters, so "nobody in front of the camera" can say what it actually saw.
		//
		// That message was the only thing this loop reported on failure, and it is a
		// conclusion rather than an observation — it reads as "you walked away" when the
		// truth might be a camera delivering black frames, a face found and discarded by
		// the quality gate every time, or two faces in shot. Those need different fixes
		// and looked identical from outside.
		var ticks = 0
		var framesWithFace = 0
		var qualityRejects = 0
		var lastAbsence = "none"
		/// The highest score any frame reached this search.
		///
		/// Without it a search can see a face on dozens of frames and report no number at
		/// all, because a score is only logged once a rejection is *committed* — after
		/// `rejectAfter` seconds of continuous presence. Frames that came and went before
		/// that scored silently. "withFace=36" and "withFace=0" then look like the same
		/// fault when one is a camera problem and the other is a matching problem.
		var bestScore: Float = 0
		/// Which of the two quality rejections fired, and how close the frames came.
		///
		/// The counts say which gate to move; the extremes say how far. A largest-seen face
		/// of 0.17 against a 0.18 floor is a threshold that is barely wrong; 0.04 is a
		/// bounding box being measured in the wrong space.
		var tooSmall = 0
		var tooBlurred = 0
		var largestFace: CGFloat = 0
		var bestQuality: Float = 0
		/// The most recent frame-quality rejection this scan, so a search that ends
		/// without unlocking can say why. Measurement only.
		var lastRejection: FrameQuality.Rejection?
		/// Whether this scan already filed an attempt record, so the search-end
		/// fallback does not file a second one.
		var recordedAttempt = false

		Self.logger.notice(
			"""
			Search starting. embedder=\(self.store.embedder.identifier, privacy: .public) \
			threshold=\(self.store.embedder.matchThreshold) faces=\(self.store.faces.count)
			""")

		// Keeps looking until the person gives up, not until a stopwatch runs out.
		//
		// This used to be a single 12-second window from the moment the screen locked, and
		// one failure ended the whole thing: after being rejected once you could stand in
		// front of the camera indefinitely and nothing would happen until you locked the
		// screen again. The window now measures *absence* — twelve seconds with nobody in
		// front of the camera means you walked away, and that is when it stops. A face that
		// is present and rejected simply gets another go.
		//
		// Still bounded, and by the thing that should bound it: six rejections and the
		// lockout takes over.
		let attemptDeadline = ContinuousClock.now.advanced(by: .seconds(60))
		var previousPoll = ContinuousClock.now
		while requestIsCurrent(), ContinuousClock.now < attemptDeadline {
			let tickStart = ContinuousClock.now
			let tickGapMs = renderDiagnostics ? renderPreviousTick.map { renderMs($0, tickStart) } ?? 0 : 0
			if renderDiagnostics { renderPreviousTick = tickStart }
			defer {
				// `defer` cannot `return`, so the opt-in check wraps the body instead of guarding it.
				if renderDiagnostics {
					let tickStartMs = renderMs(renderClockStart, tickStart)
					if let window = renderTiming.record(tick: ticks, frameID: camera.frameID,
						phase: renderPhase, tickStartMs: tickStartMs, capsuleUpdateMs: tickCapsuleMs,
						callbackGapMs: tickGapMs, drawableWaitMs: 0, inferenceMs: tickInferenceMs) {
						Self.renderTimingLogger.notice("\(window, privacy: .public)")
					}
				}
			}
			tickCapsuleMs = 0
			tickInferenceMs = 0
			let delay = RecognitionScanPacing.delay(since: previousPoll, now: .now)
			if delay > .zero {
				do { try await Task.sleep(for: delay) }
				catch { return }
			}
			previousPoll = .now
			guard requestIsCurrent(), camera.state == .running,
				camera.boundDeviceID == pinnedCamera else { return }
			switch freshFrames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: .now) {
			case .stalled:
				report(freshFrames.hasReceivedFrame ? .cameraStalled : .firstFrameTimeout)
				let stage = freshFrames.hasReceivedFrame ? "running stream" : "first frame"
				Self.logger.error("Camera timed out at \(stage, privacy: .public); analyzed=\(camera.analyzedFrames) expired=\(camera.expiredFrames). No password submitted.")
				updateCapsule("notRecognised", .notRecognised)
				cameraFailed = true
				return
			case .waiting:
				continue
			case .fresh(let continuous):
				if shownAt == nil {
					report(.scanning)
					firstFrameAt = .now
					let elapsed = cameraRequestedAt.duration(to: .now).components
					let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
					Self.logger.notice("First fresh camera frame ready after \(milliseconds)ms; analyzed=\(camera.analyzedFrames) expired=\(camera.expiredFrames).")
					updateCapsule("scanning", .scanning)
					StateBroadcast.post(.detecting)
					shownAt = Date()
				}
				if !continuous {
					matchingHold.reset()
					rejectionHold.reset()
					trackedBox = nil
					resetMovementGuidance(reason: "frame gap")
				}
			}

			if challengeGate.expired(at: .now) {
				report(.notRecognized)
				Self.logger.notice("Challenge not answered in time; treating as a rejection.")
				lockout.recordFailure()
				UnlockAttemptLog.shared.record(.notRecognised,
					steps: UnlockAttempt.Steps(lookPasses: challenge?.lookPassLog),
					photo: camera.sample?.pixelBuffer, reason: .movementTimedOut)
				recordedAttempt = true
				StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
				updateCapsule("notRecognised", .notRecognised)
				challenge?.next()
				challengeGate.reset()
				matchingHold.reset()
				rejectionHold.reset()
				cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
				continue
			}

			ticks += 1
			// The screen is the only lamp a locked Mac has. Checked before the face, since
			// in a dark enough room there is no face to find until the light is on.
			if Preferences.shared.screenGlowInDark, !LockScreenLight.shared.isShowing,
				SceneBrightness.isDark() {
				LockScreenLight.shared.show()
				Self.lightNeededAt = Date()
			}
			guard !camera.faceMissing, var sample = camera.sample else {
				lastAbsence = camera.absence?.summary ?? "no sample"
				// Face left the frame — both runs are broken and start again from zero.
				matchingHold.reset()
				rejectionHold.reset()
				trackedBox = nil
				resetMovementGuidance(reason: "face unavailable")
				if Date().timeIntervalSince(lastFaceAt) >= searchWindow { break }
				continue
			}
			lastFaceAt = Date()
		lastFacePixelBuffer = sample.pixelBuffer


			// A beat after a rejection before looking again, so the panel has time to say
			// "not recognised" and the next attempt is not judged on the same frames.
			if let until = cooldownUntil {
				guard Date() >= until else { continue }
				cooldownUntil = nil
				report(.scanning)
				updateCapsule("scanning", .scanning)
				StateBroadcast.post(.detecting)
			}

			framesWithFace += 1
			// Every face in the frame is a candidate, largest first, with the tracked
			// subject reordered to the front: overlap re-finds it without embedding
			// the other faces when it is still there.
			var candidates = [sample] + sample.bystanders
			if let trackedBox {
				candidates.sort {
					Self.overlap($0.boundingBox, trackedBox) > Self.overlap($1.boundingBox, trackedBox)
				}
			}
			for candidate in candidates {
				largestFace = max(largestFace, candidate.boundingBox.height)
				bestQuality = max(bestQuality, candidate.quality)
			}
			let usable = candidates.filter { FrameQuality.rejection($0) == nil }
			guard !usable.isEmpty else {
				matchingHold.reset()
				rejectionHold.reset()
				resetMovementGuidance(reason: "frame quality")
				qualityRejects += 1
				let qualityRejection = FrameQuality.rejection(sample)
				lastRejection = qualityRejection
				switch qualityRejection {
				case .tooSmall: tooSmall += 1
				case .tooBlurred:
					tooBlurred += 1
					// A run of blurred faces is often the camera asking for light, not
					// the person refusing to hold still. A second of it is enough to ask.
					let since = blurredSince ?? Date()
					blurredSince = since
					// Only in a dim room: in daylight a blurred face is just movement.
					if Preferences.shared.screenGlowInDark, !LockScreenLight.shared.isShowing,
						Date().timeIntervalSince(since) >= 1,
						let brightness = SceneBrightness.current(), brightness < 0.25 {
						LockScreenLight.shared.show()
					}
				default: break
				}
				continue
			}
			blurredSince = nil

			let sampleFrameID = camera.frameID
			let sampleContinuity = camera.evidenceContinuity.revision
			if evaluatedContinuity != sampleContinuity {
				matchingHold.reset()
				rejectionHold.reset()
				trackedBox = nil
				resetMovementGuidance(reason: "camera continuity")
				evaluatedContinuity = sampleContinuity
			}
			guard let sampleCapturedAt = camera.lastFrameCapturedAt else { continue }
			let inferenceStarted = ContinuousClock.now
			var result = await evaluator.evaluate(usable[0])
			var frameBest = result.score
			var matchedSample: FaceSample? = result.matched ? usable[0] : nil
			// The tracked subject is tried first and the rest are skipped when it
			// matches, so a held look costs one embedding a frame. Otherwise every
			// usable face is tried until one matches; only a frame where none match
			// counts as a miss, so a stranger beside the owner never fails the frame.
			// Every later check (anti-spoof, movement) runs on the matched face.
			if matchedSample == nil {
				for candidate in usable.dropFirst() {
					let next = await evaluator.evaluate(candidate)
					frameBest = max(frameBest, next.score)
					if next.matched {
						result = next
						matchedSample = candidate
						break
					}
				}
			}
			// Candidates come from the same camera frame, so sampleFrameID captured
			// above is still correct after the swap.
			if let matchedSample { sample = matchedSample }
			if renderDiagnostics { tickInferenceMs = renderMs(inferenceStarted, ContinuousClock.now) }
			guard requestIsCurrent(), camera.state == .running,
				camera.boundDeviceID == pinnedCamera else { return }
			let evaluatedAt = ContinuousClock.now
			let age = sampleCapturedAt.duration(to: evaluatedAt)
			let continuityIntact = camera.evidenceContinuity.permits(sampleContinuity, at: evaluatedAt)
			guard continuityIntact, age <= CameraFrameLease.maximumAge else {
				if challengeGate.isPresented {
					let duration = inferenceStarted.duration(to: evaluatedAt).components
					let milliseconds = duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000
					Self.logger.notice("Movement evidence invalidated: continuityIntact=\(continuityIntact) expired=\(age > CameraFrameLease.maximumAge) inferenceMs=\(milliseconds).")
				}
				matchingHold.reset()
				rejectionHold.reset()
				trackedBox = nil
				resetMovementGuidance(reason: "stale inference")
				continue
			}
			bestScore = max(bestScore, frameBest)
		guard result.matched, let face = result.face else {
			// A head turned for the requested movement scores below the match
			// threshold, so a near-miss on the tracked face feeds the challenge
			// instead of wiping it. Anything else keeps the rejection path below.
			let turningScoreFloor = store.embedder.matchThreshold - 0.15
			let trackedContinuity = trackedBox.map {
				Self.overlap(sample.boundingBox, $0) >= Self.subjectChangeOverlap
			} ?? true
			let isSameFaceTurning = result.comparedIdentity && result.failure == nil
				&& result.score >= turningScoreFloor && trackedContinuity
			if isSameFaceTurning, let challenge, challengeGate.isPresented, !challengeGate.isVerified {
				guard challengeGate.admits(frameID: sampleFrameID, capturedAt: sampleCapturedAt, now: .now)
				else { continue }
				Self.logger.notice("Movement progress from turning frame; action=\(challenge.action.prompt, privacy: .public) score=\(result.score) returning=\(challenge.isReturningToRest).")
				let wasReturningToRest = challenge.isReturningToRest
				let consumption = challenge.consume(sample)
				if consumption.poseSourceInvalidated {
					matchingHold.reset()
					rejectionHold.reset()
					resetMovementGuidance(reason: "pose source changed")
					continue
				}
				if challenge.isReturningToRest && !wasReturningToRest {
					let hint = challenge.guidanceHint
					updateCapsule("return", .challenge(prompt: challenge.guidancePrompt,
						symbol: challenge.guidanceSymbol, hintX: hint.x, hintY: hint.y, pulses: hint.pulses,
						isReturningToRest: true))
					Self.logger.notice("Requested movement observed; waiting for return to rest. action=\(challenge.action.prompt, privacy: .public)")
				}
				if challenge.isComplete {
					challengeGate.completeAction()
					if !challengeGate.isVerified {
						challenge.next()
					}
				}
				continue
			}
			if isSameFaceTurning { continue }
			matchingHold.reset()
			if challengeGate.isPresented, let challenge {
					let pose = challenge.poseMeasurement(yaw: sample.pose.yaw, pitch: sample.pose.pitch,
						yawSource: sample.pose.yawSource, pitchSource: sample.pose.pitchSource)
					LockScanDiagnostics.shared.recordMovementFailure(.init(action: challenge.action.prompt,
						returning: challenge.isReturningToRest, comparedIdentity: result.comparedIdentity,
						score: result.score, threshold: store.embedder.matchThreshold,
						poseOffset: pose?.offset, poseTarget: pose?.target, returnTolerance: pose?.returnTolerance),
						for: identifier)
					let failure = result.failure?.rawValue ?? "belowThreshold"
					if renderDiagnostics {
						renderTiming.lastIdentity = "\(failure) score=\(result.score) compared=\(result.comparedIdentity)"
					}
					let identityAttempt = renderDiagnostics ? " attempt=\(renderAttempt)" : ""
					Self.logger.notice("Movement identity check failed; action=\(challenge.action.prompt, privacy: .public) compared=\(result.comparedIdentity) failure=\(failure, privacy: .public) score=\(result.score) returning=\(challenge.isReturningToRest)\(identityAttempt, privacy: .public). No movement proof retained.")
				}
				resetMovementGuidance(reason: "identity mismatch")

				// Long enough looking at a face that is not yours to call it a rejection.
				// Comfortably longer than the match has to hold, or a real face would be
				// turned away before it had the chance to succeed.
				if rejectionHold.consume(capturedAt: sampleCapturedAt, required: .seconds(Self.rejectAfter)) {
					report(.notRecognized)
					lockout.recordFailure()
					UnlockAttemptLog.shared.record(.unknownFace, photo: sample.pixelBuffer, reason: .differentPerson)
					recordedAttempt = true
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
					updateCapsule("notRecognised", .notRecognised)
					Self.logger.notice("Not recognised (score \(result.score)); will try again.")
					challenge?.next()
					challengeGate.reset()
					rejectionHold.reset()
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
				}
				continue
			}
			rejectionHold.reset()

		if firstMatchAt == nil { firstMatchAt = .now }

		// Remember the matched frame for learning, but only a full-face match —
			// a mask-path print lives in the same space but describes half a face,
			// and learned prints must stay comparable with the originals.
			if !result.viaUpperFace, let matchedPrint = result.matchedPrint {
				pendingLearnedPrint = (matchedPrint, face.id)
			}

			if let decision = result.spoofDecision {
				if case .unavailable = decision {
					report(.verificationUnavailable)
					Self.logger.error("Anti-spoof inference failed; refusing password submission.")
					updateCapsule("notRecognised", .notRecognised)
					return
				}
				if case .spoof(let reason, let score) = decision {
					report(.spoofRejected)
					// A spoof (matches the face but fails anti-spoof) is a rejection like any
					// other: shake the panel, count it toward lockout, and cool down before
					// the next look — otherwise it silently retried and nothing on screen
					// ever said no.
					Self.logger.notice("Match rejected by anti-spoof: \(reason, privacy: .public) (\(String(format: "%.3f", score), privacy: .public)).")
					lockout.recordFailure()
					UnlockAttemptLog.shared.record(.spoofRejected, photo: sample.pixelBuffer, reason: .photoOrScreen)
					recordedAttempt = true
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed, score: Double(score))
					updateCapsule("spoofRejected", .spoofRejected)
					challenge?.next()
					challengeGate.reset()
					matchingHold.reset()
					rejectionHold.reset()
					await evaluator.resetSpoofCues()
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
					continue
				}
			}
			guard result.permitsMatchHold(requiresAntiSpoof: true) else {
				report(.verificationUnavailable)
				matchingHold.reset()
				challenge?.reset()
				challengeGate.reset()
				updateCapsule("notRecognised", .notRecognised)
				return
			}
			if matchingHold.faceID != face.id {
				resetMovementGuidance(reason: "identity changed")
			} else if let trackedBox,
				Self.overlap(sample.boundingBox, trackedBox) < Self.subjectChangeOverlap
			{
				// Same enrolled face, different physical subject: it must not inherit the hold.
				matchingHold.reset()
				resetMovementGuidance(reason: "subject changed")
			}
			trackedBox = sample.boundingBox
			let heldMatch = matchingHold.consume(faceID: face.id, now: sampleCapturedAt,
				required: instantUnlock ? .zero : .seconds(movementCount == .none
					? Self.requiredMatchDuration : Self.requiredMatchDurationWithChallenge))
			// Ask for the movement once the face has matched briefly, instead of after the
			// whole hold. The hold keeps counting while the person moves, and the final gate
			// below still needs the full continuous hold, the movement and anti-spoof, so
			// nothing gets easier: the two waits just overlap instead of adding up. The
			// prompt still only ever appears for a face that already matched.
			let readyToAsk = movementCount != .none && matchingHold.consume(faceID: face.id,
				now: sampleCapturedAt, required: Self.challengeLead)
			if !challengeGate.isPresented && !challengeGate.isVerified {
				challenge?.prepareBaseline(sample)
			}
			guard heldMatch || readyToAsk || challengeGate.isPresented else { continue }

			// The movement challenge, if one was asked for.
			//
			// After the match and after anti-spoof, because there is no point asking a
			// stranger to blink — the demand is only meaningful once the face is already
			// accepted, and putting it earlier would show a prompt to anybody who walked
			// past. It is the last thing between recognition and the password.
			if let challenge, !challengeGate.isVerified {
				if !challengeGate.isPresented {
					guard challenge.isBaselineReady else { continue }
					guard capsule.canPresentGuidance else {
						report(.verificationUnavailable)
						Self.logger.error("Guidance panel is unavailable; refusing a hidden movement challenge.")
						capsule.hide()
						return
					}
					challengeGate.present(at: .now, frameID: sampleFrameID)
					movementPresentedAt = .now
					report(.movement)
					let hint = challenge.guidanceHint
					// Outward prompts carry the gate's progress in two-movement mode ("· 1 of 2"),
					// so the second prompt reads as progress rather than a reset. The return cue
					// below stays bare: the animated return is deliberately captionless.
					let outwardPrompt = NotchCapsuleModel.Phase.outwardPrompt(challenge.guidancePrompt,
						completedActions: challengeGate.completedActions, requiredActions: challengeGate.requiredActions)
					updateCapsule("challenge", .challenge(
						prompt: outwardPrompt,
						symbol: challenge.guidanceSymbol,
						hintX: hint.x, hintY: hint.y, pulses: hint.pulses))
					if renderDiagnostics { renderTiming.lastPrompt = challenge.action.prompt }
					let promptAttempt = renderDiagnostics ? " attempt=\(renderAttempt)" : ""
					Self.logger.notice("Movement prompt presented; action=\(challenge.action.prompt, privacy: .public); requiring fresh response \(challengeGate.completedActions + 1) of \(challengeGate.requiredActions)\(promptAttempt, privacy: .public).")
					continue
				}
				guard challengeGate.admits(frameID: sampleFrameID, capturedAt: sampleCapturedAt, now: .now)
				else { continue }
				let wasReturningToRest = challenge.isReturningToRest
				let consumption = challenge.consume(sample)
				if consumption.poseSourceInvalidated {
					matchingHold.reset()
					rejectionHold.reset()
					resetMovementGuidance(reason: "pose source changed")
					continue
				}
				if challenge.isReturningToRest && !wasReturningToRest {
					let hint = challenge.guidanceHint
					updateCapsule("return", .challenge(prompt: challenge.guidancePrompt,
						symbol: challenge.guidanceSymbol, hintX: hint.x, hintY: hint.y, pulses: hint.pulses,
						isReturningToRest: true))
					Self.logger.notice("Requested movement observed; waiting for return to rest. action=\(challenge.action.prompt, privacy: .public)")
				}
				guard challenge.isComplete else { continue }
				challengeGate.completeAction()
				if !challengeGate.isVerified {
					challenge.next()
					continue
				}
				if let presented = movementPresentedAt {
					movementDuration = Self.seconds(since: presented)
					movementPrompt = challenge.action.prompt
					movementLookPasses = challenge.lookPassLog
				}
			}
			guard heldMatch, challengeGate.isVerified else { continue }

			func evidenceIsCurrent() -> Bool {
				let now = ContinuousClock.now
				return contextIsCurrent() && challengeGate.isVerified && camera.state == .running
					&& camera.evidenceContinuity.permits(sampleContinuity, at: now)
					&& camera.boundDeviceID == pinnedCamera && capsule.canPresentGuidance
					&& sampleCapturedAt <= now && sampleCapturedAt.duration(to: now) <= CameraFrameLease.maximumAge
			}
			func proofStillCurrent() -> Bool {
				requestIsCurrent() && evidenceIsCurrent()
			}
			guard proofStillCurrent() else {
				capsule.hide()
				return
			}
			guard UnlockExecutionPolicy.current.permitsPasswordSubmission else {
				report(.scanOnlyPassed)
				Self.logger.notice("Scan-only diagnostic passed: identity, configured anti-spoof and \(challengeGate.requiredActions) movement response(s) verified. No credential was read or typed; unlock manually.")
				capsule.hide(after: 0.8)
				return
			}

			guard Self.submissionBudget.reserve() else { return }
			do {
				try KeystrokeUnlockBackend().submitPassword(if: proofStillCurrent, evidenceIsCurrent: evidenceIsCurrent)
			} catch {
				report(.submissionStopped)
				didSubmitPassword = false
				lockout.recordFailure()
				StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
				updateCapsule("notRecognised", .notRecognised)
				Self.logger.error("Unlock failed: \(error.localizedDescription)")
				return
			}
			didSubmitPassword = true
			passwordSubmittedAt = .now
			report(.submissionPending)
			let receiptID = UUID()
			submissionID = receiptID
			// Waiting, neutrally: the padlock stays closed with "Waiting for macOS" until the
			// Mac confirms the unlock. No tick and no opening padlock before then — either
			// would announce an outcome the login window has not reported yet.
			updateCapsule("pending", .pending)

			// Unless nothing happens. A password can be refused, and a panel left showing a
			// waiting state over a lock screen that never opened would insist something is
			// still in flight. Withdraw it instead.
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.unlockGracePeriod) {
				[weak self] in
				guard let self, self.isLocked, self.submissionID == receiptID else { return }
				LockScanDiagnostics.shared.record(.submissionUnconfirmed, for: identifier)
				Self.logger.notice("Screen did not unlock after submitting; withdrawing.")
				self.submissionID = nil
				self.didSubmitPassword = false
				self.lockout.recordFailure()
				StateBroadcast.post(self.lockout.isLockedOut ? .lockedOut : .failed)
				self.capsule.hide()
			}
			return
		}

		guard !Task.isCancelled else { return }
		if LockScanDiagnostics.shared.outcome?.isScanning == true { report(.ended) }

		// Rejections are counted where they happen, one per attempt, so there is nothing to
		// record here — the loop ended because the person left or because the lockout took
		// over, and neither is a new failure. Counting one here as well meant walking away
		// cost an attempt.
		Self.logger.notice(
			"""
			Search ended. ticks=\(ticks) withFace=\(framesWithFace) \
			qualityRejected=\(qualityRejects) (small=\(tooSmall) blurred=\(tooBlurred)) \
			largestFace=\(largestFace) bestQuality=\(bestQuality) best=\(bestScore) \
		lastAbsence=\(lastAbsence, privacy: .public)
		""")
		// The scan gave up without unlocking and nothing else filed it: say why, from
		// the most recent frame-quality rejection, so the attempt is explainable.
		if !recordedAttempt, !didSubmitPassword {
			// A face that was seen clearly but never matched gets no reason: nothing
			// in the frame explains it, and guessing would mislead.
			let reason: UnlockAttempt.Reason?
			if framesWithFace == 0 {
				reason = .noFace
			} else {
				switch lastRejection {
				case .tooSmall: reason = .tooFar
				case .tooBlurred: reason = .tooDark
				case .invalidMeasurements, nil: reason = nil
				}
			}
			UnlockAttemptLog.shared.record(.notRecognised, photo: lastFacePixelBuffer, reason: reason)
		}
		StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .idle)

		// Back to the padlock rather than vanishing — the Mac is still locked, and the
		// indicator should keep saying so.
		if isLocked {
			capsule.update(phase: .locked)
		}
	}
}
