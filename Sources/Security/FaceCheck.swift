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
/// Deliberately no lockout accounting. Failing to autofill leaves the user exactly where
/// they were — in front of a password field they can type into — so a wrong face here costs
/// nothing and should not spend attempts that protect the Mac itself.
@MainActor
enum FaceCheck {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "FaceCheck")

	/// How long to keep looking before giving up. Short: this runs while the user is
	/// waiting with a text field focused, and a spinner that outlasts typing the password
	/// by hand is worse than not offering the feature.
	private static let timeout: Duration = .seconds(6)
	/// How long the match has to keep being true.
	private static let hold: TimeInterval = 0.35
	private static let sampleInterval: Duration = .milliseconds(80)

	/// Opens the camera, looks for an enrolled face, and closes it again.
	///
	/// - Parameter warm: a camera somebody else already started. Autofill passes one,
	///   because opening an `AVCaptureSession` costs between half a second and a second
	///   and a half — far more than everything else here put together. Starting it in
	///   parallel with looking for the password field, rather than after, is the single
	///   biggest thing that makes this feel instant instead of sluggish. When one is
	///   handed in, closing it stays the caller's job: they own it and may want it again.
	static func authenticate(
		using store: FaceEnrollmentStore, warm: CameraController? = nil
	) async -> Bool {
		guard store.isEnrolled else { return false }

		let camera = warm ?? CameraController()
		if warm == nil {
			await camera.start(
				pinnedDeviceID: Preferences.shared.requireBuiltInCamera ? store.pinnedCameraID : nil)
		}
		defer { if warm == nil { camera.stop() } }

		guard camera.state == .running else {
			logger.error("Face check skipped: camera unavailable.")
			return false
		}

		let deadline = ContinuousClock.now.advanced(by: timeout)
		var matchingSince: Date?

		while ContinuousClock.now < deadline {
			if Task.isCancelled { return false }

			guard let sample = camera.sample, FrameQuality.isUsable(sample) else {
				matchingSince = nil
				try? await Task.sleep(for: sampleInterval)
				continue
			}

			guard store.matches(sample).matched else {
				// A frame that is not you resets the hold. Anything else would let a
				// stranger's face inherit the seconds yours had already banked.
				matchingSince = nil
				try? await Task.sleep(for: sampleInterval)
				continue
			}

			let since = matchingSince ?? Date()
			matchingSince = since
			if Date().timeIntervalSince(since) >= hold {
				logger.notice("Face check passed.")
				return true
			}
			try? await Task.sleep(for: sampleInterval)
		}

		logger.notice("Face check timed out.")
		return false
	}
}
