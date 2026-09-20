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

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
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

		Self.logger.notice("Watching for screen lock and wake.")
	}

	func stop() {
		if let diagnosticID { LockScanDiagnostics.shared.cancel(for: diagnosticID) }
		submissionID = nil
		didSubmitPassword = false
		attempt?.cancel()
		attempt = nil
		attemptID = nil
		capsule.hide()
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
		guard Self.screenIsLocked() else { return }
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

		// A padlock, immediately. It is a statement about the Mac's state, not a claim
		// that the camera is looking at anyone — that distinction is why the compact
		// locked phase exists separately from scanning.
		didSubmitPassword = false
		capsule.show(phase: .locked)
		// Every broadcast below is posted beside the capsule update that shows the same
		// thing, so the panel and any subscriber can never disagree about the state.
		StateBroadcast.reset()
		StateBroadcast.post(.locked)

		let inputSnapshot = LockScreenInputSnapshot.current()
		let identifier = UUID()
		attemptID = identifier
		diagnosticID = identifier
		LockScanDiagnostics.shared.begin(identifier)
		attempt = Task {
			defer {
				LockScanDiagnostics.shared.finishScanning(for: identifier)
				if self.attemptID == identifier {
					self.attempt = nil
					self.attemptID = nil
				}
			}
			if settle > .zero {
				try? await Task.sleep(for: settle)
				guard !Task.isCancelled else { return }
			}
			await self.attemptUnlock(inputSnapshot: inputSnapshot, identifier: identifier)
		}
	}

	private func screenUnlocked() {
		guard AutofillConsoleSession.current() != nil else { return }
		if let diagnosticID {
			if didSubmitPassword { LockScanDiagnostics.shared.record(.unlocked, for: diagnosticID) }
			else { LockScanDiagnostics.shared.finishScanning(for: diagnosticID) }
		}
		Self.submissionBudget.resetAfterVerifiedUnlock()
		Self.manualInputObserved = false
		submissionID = nil
		isLocked = false
		StateBroadcast.post(.idle)
		// Whatever unlocked the Mac, we are done. Cancelling releases the camera promptly
		// rather than leaving the indicator lit after the user has typed their password.
		attempt?.cancel()
		attempt = nil
		attemptID = nil

		guard didSubmitPassword else {
			// Unlocked by other means. Nothing to celebrate — just get out of the way.
			capsule.hide()
			return
		}
		didSubmitPassword = false
		lockout.recordSuccess()
		StateBroadcast.post(.succeeded)

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

	private func attemptUnlock(inputSnapshot: LockScreenInputSnapshot, identifier: UUID) async {
		func report(_ outcome: LockScanDiagnostics.Outcome) {
			LockScanDiagnostics.shared.record(outcome, for: identifier)
		}
		guard UnlockGuard.embedderBlocker() == nil, store.isEnrolled, !store.isCorrupted,
			let lockedSession = LockedConsoleSession.current() else { report(.verificationUnavailable); return }
		let enrolledFaces = store.faces.map(\.id)
		guard let pinnedCamera = store.pinnedCameraID, !pinnedCamera.isEmpty else { report(.cameraUnavailable); return }
		let antiSpoofEnabled = Preferences.shared.livenessEnabled
		let movementCount = Preferences.shared.unlockMovementCount
		var inputGuard = LockScreenInputGuard(initial: inputSnapshot)
		func contextIsCurrent() -> Bool {
			guard !Task.isCancelled, isLocked, !Self.manualInputObserved,
				LockedConsoleSession.current() == lockedSession,
				lockout.mayAttempt(), !Preferences.shared.isPaused,
				UnlockExecutionPolicy.current.permitsScanning(passwordReplayEnabled: PasswordReplaySafety.isEnabled,
					keystrokeSelected: Preferences.shared.unlockBackend == .keystroke),
				Preferences.shared.livenessEnabled == antiSpoofEnabled,
				Preferences.shared.unlockMovementCount == movementCount,
				!store.isCorrupted, store.faces.map(\.id) == enrolledFaces,
				store.pinnedCameraID == pinnedCamera else { return false }
			return true
		}
		func requestIsCurrent() -> Bool {
			guard contextIsCurrent() else { return false }
			guard inputGuard.permits(.current()) else {
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
		let antiSpoof: AntiSpoofGate? = {
			guard antiSpoofEnabled else { return nil }
			return AntiSpoofGate(spoof: SpoofDetector.shared)
		}()
		if let antiSpoof, !antiSpoof.isActive {
			report(.verificationUnavailable)
			Self.logger.error("Anti-spoof protection was requested but its model is unavailable. Refusing password submission.")
			capsule.update(phase: .notRecognised)
			return
		}
		guard requestIsCurrent() else { capsule.hide(); return }
		let camera = CameraController(accessScope: .lockScreen)
		let cameraRequestedAt = ContinuousClock.now
		await camera.start(pinnedDeviceID: pinnedCamera)
		defer { camera.stop() }

		guard camera.state == .running, camera.boundDeviceID == pinnedCamera, requestIsCurrent() else {
			if contextIsCurrent() { report(.cameraUnavailable) }
			Self.logger.error("Camera unavailable: \(String(describing: camera.state))")
			return
		}
		var freshFrames = RecognitionFrameGate()
		var evaluatedContinuity: UInt64?
		let evaluator = UnlockFrameEvaluator(embedder: store.embedder, faces: store.faces, antiSpoof: antiSpoof)
		let challenge: LivenessChallenge? = LivenessChallenge()
		var challengeGate = UnlockChallengeGate(requiredActions: movementCount.rawValue)
		func resetMovementGuidance(reason: String) {
			challenge?.reset()
			guard challengeGate.reset() else { return }
			report(.scanning)
			capsule.update(phase: .challenge(prompt: "Face the camera to retry", symbol: "viewfinder",
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
				capsule.update(phase: .notRecognised)
				return
			case .waiting:
				continue
			case .fresh(let continuous):
				if shownAt == nil {
					report(.scanning)
					let elapsed = cameraRequestedAt.duration(to: .now).components
					let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
					Self.logger.notice("First fresh camera frame ready after \(milliseconds)ms; analyzed=\(camera.analyzedFrames) expired=\(camera.expiredFrames).")
					capsule.update(phase: .scanning)
					StateBroadcast.post(.detecting)
					shownAt = Date()
				}
				if !continuous {
					matchingHold.reset()
					rejectionHold.reset()
					resetMovementGuidance(reason: "frame gap")
				}
			}

			if challengeGate.expired(at: .now) {
				report(.notRecognized)
				Self.logger.notice("Challenge not answered in time; treating as a rejection.")
				lockout.recordFailure()
				StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
				capsule.update(phase: .notRecognised)
				challenge?.next()
				challengeGate.reset()
				matchingHold.reset()
				rejectionHold.reset()
				cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
				continue
			}

			ticks += 1
			guard !camera.faceMissing, let sample = camera.sample else {
				lastAbsence = camera.absence?.summary ?? "no sample"
				// Face left the frame — both runs are broken and start again from zero.
				matchingHold.reset()
				rejectionHold.reset()
				resetMovementGuidance(reason: "face unavailable")
				if Date().timeIntervalSince(lastFaceAt) >= searchWindow { break }
				continue
			}
			lastFaceAt = Date()

			// A beat after a rejection before looking again, so the panel has time to say
			// "not recognised" and the next attempt is not judged on the same frames.
			if let until = cooldownUntil {
				guard Date() >= until else { continue }
				cooldownUntil = nil
				report(.scanning)
				capsule.update(phase: .scanning)
				StateBroadcast.post(.detecting)
			}

			framesWithFace += 1
			largestFace = max(largestFace, sample.boundingBox.height)
			bestQuality = max(bestQuality, sample.quality)
			if let rejection = FrameQuality.rejection(sample) {
				matchingHold.reset()
				rejectionHold.reset()
				resetMovementGuidance(reason: "frame quality")
				qualityRejects += 1
				switch rejection {
				case .invalidMeasurements: break
				case .tooSmall: tooSmall += 1
				case .tooBlurred: tooBlurred += 1
				}
				continue
			}

			let sampleFrameID = camera.frameID
			let sampleContinuity = camera.evidenceContinuity.revision
			if evaluatedContinuity != sampleContinuity {
				matchingHold.reset()
				rejectionHold.reset()
				resetMovementGuidance(reason: "camera continuity")
				evaluatedContinuity = sampleContinuity
			}
			guard let sampleCapturedAt = camera.lastFrameCapturedAt else { continue }
			let inferenceStarted = ContinuousClock.now
			let result = await evaluator.evaluate(sample)
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
				resetMovementGuidance(reason: "stale inference")
				continue
			}
			bestScore = max(bestScore, result.score)
			guard result.matched, let face = result.face else {
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
					Self.logger.notice("Movement identity check failed; action=\(challenge.action.prompt, privacy: .public) compared=\(result.comparedIdentity) failure=\(failure, privacy: .public) score=\(result.score) returning=\(challenge.isReturningToRest). No movement proof retained.")
				}
				resetMovementGuidance(reason: "identity mismatch")

				// Long enough looking at a face that is not yours to call it a rejection.
				// Comfortably longer than the match has to hold, or a real face would be
				// turned away before it had the chance to succeed.
				if rejectionHold.consume(capturedAt: sampleCapturedAt, required: .seconds(Self.rejectAfter)) {
					report(.notRecognized)
					lockout.recordFailure()
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed)
					capsule.update(phase: .notRecognised)
					Self.logger.notice("Not recognised (score \(result.score)); will try again.")
					challenge?.next()
					challengeGate.reset()
					rejectionHold.reset()
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
				}
				continue
			}
			rejectionHold.reset()

			if let decision = result.spoofDecision {
				if case .unavailable = decision {
					report(.verificationUnavailable)
					Self.logger.error("Anti-spoof inference failed; refusing password submission.")
					capsule.update(phase: .notRecognised)
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
					StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .failed, score: Double(score))
					capsule.update(phase: .spoofRejected)
					challenge?.next()
					challengeGate.reset()
					matchingHold.reset()
					rejectionHold.reset()
					cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
					continue
				}
			}
			guard result.permitsMatchHold(requiresAntiSpoof: antiSpoofEnabled) else {
				report(.verificationUnavailable)
				matchingHold.reset()
				challenge?.reset()
				challengeGate.reset()
				capsule.update(phase: .notRecognised)
				return
			}
			if matchingHold.faceID != face.id {
				resetMovementGuidance(reason: "identity changed")
			}
			let heldMatch = matchingHold.consume(faceID: face.id, now: sampleCapturedAt,
				required: .seconds(Self.requiredMatchDuration))
			if !challengeGate.isPresented && !challengeGate.isVerified {
				challenge?.prepareBaseline(sample)
			}
			guard heldMatch || challengeGate.isPresented else { continue }

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
					report(.movement)
					let hint = challenge.guidanceHint
					// Outward prompts carry the gate's progress in two-movement mode ("· 1 of 2"),
					// so the second prompt reads as progress rather than a reset. The return cue
					// below stays bare: the animated return is deliberately captionless.
					let outwardPrompt = NotchCapsuleModel.Phase.outwardPrompt(challenge.guidancePrompt,
						completedActions: challengeGate.completedActions, requiredActions: challengeGate.requiredActions)
					capsule.update(
						phase: .challenge(
							prompt: outwardPrompt,
							symbol: challenge.guidanceSymbol,
							hintX: hint.x, hintY: hint.y, pulses: hint.pulses))
					Self.logger.notice("Movement prompt presented; action=\(challenge.action.prompt, privacy: .public); requiring fresh response \(challengeGate.completedActions + 1) of \(challengeGate.requiredActions).")
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
					capsule.update(phase: .challenge(prompt: challenge.guidancePrompt,
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
				capsule.update(phase: .notRecognised)
				Self.logger.error("Unlock failed: \(error.localizedDescription)")
				return
			}
			didSubmitPassword = true
			report(.submissionPending)
			let receiptID = UUID()
			submissionID = receiptID
			// Waiting, neutrally: the padlock stays closed with "Waiting for macOS" until the
			// Mac confirms the unlock. No tick and no opening padlock before then — either
			// would announce an outcome the login window has not reported yet.
			capsule.update(phase: .pending)

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
		StateBroadcast.post(lockout.isLockedOut ? .lockedOut : .idle)

		// Back to the padlock rather than vanishing — the Mac is still locked, and the
		// indicator should keep saying so.
		if isLocked {
			capsule.update(phase: .locked)
		}
	}
}
