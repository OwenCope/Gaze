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

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "LockWatcher")

	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager

	private var attempt: Task<Void, Never>?
	/// Whether this lock produced a recognised face and a submitted password.
	///
	/// The unlock animation must only play when *we* did it. The screen unlocking is not by
	/// itself evidence of that — Touch ID, a typed password and a paired Watch all raise the
	/// same notification, and playing "Face ID opened this" over someone else's unlock is a
	/// claim the app has no basis for.
	private var didSubmitPassword = false
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
	private static let unlockAnimationDuration: TimeInterval = 0.7

	/// How long to wait for the Mac to actually unlock before giving up on it.
	private static let unlockGracePeriod: TimeInterval = 3.0

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
	}

	func start() {
		guard !isWatching else { return }
		isWatching = true

		let centre = DistributedNotificationCenter.default()
		centre.addObserver(
			forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.screenLocked() }
		}
		centre.addObserver(
			forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.screenUnlocked() }
		}

		Self.logger.notice("Watching for screen lock.")
	}

	func stop() {
		attempt?.cancel()
		attempt = nil
		isWatching = false
		DistributedNotificationCenter.default().removeObserver(self)
	}

	// MARK: - Events

	private func screenLocked() {
		isLocked = true
		guard Preferences.shared.unlockBackend == .keystroke else { return }
		guard store.isEnrolled else { return }
		guard lockout.mayAttempt() else {
			Self.logger.notice("Screen locked while locked out; not looking.")
			StateBroadcast.post(.lockedOut)
			return
		}

		Self.logger.notice("Screen locked — looking for a face.")

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
		attempt = Task { await self.attemptUnlock() }
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
				? store.enrollment?.cameraID : nil)
		defer { camera.stop() }

		guard camera.state == .running else {
			Self.logger.error("Camera unavailable: \(String(describing: camera.state))")
			return
		}

		let liveness = Preferences.shared.livenessEnabled ? Liveness.detector() : nil
		let deadline = Date().addingTimeInterval(searchWindow)
		var shownAt: Date?
		/// When the current unbroken run of matching frames began.
		var matchingSince: Date?

		while Date() < deadline, !Task.isCancelled {
			try? await Task.sleep(for: .milliseconds(60))

			guard !camera.faceMissing, let sample = camera.sample else {
				// Face left the frame — the run is broken and starts again from zero.
				matchingSince = nil
				continue
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

			let result = store.matches(sample)
			guard result.matched else {
				matchingSince = nil
				continue
			}

			// Hold the match for the full duration. A single good frame is not enough:
			// it has to keep being you.
			let since = matchingSince ?? Date()
			matchingSince = since
			guard Date().timeIntervalSince(since) >= Self.requiredMatchDuration else {
				continue
			}

			if let liveness {
				guard let score = liveness.score(sample), score >= liveness.threshold else {
					Self.logger.notice("Match rejected by liveness.")
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
		lockout.recordFailure()
		Self.logger.notice("No match within the search window.")

		// Only worth saying "not recognised" if we actually showed the user we were
		// looking; otherwise the panel would appear for the first time to report a
		// failure at someone who never saw it scanning.
		StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)

		if shownAt != nil {
			capsule.update(phase: .notRecognised)
			// Back to the padlock rather than vanishing — the Mac is still locked, and the
			// indicator should keep saying so.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
				guard let self, self.isLocked else { return }
				self.capsule.update(phase: .locked)
			}
		}
	}
}
