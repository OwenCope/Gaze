import AppKit
import AVFoundation
import CoreGraphics
import IOKit.pwr_mgt
import Observation
import os

/// Uses input inactivity to trigger a bounded camera check. Only sustained,
/// fresh no-face evidence may request a lock. Any face cancels the check;
/// this feature detects presence, not identity.
@Observable
@MainActor
final class PresenceWatcher {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Presence")

	private static let armIdle = PresenceCheckSchedule.idleRequired
	private static let tick: Duration = .seconds(5)
	private static let absenceRequired: Duration = .seconds(4)
	private static let startupAllowance: Duration = .seconds(6)
	private static let sampleInterval: Duration = .milliseconds(400)

	private let store: FaceEnrollmentStore
	private var loop: Task<Void, Never>?
	private var confirmationGeneration: UInt64?
	private var generation: UInt64 = 0
	private var activeCamera: CameraController?
	private var schedule = PresenceCheckSchedule()

	init(store: FaceEnrollmentStore) {
		self.store = store
	}

	func start() {
		guard loop == nil else { return }
		generation &+= 1
		let runningGeneration = generation
		loop = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.tick)
				guard let self, !Task.isCancelled, self.generation == runningGeneration else { return }
				await self.tickOnce()
			}
		}
		Self.logger.notice("Walk-away locking enabled; camera checks require idle input and permissions.")
	}

	func stop() {
		generation &+= 1
		loop?.cancel()
		loop = nil
		activeCamera?.stop()
		activeCamera = nil
		confirmationGeneration = nil
		schedule = PresenceCheckSchedule()
	}

	// MARK: - The check

	private func tickOnce() async {
		guard schedule.permits(idleSeconds: Self.idleSeconds(), at: .now),
			confirmationGeneration == nil else { return }
		let session = AutofillSessionLease()
		defer { session.invalidate() }
		let myGeneration = generation
		guard decision(generation: myGeneration, session: session, absenceProven: true).allowsLock else { return }

		confirmationGeneration = myGeneration
		defer {
			// A stopped task must not clear a newer check's state or retry deadline.
			if confirmationGeneration == myGeneration {
				confirmationGeneration = nil
				schedule.finished(at: .now)
			}
		}
		guard let capturedAt = await confirmedAbsence(generation: myGeneration, session: session) else { return }
		let now = ContinuousClock.now
		guard decision(generation: myGeneration, session: session,
			absenceProven: capturedAt <= now && capturedAt.duration(to: now) <= CameraFrameLease.maximumAge).allowsLock else { return }
		Self.logger.notice("Sustained absence detected; requesting screen lock.")
		ScreenLock.now()
	}

	private func decision(generation expected: UInt64, session: AutofillSessionLease,
		absenceProven: Bool) -> PresenceLockDecision {
		PresenceLockDecision(
			executionPermitsLocking: UnlockExecutionPolicy.current.permitsAutomaticLocking,
			permissionsGranted: AXIsProcessTrusted()
				&& AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
			walkAwayEnabled: Preferences.shared.walkAwayLock,
			paused: Preferences.shared.isPaused,
			cancelled: Task.isCancelled,
			generationCurrent: expected == generation,
			sessionUnlockedAndActive: session.isValid,
			inputIdle: Self.idleSeconds() >= Self.armIdle,
			displayAssertionHeld: Self.displaySleepIsPrevented(),
			absenceProven: absenceProven)
	}

	private func confirmedAbsence(generation expected: UInt64, session: AutofillSessionLease) async -> ContinuousClock.Instant? {
		let camera = CameraController()
		activeCamera = camera
		let startedAt = ContinuousClock.now
		let evidenceDeadline = startedAt.advanced(by: Self.startupAllowance)
		let deadline = evidenceDeadline.advanced(by: Self.absenceRequired)
		var gate = PresenceAbsenceGate(requiredAbsence: Self.seconds(Self.absenceRequired))
		var verdict = PresenceAbsenceGate.Verdict.needMore
		var receivedFrame = false
		// Observe each analyzed frame: a face or analysis failure between timer ticks
		// must still cancel or invalidate the absence proof.
		// Documented main-actor, but the closure type is non-isolated; assume isolation
		// before touching the gate state the polling loop below reads.
		camera.onFrameAnalyzed = { absence, frameID, capturedAt in
			MainActor.assumeIsolated {
				guard verdict != .present else { return }
				receivedFrame = true
				verdict = gate.update(.init(sample: Self.sampleKind(absence), frameID: frameID,
					capturedAt: Self.seconds(startedAt.duration(to: capturedAt)),
					observedAt: Self.seconds(startedAt.duration(to: .now))))
			}
		}
		session.onInvalidation = { [weak camera] in camera?.stop() }
		var startupFinished = false
		let pinnedCamera = Preferences.shared.requireBuiltInCamera ? store.pinnedCameraID : nil
		let startup = Task {
			await camera.start(pinnedDeviceID: pinnedCamera)
			startupFinished = true
		}
		defer {
			startup.cancel()
			session.onInvalidation = nil
			camera.onFrameAnalyzed = nil
			camera.stop()
			if activeCamera === camera { activeCamera = nil }
		}

		while ContinuousClock.now < deadline {
			guard decision(generation: expected, session: session, absenceProven: true).allowsLock else { return nil }
			if startupFinished && camera.state != .running { return nil }
			if verdict == .present { return nil }
			if verdict == .absent {
				guard camera.state == .running, camera.absence == .noFace,
					let capturedAt = camera.lastFrameCapturedAt else { return nil }
				let now = ContinuousClock.now
				return capturedAt <= now && capturedAt.duration(to: now) <= CameraFrameLease.maximumAge ? capturedAt : nil
			}
			if !receivedFrame && ContinuousClock.now >= evidenceDeadline { return nil }
			do { try await Task.sleep(for: Self.sampleInterval) }
			catch { return nil }
		}
		return nil
	}

	private static func sampleKind(_ absence: FaceAbsence?) -> PresenceAbsenceGate.Sample {
		switch absence {
		case .none, .multipleFaces, .analysisFailed:
			// analysisFailed means the face detector succeeded but landmarks did not.
			return .facePresent
		case .noFace:
			return .noFace
		case .detectionFailed:
			return .indeterminate
		}
	}

	// MARK: - System state

	/// Seconds since the last keyboard or pointer event anywhere in the session.
	private static func idleSeconds() -> TimeInterval {
		// `~0` is the documented "any event type" wildcard; there is no named constant for
		// it, and asking per-type would miss whichever type the user is actually using.
		guard let any = CGEventType(rawValue: ~0) else { return 0 }
		return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
	}

	private static func seconds(_ duration: Duration) -> TimeInterval {
		let parts = duration.components
		return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
	}

	/// Display-awake assertions suppress checks; they are not proof of media playback.
	private static func displaySleepIsPrevented() -> Bool {
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
				if let type, watching.contains(type) {
					let level = assertion[kIOPMAssertionLevelKey as String] as? NSNumber
					if (level?.uint32Value ?? UInt32(kIOPMAssertionLevelOn)) != UInt32(kIOPMAssertionLevelOff) { return true }
				}
			}
		}
		return false
	}
}
