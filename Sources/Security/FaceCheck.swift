import AppKit
import os

/// "Is this the enrolled user, right now?" — asked once, answered yes or no.
///
/// `LockWatcher` has its own version of this loop and keeps it, because unlocking the Mac
/// is not the same question. It drives the notch panel through four phases, runs the
/// anti-spoof gate and the movement challenge, records failures against the lockout
/// counter, and retries for as long as the screen stays locked. None of that belongs to
/// filling in a password field.
///
/// What this shares with it is the part that must not be reimplemented differently: frames
/// are quality-gated before they are scored, and a match has to *hold* rather than land
/// once. A single good frame is a coincidence often enough to matter when the thing on the
/// other side of the decision is a stored credential.
///
@MainActor
enum FaceCheck {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "FaceCheck")

	/// How long to keep looking before giving up. Short: this runs while the user is
	/// waiting with a text field focused, and a spinner that outlasts typing the password
	/// by hand is worse than not offering the feature.
	private static let timeout: Duration = .seconds(6)
	/// How long the match has to keep being true.
	private static let hold: Duration = .milliseconds(350)
	private static let sampleInterval: Duration = .milliseconds(80)

	/// Opens the camera, looks for an enrolled face, and closes it again.
	///
	static func authenticate(
		using store: FaceEnrollmentStore, warm: CameraController? = nil,
		requestIsValid: () -> Bool = { AutofillConsoleSession.current() != nil }
	) async -> Bool {
		guard store.isEnrolled, !store.isCorrupted, UnlockGuard.embedderBlocker() == nil,
			let pinnedCamera = store.pinnedCameraID, !pinnedCamera.isEmpty,
			!Task.isCancelled, requestIsValid() else { return false }
		let enrolledFaces = store.faces.map(\.id)

		let camera = warm ?? CameraController()
		if warm == nil {
			await camera.start(pinnedDeviceID: pinnedCamera)
		}
		defer { if warm == nil { camera.stop() } }

		guard camera.state == .running, camera.boundDeviceID == pinnedCamera, requestIsValid() else {
			logger.error("Face check skipped: camera unavailable.")
			return false
		}

		let deadline = ContinuousClock.now.advanced(by: timeout)
		var matchingHold = RecognitionMatchHold()
		var freshFrames = RecognitionFrameGate()
		let evaluator = UnlockFrameEvaluator(
			embedder: store.embedder, faces: store.faces, antiSpoof: nil)

		while ContinuousClock.now < deadline {
			guard !Task.isCancelled, !Preferences.shared.isPaused, camera.state == .running,
				camera.boundDeviceID == pinnedCamera, !store.isCorrupted,
				store.faces.map(\.id) == enrolledFaces, requestIsValid() else {
				return false
			}
			let now = ContinuousClock.now
			switch freshFrames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: now) {
			case .stalled: return false
			case .waiting:
				try? await Task.sleep(for: sampleInterval)
				continue
			case .fresh(let continuous):
				if !continuous { matchingHold.reset() }
			}

			guard !camera.faceMissing, let sample = camera.sample, FrameQuality.isUsable(sample) else {
				matchingHold.reset()
				try? await Task.sleep(for: sampleInterval)
				continue
			}

			// Inference runs on the evaluator actor, off the main thread; the
			// continuation hops back here only to update the hold. Any
			// evaluation failure is fail-closed: it resets the hold like a miss.
			let evaluation = await evaluator.evaluate(sample)
			guard evaluation.failure == nil, evaluation.matched, let face = evaluation.face else {
				// A frame that is not you resets the hold. Anything else would let a
				// stranger's face inherit the seconds yours had already banked.
				matchingHold.reset()
				try? await Task.sleep(for: sampleInterval)
				continue
			}

			if matchingHold.consume(faceID: face.id, now: now, required: hold) {
				logger.notice("Face check passed.")
				return true
			}
			try? await Task.sleep(for: sampleInterval)
		}

		logger.notice("Face check timed out.")
		return false
	}
}
