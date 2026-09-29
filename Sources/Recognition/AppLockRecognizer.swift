import AppKit
import Foundation
import os

/// Face recognition for the App Lock shield.
///
/// Reuses the camera and `UnlockFrameEvaluator` with anti-spoof and a 1 s
/// match hold, and no movement challenge, to keep it quick like iOS. A passing
/// face unlocks through the shield's existing `unlockSucceeded()` path.
///
/// After `AppLockStateMachine.maxFaceMisses` misses the face is disabled and
/// only Use Password works, until a successful unlock clears the counter in
/// the state machine. Scans that saw nobody do not count as misses.
@MainActor
final class AppLockRecognizer {

	/// How long a face must match before it unlocks. Shorter than the main
	/// lock screen's hold because there is no movement challenge here.
	static let matchHold: Duration = .seconds(1)
	/// How long a scan runs before giving up. Matches the lock screen's
	/// search window.
	static let searchTimeout: Duration = .seconds(12)

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "AppLockFace")

	/// Reports scan state to the shield for the caption under the face mark.
	var onScanState: ((AppLockScanState) -> Void)?

	private let store: FaceEnrollmentStore
	private let machine: AppLockStateMachine
	private var scanTask: Task<Void, Never>?

	init(store: FaceEnrollmentStore, machine: AppLockStateMachine) {
		self.store = store
		self.machine = machine
	}

	/// Wires shield show to scan start and scan success to the shield's
	/// success path, chaining any previous `faceUnlockAttempt` handler.
	func attach(to shield: AppLockShield) {
		let previous = shield.faceUnlockAttempt
		shield.faceUnlockAttempt = { [weak self] bundleID in
			previous?(bundleID)
			self?.startScan(bundleID: bundleID, shield: shield)
		}
		shield.stopFaceScan = { [weak self] in self?.stop() }
		onScanState = { [weak shield] state in shield?.reportScanState(state) }
	}

	/// Starts a scan for the shown shield. No-op when the face is disabled
	/// for the app after too many misses.
	func startScan(bundleID: String, shield: AppLockShield) {
		stop()
		guard !machine.isFaceDisabled(bundleID) else {
			Self.logger.info("App Lock scan skipped: face disabled for \(bundleID, privacy: .public)")
			onScanState?(.faceDisabled)
			return
		}
		onScanState?(.scanning)
		// Wait for the previous scan's camera to close first. Two sessions at once
		// starved the new one of frames, which read as "camera stalled".
		let previous = finishingTask
		scanTask = Task { [weak self, weak shield] in
			await previous?.value
			guard let self, let shield, !Task.isCancelled else { return }
			await self.runScan(bundleID: bundleID, shield: shield)
		}
		finishingTask = scanTask
	}

	func stop() {
		scanTask?.cancel()
		scanTask = nil
	}

	/// The last scan, kept after `stop()` so the next one can wait for its camera.
	private var finishingTask: Task<Void, Never>?

	/// How long to keep looking while the shield is up before resting the camera.
	/// Clicking the face starts looking again.
	static let lookingLimit: Duration = .seconds(60)
	/// Camera hiccups tolerated in a row before saying the camera is unavailable.
	static let cameraRetries = 3

	private func runScan(bundleID: String, shield: AppLockShield) async {
		guard !store.isCorrupted, store.isEnrolled else {
			Self.logger.error("App Lock scan unavailable: face not enrolled")
			onScanState?(.unavailable(reason: "Face not set up. Use your password."))
			return
		}
		guard let pinnedCamera = store.pinnedCameraID, !pinnedCamera.isEmpty else {
			Self.logger.error("App Lock scan unavailable: no pinned camera")
			onScanState?(.unavailable(reason: "No camera selected. Use your password."))
			return
		}
		// Fail closed like the lock screen: without anti-spoof there is no
		// face unlock, only Use Password.
		let detector = AntiSpoofGate(spoof: SpoofDetector.shared)
		guard detector.isActive else {
			Self.logger.error("App Lock scan unavailable: anti-spoof inactive")
			onScanState?(.unavailable(reason: "Face check unavailable. Use your password."))
			return
		}
		// Load both models while the camera starts, as the lock screen does. Loading
		// them on the first frame stalls the loop for over a second, which the frame
		// gate reads as a dead camera ("Camera stalled").
		let embedder = store.embedder
		let warmUp = Task.detached(priority: .userInitiated) {
			embedder.warmUp()
			SpoofDetector.shared?.warmUp()
		}
		let started = ContinuousClock.now
		var failures = 0
		while !Task.isCancelled, started.duration(to: .now) < Self.lookingLimit {
			switch await scanOnce(bundleID: bundleID, shield: shield, pinnedCamera: pinnedCamera,
				detector: detector, warmUp: warmUp) {
			case .unlocked, .cancelled:
				return
			case .noMatch:
				failures = 0
			case .cameraProblem:
				failures += 1
				if failures >= Self.cameraRetries {
					onScanState?(.unavailable(reason: "Camera unavailable. Use your password."))
					return
				}
				// A camera that hiccups usually comes back after a beat; keep the
				// caption on "Looking for you" rather than flashing an error.
				try? await Task.sleep(for: .milliseconds(400))
			}
			if machine.isFaceDisabled(bundleID) {
				Self.logger.info("App Lock face disabled for \(bundleID, privacy: .public) after too many misses")
				onScanState?(.faceDisabled)
				return
			}
		}
		guard !Task.isCancelled else { return }
		onScanState?(.resting)
	}

	private enum ScanOutcome { case unlocked, cancelled, noMatch, cameraProblem }

	/// One camera session: looks until a match, a camera problem, or the search window.
	private func scanOnce(bundleID: String, shield: AppLockShield, pinnedCamera: String,
		detector: AntiSpoofGate, warmUp: Task<Void, Never>) async -> ScanOutcome {
		SceneBrightness.reset()
		let camera = CameraController(accessScope: .lockScreen, allowsBystanders: false)
		let alreadyHeld = ForegroundCameraClaim.shared.appLockIsScanning
		ForegroundCameraClaim.shared.beginAppLockScan()
		defer {
			ForegroundCameraClaim.shared.endAppLockScan()
			camera.stop()
			LockScreenLight.shared.hide()
		}
		if !alreadyHeld {
			// Let the test window release the camera before starting.
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled else { return .cancelled }
		}
		await camera.start(pinnedDeviceID: pinnedCamera)
		await warmUp.value
		guard !Task.isCancelled else { return .cancelled }
		guard camera.state == .running, camera.boundDeviceID == pinnedCamera else {
			Self.logger.error("App Lock camera failed to start; retrying")
			return .cameraProblem
		}
		onScanState?(.scanning)
		let evaluator = UnlockFrameEvaluator(
			embedder: store.embedder,
			faces: store.faces.filter(\.isEnabled),
			antiSpoof: detector)
		var frames = RecognitionFrameGate()
		var hold = RecognitionMatchHold()
		var lastContinuity: UInt64?
		var sawFace = false
		let deadline = ContinuousClock.now.advanced(by: Self.searchTimeout)
		while ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(40))
			guard !Task.isCancelled else { return .cancelled }
			guard camera.state == .running, camera.boundDeviceID == pinnedCamera else { return .cameraProblem }
			// Same as the lock screen: in a dark room, light the screen edges and turn
			// the brightness up so the camera can see a face.
			if Preferences.shared.screenGlowInDark, !LockScreenLight.shared.isShowing,
				SceneBrightness.isDark() {
				LockScreenLight.shared.show()
			}
			switch frames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: .now) {
			case .stalled:
				Self.logger.error("App Lock frame stream stalled; restarting the camera")
				return .cameraProblem
			case .waiting:
				continue
			case .fresh(let continuous):
				if !continuous { hold.reset() }
			}
			guard let sample = camera.sample, FrameQuality.rejection(sample) == nil,
				let capturedAt = camera.lastFrameCapturedAt else {
				hold.reset()
				continue
			}
			let continuity = camera.evidenceContinuity.revision
			if lastContinuity != continuity { hold.reset() }
			lastContinuity = continuity
			let result = await evaluator.evaluate(sample)
			guard !Task.isCancelled, camera.state == .running,
				camera.boundDeviceID == pinnedCamera,
				camera.evidenceContinuity.permits(continuity, at: .now),
				capturedAt <= .now, capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge else {
				hold.reset()
				continue
			}
			sawFace = true
			guard result.permitsMatchHold(requiresAntiSpoof: true), let face = result.face else {
				hold.reset()
				continue
			}
			guard hold.consume(faceID: face.id, now: capturedAt, required: Self.matchHold) else { continue }
			guard !Task.isCancelled else { return .cancelled }
			shield.unlockSucceeded()
			return .unlocked
		}
		if sawFace { machine.recordFaceMiss(bundleID) }
		return .noMatch
	}
}
