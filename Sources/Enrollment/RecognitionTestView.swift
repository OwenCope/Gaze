import AppKit
import Observation
import SwiftUI
import Vision

/// Live recognition, with the numbers shown.
///
/// This exists to answer one question before any system authentication is touched: is
/// recognition actually good enough to unlock with? Enrolling a face proves nothing on
/// its own — what matters is the margin between your score and a stranger's, and the only
/// way to see that is to watch it run.
///
/// The anti-spoof read-out mirrors what the lock screen actually checks (`AntiSpoofGate`):
/// the passive texture model and the object detector, the two signals that gate a real
/// unlock. Blink is shown alongside as the plainest demonstration that a photo can't pass.
///
/// Nothing here changes any setting or unlocks anything. It is safe to leave open.
struct RecognitionTestView: View {

	let store: FaceEnrollmentStore

	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) private var dismissWindow

	@State private var camera = CameraController()
	@State private var score: Float = 0
	@State private var matched = false
	@State private var peak: Float = 0
	@State private var floor: Float = 1
	@State private var samples = 0
	@State private var testRevision = UUID()
	@State private var showsDetail = false

	/// Object-detector anti-spoof (`SpoofDetector`): how confidently the Roboflow-trained
	/// detector sees a held phone/screen/photo in the frame. nil when no model is installed.
	/// This is the signal that catches the held-photo attack — it looks for the device, not
	/// the face's texture.
	@State private var spoofConf: Float?
	private let spoof = SpoofDetector.shared

	/// Active challenge–response liveness: a randomly chosen action the user has to perform.
	/// The one anti-spoof signal a webcam can do well — a photo can't turn its head or blink
	/// on demand, and the demand is random.
	@State private var challenge = LivenessChallenge()

	// ── Blink liveness ────────────────────────────────────────────────
	/// Eye openness (height/width of the eye landmarks), ~0.30 open, <0.15 shut. A photo
	/// holds one value forever; a live person's dips when they blink. That dip-then-recover
	/// is the thing a flat image can't fake, in any light.
	@State private var eyeOpen: Float = 0
	@State private var eyesShut = false
	@State private var blinked = false

	@State private var pose: FacePose = .zero

	/// Accumulated between publishes. Deliberately a reference type held in @State so
	/// mutating it does not invalidate the view.
	@State private var pending = PendingStats()

	@Observable
	final class PendingStats {
		var score: Float = 0
		var matched = false
		var peak: Float = 0
		var floor: Float = 1
		var samples = 0
	}

	var body: some View {
		RecognitionTestPanel(readout: readout, showsDetail: $showsDetail, next: { challenge.next() }, reset: reset,
			onSetup: store.isEnrolled ? nil : handleSetup) {
			cameraPreview
		} companion: {
			GazeCompanionView(motion: companionMotion)
		}
		.onChange(of: challenge.isComplete) { _, complete in
			if complete { AccessibilityNotification.Announcement("Movement complete").post() }
		}
		.padding(.top, 18)
		.background(WindowGlass(keepsTitle: true))
		.preferredColorScheme(.dark)
		.task {
			AppActivation.bringToFront()
			// No enrollment means no capture: opening this test must not prompt for
			// camera access. The setup button owns the path forward instead.
			guard store.isEnrolled else { return }
			await camera.start(pinnedDeviceID: store.pinnedCameraID)
			await runRecognition()
		}
		.onDisappear {
			camera.stop()
			AppActivation.returnToBackgroundIfIdle()
		}
		.onChange(of: camera.frameID) { _, _ in updateMeasurements() }
		.onChange(of: camera.state) { _, state in
			guard state != .running else { return }
			matched = false
			score = 0
			pending.matched = false
			pending.score = 0
			spoofConf = nil
			challenge.reset()
		}
	}

	private var canChallenge: Bool { store.isEnrolled && camera.state == .running && !camera.faceMissing }

	private var currentYaw: Double? {
		canChallenge && pose.yaw.isFinite && pose.yawSource != .unavailable ? pose.yaw : nil
	}

	private var currentPitch: Double? {
		canChallenge && pose.pitch.isFinite && pose.pitchSource != .unavailable ? pose.pitch : nil
	}

	private var companionMotion: GazeFaceMotion {
		guard canChallenge else { return .resting }
		guard challenge.isBaselineReady else { return .resting }
		if challenge.isComplete { return .accepted }
		if challenge.isReturningToRest { return .returnToCenter }
		switch challenge.action {
		case .turnLeft: return .turnLeft
		case .turnRight: return .turnRight
		case .nod: return .nod
		case .blink: return .blink
		case .openMouth: return .openMouth
		}
	}

	private var readout: RecognitionTestReadout {
		var rows: [(String, String)] = [
			("Analyzed / expired frames", "\(camera.analyzedFrames) / \(camera.expiredFrames)"),
			("Requested movement", challenge.guidancePrompt),
			("Match score", String(format: "%.3f", score)),
			("Match threshold", String(format: "%.2f", store.embedder.matchThreshold)),
			("Lowest / highest", String(format: "%.3f / %.3f", floor == 1 ? 0 : floor, peak)),
			("Samples", "\(samples)"),
			("Yaw (raw)", currentYaw.map { String(format: "%+.2f rad", $0) } ?? "—"),
			("Pitch (raw)", currentPitch.map { String(format: "%+.2f rad", $0) } ?? "—"),
			("Blink observed", blinked ? "Yes" : "Not yet"),
			("Eye openness", String(format: "%.3f · %@", eyeOpen, eyesShut ? "shut" : "open"))
		]
		if canChallenge, let movement = challenge.poseMeasurement(yaw: pose.yaw, pitch: pose.pitch,
			yawSource: pose.yawSource, pitchSource: pose.pitchSource) {
			rows.append(("Movement from start", String(format: "%+.2f rad", movement.offset)))
			rows.append(("Requested excursion", String(format: "%+.2f rad", movement.target)))
			rows.append(("Return to start", String(format: "within ±%.2f rad", movement.returnTolerance)))
		}
		if spoof != nil {
			// Mirrors AntiSpoofGate's gate decision (spoofRejectThreshold 0.65).
			rows.append(("Photo / screen detector", spoofConf.map { $0 < 0.65 ? "Clear" : "Device seen" } ?? "Not evaluated"))
			rows.append(("Detector score / threshold", spoofConf.map { String(format: "%.3f / %.2f", $0, 0.65) } ?? "—"))
		} else {
			rows.append(("Photo / screen detector", "Model unavailable"))
		}
		let instruction: String
		if !store.isEnrolled {
			instruction = "Enroll your face to try this."
		} else if !canChallenge {
			instruction = "Look at the camera when you're ready."
		} else if !challenge.isBaselineReady {
			instruction = "Face the camera and hold still."
		} else {
			instruction = challenge.isComplete ? "Nicely done." : challenge.guidancePrompt
		}
		return RecognitionTestReadout(status: statusText, matched: matched, score: score,
			threshold: store.embedder.matchThreshold, instruction: instruction,
			complete: canChallenge && challenge.isComplete, canChallenge: canChallenge, diagnosticRows: rows,
			yaw: currentYaw, pitch: currentPitch,
			isCollectingBaseline: canChallenge && !challenge.isBaselineReady)
	}

	@ViewBuilder private var cameraPreview: some View {
		if !store.isEnrolled {
			ZStack {
				Theme.surface
				VStack(spacing: 12) {
					Image(systemName: "person.crop.rectangle").font(.title2)
					Text("Enroll your face before testing recognition.")
						.multilineTextAlignment(.center)
				}.font(.callout).foregroundStyle(Theme.secondaryLabel).padding(24)
			}
		} else if camera.state == .running {
			CameraPreview(controller: camera)
		} else {
			ZStack {
				Theme.surface
				VStack(spacing: 12) {
					if camera.state == .idle {
						ProgressView().controlSize(.small)
						Text("Starting camera…")
					} else {
						Image(systemName: "video.slash").font(.title2)
						Text(statusText).multilineTextAlignment(.center)
						if camera.state == .denied {
							Text("Allow camera access in System Settings → Privacy & Security → Camera, then reopen this test.")
								.font(.caption).multilineTextAlignment(.center)
						}
					}
				}.font(.callout).foregroundStyle(Theme.secondaryLabel).padding(24)
			}
		}
	}

	private func handleSetup() {
		camera.stop()
		SetupRequest.beginOnboarding()
		AppActivation.bringToFront(userInitiated: true)
		openWindow(id: "enrollment")
		dismissWindow(id: "test")
	}

	private func reset() {
		testRevision = UUID()
		pending.peak = 0
		pending.floor = 1
		pending.samples = 0
		blinked = false
		eyesShut = false
		challenge.next()
		publish()
	}

	private func eyeOpenness(_ lm: VNFaceLandmarks2D) -> Float? {
		func openness(_ region: VNFaceLandmarkRegion2D?) -> Float? {
			guard let p = region?.normalizedPoints, p.count >= 4 else { return nil }
			let xs = p.map { $0.x }, ys = p.map { $0.y }
			guard let minX = xs.min(), let maxX = xs.max(),
				let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0.0001
			else { return nil }
			return Float((maxY - minY) / (maxX - minX))
		}
		let vals = [openness(lm.leftEye), openness(lm.rightEye)].compactMap { $0 }
		guard !vals.isEmpty else { return nil }
		return vals.reduce(0, +) / Float(vals.count)
	}

	private func updateBlink(_ sample: FaceSample) {
		guard let o = eyeOpenness(sample.landmarks) else { return }
		eyeOpen = o
		if o < 0.15 {
			eyesShut = true
		} else if eyesShut && o > 0.22 {
			blinked = true
			eyesShut = false
		}
	}

	private var statusText: String {
		if case .failed(let reason) = camera.state { return reason }
		if camera.state == .denied { return "Camera access is off" }
		if camera.state == .idle { return store.isEnrolled ? "Starting camera…" : "Not enrolled" }
		if camera.lastFrameCapturedAt == nil { return "Waiting for camera frames…" }
		if !store.isEnrolled { return "Not enrolled" }
		// The reason, not just the fact. This window exists to explain why recognition is or
		// is not happening, and "No face" over a picture of your own face — which is what a
		// second face in the background produced — is the least useful thing it could say.
		if camera.faceMissing { return camera.absence?.summary ?? "No face" }
		if canChallenge && !challenge.isBaselineReady { return "Scanning. Hold still." }
		return matched ? "Recognised" : "Not recognised"
	}

	private func updateMeasurements() {
		guard store.isEnrolled, !camera.faceMissing, let sample = camera.sample,
			FrameQuality.isUsable(sample) else {
			clearMatch()
			challenge.reset()
			return
		}
		pose = sample.pose
		updateBlink(sample)
		challenge.consume(sample)
	}

	/// One inference at a time, at most 10Hz. The actor keeps both neural passes off
	/// the UI thread, and the loop reads the latest frame instead of queueing old ones.
	private func runRecognition() async {
		let enrolledIDs = store.faces.map(\.id)
		let worker = RecognitionTestWorker(embedder: store.embedder, faces: store.faces, spoof: spoof)
		var frames = RecognitionFrameGate()
		while !Task.isCancelled, camera.state == .running, store.faces.map(\.id) == enrolledIDs {
			let start = ContinuousClock.now
			let observation = frames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: start)
			if observation == .stalled { clearMatch(); return }
			if case .fresh = observation, !camera.faceMissing, let sample = camera.sample,
				let capturedAt = camera.lastFrameCapturedAt, FrameQuality.isUsable(sample) {
				let continuity = camera.evidenceContinuity.revision
				let revision = testRevision
				let (result, confidence) = await worker.evaluate(sample)
				guard !Task.isCancelled, camera.state == .running else { clearMatch(); return }
				if revision == testRevision, store.faces.map(\.id) == enrolledIDs,
					capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge,
					camera.evidenceContinuity.permits(continuity, at: .now), result.failure == nil {
					pending.peak = max(pending.peak, result.score)
					pending.floor = min(pending.floor, result.score)
					pending.samples += 1
					pending.matched = result.matched
					pending.score = result.score
					spoofConf = confidence
					publish()
				} else { clearMatch() }
			}
			let delay = max(.zero, Duration.milliseconds(100) - start.duration(to: .now))
			do { try await Task.sleep(for: delay) } catch { break }
		}
		clearMatch()
	}

	private func clearMatch() {
		matched = false
		score = 0
		pending.matched = false
		pending.score = 0
		spoofConf = nil
	}

	private func publish() {
		score = pending.score
		matched = pending.matched
		peak = pending.peak
		floor = pending.floor
		samples = pending.samples
	}
}

private actor RecognitionTestWorker {
	private let evaluator: UnlockFrameEvaluator
	private let spoof: SpoofDetector?

	init(embedder: any FaceEmbedder, faces: [FaceEnrollment], spoof: SpoofDetector?) {
		evaluator = UnlockFrameEvaluator(embedder: embedder, faces: faces, antiSpoof: nil)
		self.spoof = spoof
	}

	func evaluate(_ sample: FaceSample) async -> (UnlockFrameEvaluator.Result, Float?) {
		let result = await evaluator.evaluate(sample)
		guard !Task.isCancelled, result.failure == nil else { return (result, nil) }
		return (result, spoof?.spoofConfidence(sample))
	}
}
