import AppKit
import Foundation
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

	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager

	private var attempt: Task<Void, Never>?
	/// Whether this lock produced a recognised face and a submitted password.
	///
	/// The unlock animation must only play when *we* did it. The screen unlocking is not by
	/// itself evidence of that — Touch ID, a typed password and a paired Watch all raise the
	/// same notification, and playing "Gaze opened this" over someone else's unlock is a
	/// claim the app has no basis for.
	private var didSubmitPassword = false
	/// When the last wake trigger was honoured, so the pair of them counts as one.
	private var lastWakeTrigger: Date?
	/// Block-observer tokens, so `stop()` can actually unregister them.
	private var observers: [NSObjectProtocol] = []
	private(set) var isWatching = false
	private(set) var isLocked = false

	private let capsule = NotchCapsuleController()

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
	private static let requiredMatchDuration: TimeInterval = 2.0

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
	/// delivers black frames, which reads to the recogniser as "nobody there".
	private static let wakeSettle = Duration.milliseconds(700)

	/// How long to wait for the Mac to actually unlock before giving up on it.
	private static let unlockGracePeriod: TimeInterval = 3.0

	/// How long a face has to be looked at, without matching, before it counts as rejected.
	///
	/// Comfortably longer than `requiredMatchDuration`, or a face that needs a moment to be
	/// recognised would be turned away before it had the chance.
	private static let rejectAfter: TimeInterval = 4.0

	/// The pause between a rejection and the next attempt.
	private static let retryCooldown: TimeInterval = 2.0

	/// How long somebody gets to answer a movement challenge.
	///
	/// Long enough to read a glyph, understand what it is asking and do it — which is a
	/// slower sequence than it sounds the first few times, before the action becomes
	/// familiar. Short enough that a Mac left facing an empty room gives up rather than
	/// sitting with a prompt on screen.
	private static let challengeTimeout: TimeInterval = 8.0

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
	}

	func start() {
		guard !isWatching else { return }
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

		Self.logger.notice("Watching for screen lock and wake.")
	}

	func stop() {
		attempt?.cancel()
		attempt = nil
		isWatching = false
		lastWakeTrigger = nil
		for token in observers {
			DistributedNotificationCenter.default().removeObserver(token)
			NSWorkspace.shared.notificationCenter.removeObserver(token)
		}
		observers.removeAll()
	}

	// MARK: - Events

	private func screenLocked() {
		isLocked = true
		beginAttempt(trigger: "Screen locked")
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

		// Waking posts more than one notification — the system wakes, then the displays
		// do — and both mean the same thing here. Without this, the second one cancels
		// the attempt the first one started and the camera is torn down and rebuilt.
		if let last = lastWakeTrigger, Date().timeIntervalSince(last) < Self.wakeDebounce {
			return
		}
		lastWakeTrigger = Date()

		isLocked = true
		beginAttempt(trigger: "Woke to a locked screen", settle: Self.wakeSettle)
	}

	/// Everything both triggers do. Shared so the two cannot drift apart.
	///
	/// - Parameter settle: how long to wait before opening the camera. Zero when the
	///   screen locks in front of us, because the hardware is already awake; a beat after
	///   a wake, because it is not — asking too early returns a camera that reports
	///   running and delivers black frames for the first second.
	private func beginAttempt(trigger: String, settle: Duration = .zero) {
		guard Preferences.shared.unlockBackend == .keystroke else { return }
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

		Self.logger.notice("\(trigger, privacy: .public) — looking for a face.")

		// A padlock, immediately. It is a statement about the Mac's state, not a claim
		// that the camera is looking at anyone — that distinction is why the compact
		// locked phase exists separately from scanning.
		didSubmitPassword = false
		capsule.show(phase: .locked)
		// Every broadcast below is posted beside the capsule update that shows the same
		// thing, so the panel and any subscriber can never disagree about the state.
		StateBroadcast.reset()
		StateBroadcast.post(.locked)

		attempt?.cancel()
		attempt = Task {
			if settle > .zero {
				try? await Task.sleep(for: settle)
				guard !Task.isCancelled else { return }
			}
			await self.attemptUnlock()
		}
	}

	private func screenUnlocked() {
		isLocked = false
		StateBroadcast.post(.idle)
		// Whatever unlocked the Mac, we are done. Cancelling releases the camera promptly
		// rather than leaving the indicator lit after the user has typed their password.
		attempt?.cancel()
		attempt = nil

		guard didSubmitPassword else {
			// Unlocked by other means. Nothing to celebrate — just get out of the way.
			capsule.hide()
			return
		}
		didSubmitPassword = false

		// The Mac agreed. Retract to the resting bar and let the padlock open there, which
		// is the last beat of the sequence and the only one the user is still looking at.
		capsule.update(phase: .unlocked)
		capsule.hide(after: Self.unlockAnimationDuration)
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

	private func attemptUnlock() async {
		let camera = CameraController()
		await camera.start(
			pinnedDeviceID: Preferences.shared.requireBuiltInCamera
				? store.pinnedCameraID : nil)
		defer { camera.stop() }

		guard camera.state == .running else {
			Self.logger.error("Camera unavailable: \(String(describing: camera.state))")
			return
		}

		// Anti-spoof runs the object detector (see `AntiSpoofGate` — the passive texture model
		// is deliberately excluded, it calls real faces spoofs). Built once per attempt, and
		// only when the setting is on and the detector is actually present — otherwise the gate
		// is skipped entirely.
		let antiSpoof: AntiSpoofGate? = {
			guard Preferences.shared.livenessEnabled else { return nil }
			let gate = AntiSpoofGate(spoof: SpoofDetector())
			return gate.isActive ? gate : nil
		}()
		// The movement challenge, when the user has asked for one. Built per attempt so a
		// fresh action is chosen each time the screen locks — a recording of you blinking
		// answers a demand to blink, and only a demand you cannot predict is worth making.
		let challenge: LivenessChallenge? = Preferences.shared.requireChallenge
			? LivenessChallenge() : nil
		/// When the challenge was first put to the user, for timing it out.
		var challengeSince: Date?

		var shownAt: Date?
		/// When the current unbroken run of matching frames began.
		var matchingSince: Date?
		/// When the face currently in frame arrived, for deciding it has been rejected.
		var faceSince: Date?
		/// The last moment anybody was in front of the camera.
		var lastFaceAt = Date()
		/// Set after a rejection, so the next try starts from a clean slate.
		var cooldownUntil: Date?

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
		while !Task.isCancelled, isLocked, lockout.mayAttempt() {
			try? await Task.sleep(for: .milliseconds(60))

			ticks += 1
			guard !camera.faceMissing, let sample = camera.sample else {
				lastAbsence = camera.absence?.summary ?? "no sample"
				// Face left the frame — both runs are broken and start again from zero.
				matchingSince = nil
				faceSince = nil
				if Date().timeIntervalSince(lastFaceAt) >= searchWindow { break }
				continue
			}
			lastFaceAt = Date()

			// A beat after a rejection before looking again, so the panel has time to say
			// "not recognised" and the next attempt is not judged on the same frames.
			if let until = cooldownUntil {
				guard Date() >= until else { continue }
				cooldownUntil = nil
				capsule.update(phase: .scanning)
				StateBroadcast.post(.detecting)
			}

			// Shown on the very first frame containing a face. Waiting for a run of
			// frames sounded more robust, but recognition regularly completes in under
			// 200ms — the panel lost the race every time and never appeared at all.
			// Grows out of the padlock the moment there is a face to look at.
			if shownAt == nil {
				capsule.update(phase: .scanning)
				StateBroadcast.post(.detecting)
				shownAt = Date()
			}

			let presentSince = faceSince ?? Date()
			faceSince = presentSince

			// Too far, too small or too blurred to judge. Skip it rather than grade it: a
			// bad frame is not a rejection, and counting it as one burned attempts on frames
			// we should never have scored. A held match survives a brief blur this way.
			framesWithFace += 1
			guard FrameQuality.isUsable(sample) else {
				qualityRejects += 1
				continue
			}

			let result = store.matches(sample)
			guard result.matched else {
				matchingSince = nil

				// Long enough looking at a face that is not yours to call it a rejection.
				// Comfortably longer than the match has to hold, or a real face would be
				// turned away before it had the chance to succeed.
				if Date().timeIntervalSince(presentSince) >= Self.rejectAfter {
					lockout.recordFailure()
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
					capsule.update(phase: .notRecognised)
					Self.logger.notice("Not recognised (score \(result.score)); will try again.")
					faceSince = nil
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
				}
				continue
			}

			// Hold the match for the full duration. A single good frame is not enough:
			// it has to keep being you.
			let since = matchingSince ?? Date()
			matchingSince = since
			guard Date().timeIntervalSince(since) >= Self.requiredMatchDuration else {
				continue
			}

			if let antiSpoof {
				if case .spoof(let reason, let score) = antiSpoof.evaluate(sample) {
					// A spoof (matches the face but fails anti-spoof) is a rejection like any
					// other: shake the panel, count it toward lockout, and cool down before
					// the next look — otherwise it silently retried and nothing on screen
					// ever said no.
					Self.logger.notice("Match rejected by anti-spoof: \(reason, privacy: .public) (\(String(format: "%.3f", score), privacy: .public)).")
					lockout.recordFailure()
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed, score: Double(score))
					capsule.update(phase: .spoofRejected)
					matchingSince = nil
					faceSince = nil
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
					continue
				}
			}

			// The movement challenge, if one was asked for.
			//
			// After the match and after anti-spoof, because there is no point asking a
			// stranger to blink — the demand is only meaningful once the face is already
			// accepted, and putting it earlier would show a prompt to anybody who walked
			// past. It is the last thing between recognition and the password.
			if let challenge {
				challenge.consume(sample)

				guard challenge.isComplete else {
					let asked = challengeSince ?? Date()
					challengeSince = asked

					// Ask, in the panel's own vocabulary. It draws glyphs, not words, so the
					// action arrives as its symbol — an eye to blink, an arrow to turn.
					let hint = challenge.action.hint
					capsule.update(
						phase: .challenge(
							prompt: challenge.action.prompt,
							symbol: challenge.action.symbol,
							hintX: hint.x, hintY: hint.y, pulses: hint.pulses))

					// Give up rather than hold the panel open forever. Somebody who has
					// walked away, or whose camera cannot see the movement, gets the same
					// outcome as any other failed attempt instead of a prompt that never
					// resolves — and the next look starts from a fresh, different action.
					if Date().timeIntervalSince(asked) >= Self.challengeTimeout {
						Self.logger.notice("Challenge not answered in time; treating as a rejection.")
						lockout.recordFailure()
						StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
						capsule.update(phase: .notRecognised)
						challenge.next()
						challengeSince = nil
						matchingSince = nil
						faceSince = nil
						cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
					}
					continue
				}
			}

			// Re-check cancellation before typing. The user may have entered their
			// password while we were deciding, and replaying it afterwards would type
			// the password into whatever is now focused.
			guard !Task.isCancelled, isLocked else { return }

			lockout.recordSuccess()
			Self.logger.notice("Recognised (score \(result.score)) — unlocking.")

			// Let the checkmark actually draw before the password goes in.
			capsule.update(phase: .success)
			StateBroadcast.post(.succeeded, score: Double(result.score))
			try? await Task.sleep(for: .milliseconds(480))

			// Re-check *here*, immediately before posting keystrokes, and against the
			// window server rather than our own cached flag.
			//
			// This is the last line of defence against the worst thing this app can do.
			// Checking before the animation delay was not enough: the user can unlock with
			// Touch ID during it, and then the keystrokes land in whatever application is
			// now focused — typing their account password into a terminal, a chat window,
			// anything. `try?` on the sleep above also swallows cancellation, so a
			// cancelled task reaches this point too.
			//
			// Never trust `isLocked` alone for this; it depends on a notification arriving
			// in time, and this decision cannot afford to be a step behind.
			guard !Task.isCancelled, isLocked, Self.screenIsLocked() else {
				Self.logger.notice("Unlocked by other means during the animation; not typing.")
				capsule.hide()
				return
			}

			do {
				try await KeystrokeUnlockBackend().unlock()
			} catch {
				Self.logger.error("Unlock failed: \(error.localizedDescription)")
			}
			// The panel stays up on the tick. `screenUnlocked` drives what happens next,
			// because the padlock should open when the Mac actually opens — not when we
			// finish typing at it.
			didSubmitPassword = true

			// Unless nothing happens. A password can be refused, and a panel left showing a
			// tick over a lock screen that never opened is the app insisting it succeeded.
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.unlockGracePeriod) {
				[weak self] in
				guard let self, self.isLocked else { return }
				Self.logger.notice("Screen did not unlock after submitting; withdrawing.")
				self.didSubmitPassword = false
				self.capsule.hide()
			}
			return
		}

		guard !Task.isCancelled else { return }

		// Rejections are counted where they happen, one per attempt, so there is nothing to
		// record here — the loop ended because the person left or because the lockout took
		// over, and neither is a new failure. Counting one here as well meant walking away
		// cost an attempt.
		Self.logger.notice(
			"Search ended. ticks=\(ticks) withFace=\(framesWithFace) qualityRejected=\(qualityRejects) lastAbsence=\(lastAbsence, privacy: .public)")
		StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .idle)

		// Back to the padlock rather than vanishing — the Mac is still locked, and the
		// indicator should keep saying so.
		if isLocked {
			capsule.update(phase: .locked)
		}
	}
}
