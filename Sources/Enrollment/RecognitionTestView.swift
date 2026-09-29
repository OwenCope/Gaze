import AVFoundation
import AppKit
import CoreVideo
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

	// Same face selection as the lock screen, so the test reflects what unlocking will do.
	@State private var camera = CameraController(allowsBystanders: true)
	@State private var score: Float = 0
	@State private var matched = false
	@State private var peak: Float = 0
	@State private var floor: Float = 1
	@State private var samples = 0
	@State private var lastProblem: String?
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

	/// Smoothed pupil offsets for the eyes readout: pixel-based, then Vision's
	/// landmark value for comparison. Nil until the first measurable frame.
	@State private var pupilPixel: Double?
	@State private var pupilVision: Double?
	@State private var eyeReadInFlight = false
	/// The spoken eye check: which step it is on, and the raw readings per step.
	@State private var eyeCheckStep: EyeCheckStep?
	@State private var eyeCheckReadings: [EyeCheckStep: [(pixel: Double?, vision: Double?)]] = [:]
	@State private var eyeCheckResult: String?
	@State private var speech = AVSpeechSynthesizer()

	/// One label per face in view, so the test can be run with a friend beside the owner.
	@State private var faceLabels: [FaceLabel] = []
	@State private var frameSize: CGSize = .zero
	@State private var lockVerdict = "Not recognised"
	@State private var lockWillUnlock = false
	@State private var worker: RecognitionTestWorker?

	private struct FaceLabel: Equatable {
		var box: CGRect
		var text: String
		var matched: Bool
	}

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
		var lastProblem: String?
		var lockVerdict = "Not recognised"
		var lockWillUnlock = false
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
			IrisLocator.warmUp()
			// No enrollment means no capture: opening this test must not prompt for
			// camera access. The setup button owns the path forward instead.
			guard store.isEnrolled else { return }
			guard !ForegroundCameraClaim.shared.appLockIsScanning else { return }
			await camera.start(pinnedDeviceID: store.pinnedCameraID)
			await runRecognition()
		}
		.onDisappear {
			camera.stop()
			AppActivation.returnToBackgroundIfIdle()
		}
		.onChange(of: camera.frameID) { _, _ in updateMeasurements() }
		.onChange(of: ForegroundCameraClaim.shared.appLockIsScanning) { _, scanning in
			if scanning {
				camera.stop()
			} else {
				Task {
					guard store.isEnrolled else { return }
					await camera.start(pinnedDeviceID: store.pinnedCameraID)
					await runRecognition()
				}
			}
		}
		.onChange(of: camera.state) { _, state in
			guard state != .running else { return }
			matched = false
			score = 0
			pending.matched = false
			pending.score = 0
			spoofConf = nil
			faceLabels = []
			lockVerdict = "Not recognised"
			lockWillUnlock = false
			pending.lockVerdict = "Not recognised"
			pending.lockWillUnlock = false
			challenge.reset()
		}
		.onChange(of: store.faces.map(\.id)) { _, _ in
			if let worker { Task { await worker.reset() } }
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
		case .lookLeft, .lookRight: return .resting
		}
	}

	private var readout: RecognitionTestReadout {
		var rows: [(String, String)] = [
			("At the lock screen", lockVerdict),
			("Analyzed / expired frames", "\(camera.analyzedFrames) / \(camera.expiredFrames)"),
			("Requested movement", challenge.guidancePrompt),
			("Match score", String(format: "%.3f", score)),
			("Match threshold", String(format: "%.2f", store.embedder.matchThreshold)),
			("Lowest / highest", String(format: "%.3f / %.3f", floor == 1 ? 0 : floor, peak)),
			("Samples", "\(samples)"),
			("Last problem", lastProblem ?? "None"),
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
		} else if ForegroundCameraClaim.shared.appLockIsScanning {
			ZStack {
				Theme.surface
				Text("Paused while App Lock checks your face")
					.multilineTextAlignment(.center)
			}.font(.callout).foregroundStyle(Theme.secondaryLabel).padding(24)
		} else if camera.state == .running {
			CameraPreview(controller: camera)
				.overlay { faceBoxOverlay }
				// A tuning tool, not part of the test: it crowded the status pill and cost a
				// model run per frame. `defaults write com.gazeunlock.Gaze showEyeReadout -bool YES`.
				.overlay(alignment: .bottomTrailing) { if Self.showsEyeReadout { eyesRow.padding(14) } }
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
		pending.lastProblem = nil
		pending.lockVerdict = "Not recognised"
		pending.lockWillUnlock = false
		blinked = false
		eyesShut = false
		challenge.next()
		if let worker { Task { await worker.reset() } }
		publish()
	}

	/// What the lock screen would do with the chosen face's result. Matches
	/// `UnlockFrameEvaluator.Result.permitsMatchHold(requiresAntiSpoof: true)`.
	private static func lockScreenVerdict(matched: Bool, decision: AntiSpoofGate.Decision?) -> (String, Bool) {
		guard matched else { return ("Not recognised", false) }
		switch decision {
		case .live:
			return ("Would unlock", true)
		case .spoof(let reason, _):
			let text = reason.lowercased()
			if text.contains("device-bezel") { return ("Blocked: a rectangle around your face", false) }
			if text.contains("glare") { return ("Blocked: glare on your face", false) }
			return ("Blocked: looks like a photo or screen", false)
		case .unavailable, nil:
			return ("Blocked: photo check unavailable", false)
		}
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
		if camera.lastFrameCapturedAt == nil { return "Getting ready…" }
		if !store.isEnrolled { return "Not enrolled" }
		// The reason, not just the fact. This window exists to explain why recognition is or
		// is not happening, and "No face" over a picture of your own face — which is what a
		// second face in the background produced — is the least useful thing it could say.
		if camera.faceMissing { return camera.absence?.summary ?? "No face" }
		if canChallenge && !challenge.isBaselineReady { return "Scanning. Hold still." }
		// One pill says it all: recognised and would unlock, or the reason the lock
		// screen would still refuse. A second pill beside it collided on narrow windows
		// and repeated "Not recognised" while the first was still starting up.
		guard matched else { return "Not recognised" }
		return lockWillUnlock ? "Recognised" : lockVerdict
	}

	private func updateMeasurements() {
		guard store.isEnrolled, !camera.faceMissing, let sample = camera.sample,
			FrameQuality.isUsable(sample) else {
			clearMatch()
			pupilPixel = nil
			pupilVision = nil
			challenge.reset()
			return
		}
		pose = sample.pose
		updateBlink(sample)
		challenge.consume(sample)
		guard Self.showsEyeReadout else { return }
		// The eye readout runs the iris model off the main thread, one frame at a time;
		// frames that arrive while it is busy are skipped rather than queued.
		guard !eyeReadInFlight else { return }
		eyeReadInFlight = true
		let rawVision = LivenessChallenge.gazeOffset(sample.landmarks)
		Task.detached(priority: .utility) {
			let rawPixel = PupilLocator.horizontalOffset(sample)
			await MainActor.run {
				eyeReadInFlight = false
				pupilPixel = Self.smooth(pupilPixel, rawPixel)
				pupilVision = Self.smooth(pupilVision, rawVision)
				if let step = eyeCheckStep { eyeCheckReadings[step, default: []].append((rawPixel, rawVision)) }
			}
		}
	}

	/// Exponential moving average that holds its value through unmeasurable frames.
	private static func smooth(_ old: Double?, _ fresh: Double?) -> Double? {
		guard let fresh, fresh.isFinite else { return old }
		guard let old else { return fresh }
		return 0.35 * fresh + 0.65 * old
	}

	/// Live pupil readout on the preview: bright dot is the pixel locator, faint
	/// dot is Vision's landmark value. Mirrored like the preview itself (the
	/// preview layer flips horizontally, so image +x shows on screen left).
	private static var showsEyeReadout: Bool { UserDefaults.standard.bool(forKey: "showEyeReadout") }

	@ViewBuilder private var eyesRow: some View {
		if canChallenge {
			HStack(spacing: 8) {
				Text("Eyes").font(.caption).foregroundStyle(.white.opacity(0.7))
				ZStack {
					Capsule().fill(.white.opacity(0.2)).frame(width: 120, height: 4)
					if let vision = pupilVision {
						Circle().fill(.white.opacity(0.45)).frame(width: 7, height: 7)
							.offset(x: Self.dotX(vision))
					}
					if let pixel = pupilPixel {
						Circle().fill(.white).frame(width: 7, height: 7)
							.offset(x: Self.dotX(pixel))
					}
				}.frame(width: 120)
				Text(pupilPixel.map { String(format: "%+.2f", $0) } ?? "—")
					.font(.caption).monospacedDigit().foregroundStyle(.white)
				Button(eyeCheckStep != nil ? "Checking…" : (eyeCheckResult ?? "Check eyes")) { runEyeCheck() }
					.buttonStyle(.plain)
					.font(.caption.weight(.semibold)).monospacedDigit()
					.foregroundStyle(.white)
					.disabled(eyeCheckStep != nil)
			}
			.padding(.horizontal, 12).padding(.vertical, 7)
			.background(.black.opacity(0.55), in: Capsule())
			.background(.ultraThinMaterial, in: Capsule())
			.accessibilityElement(children: .combine)
			.accessibilityLabel("Pupil offset")
			.accessibilityValue(pupilPixel.map { String(format: "%+.2f", $0) } ?? "No reading")
		}
	}

	enum EyeCheckStep: String, CaseIterable { case middle, left, right }

	/// Talks the person through looking at the middle, left edge and right edge,
	/// since they cannot watch the readout while looking away, then shows the
	/// averages and writes the raw readings to /tmp/gaze-eyes.csv.
	private func runEyeCheck() {
		guard eyeCheckStep == nil else { return }
		eyeCheckReadings = [:]
		eyeCheckResult = nil
		Task { @MainActor in
			let prompts: [(EyeCheckStep, String)] = [
				(.middle, "Keep your head still and look at the middle of the screen."),
				(.left, "Now look at the left edge of the screen."),
				(.right, "Now look at the right edge of the screen."),
			]
			for (step, line) in prompts {
				speech.speak(AVSpeechUtterance(string: line))
				try? await Task.sleep(for: .seconds(1.8))
				eyeCheckStep = step
				try? await Task.sleep(for: .seconds(2.5))
				eyeCheckStep = nil
			}
			speech.speak(AVSpeechUtterance(string: "Done. You can look back."))
			func mean(_ step: EyeCheckStep, _ pick: ((pixel: Double?, vision: Double?)) -> Double?) -> Double? {
				let values = (eyeCheckReadings[step] ?? []).compactMap(pick)
				return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
			}
			func show(_ v: Double?) -> String { v.map { String(format: "%+.2f", $0) } ?? "—" }
			eyeCheckResult = EyeCheckStep.allCases.map { step in
				"\(step.rawValue.prefix(1).uppercased()) \(show(mean(step, \.pixel)))"
			}.joined(separator: "  ")
			var csv = "step,pixel,vision\n"
			for step in EyeCheckStep.allCases {
				for r in eyeCheckReadings[step] ?? [] {
					csv += "\(step.rawValue),\(r.pixel.map { String($0) } ?? ""),\(r.vision.map { String($0) } ?? "")\n"
				}
			}
			try? csv.write(toFile: "/tmp/gaze-eyes.csv", atomically: true, encoding: .utf8)
		}
	}

	private static func dotX(_ value: Double) -> CGFloat {
		-min(max(value / 0.25, -1), 1) * 56
	}

	/// One inference at a time, at most 10Hz. The actor keeps both neural passes off
	/// the UI thread, and the loop reads the latest frame instead of queueing old ones.
	private func runRecognition() async {
		let enrolledIDs = store.faces.map(\.id)
		// Faces switched off in Settings are left out, as on the lock screen.
		let testWorker = RecognitionTestWorker(embedder: store.embedder, faces: store.faces.filter(\.isEnabled), spoof: spoof)
		worker = testWorker
		var frames = RecognitionFrameGate()
		while !Task.isCancelled, camera.state == .running, store.faces.map(\.id) == enrolledIDs {
			let start = ContinuousClock.now
			let observation = frames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: start)
			if observation == .stalled { clearMatch(); return }
			if case .fresh = observation, !camera.faceMissing, let sample = camera.sample,
				let capturedAt = camera.lastFrameCapturedAt, FrameQuality.isUsable(sample) {
				let continuity = camera.evidenceContinuity.revision
				let revision = testRevision
				// Same rule as the lock screen: with several faces in view, the one that matches.
				let faces = [sample] + sample.bystanders.filter(FrameQuality.isUsable)
				let (results, chosen, confidence) = await testWorker.evaluate(faces)
				let result = results[chosen]
				guard !Task.isCancelled, camera.state == .running else { clearMatch(); return }
				if revision == testRevision, store.faces.map(\.id) == enrolledIDs,
					capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge,
					camera.evidenceContinuity.permits(continuity, at: .now), result.failure == nil {
					pending.peak = max(pending.peak, result.score)
					pending.floor = min(pending.floor, result.score)
					pending.samples += 1
					pending.matched = result.matched
					pending.score = result.score
					(pending.lockVerdict, pending.lockWillUnlock) = Self.lockScreenVerdict(matched: result.matched, decision: result.spoofDecision)
					spoofConf = confidence
					faceLabels = zip(faces, results).map { face, verdict in
						FaceLabel(box: face.boundingBox,
							text: Self.labelText(score: verdict.score, matched: verdict.matched),
							matched: verdict.matched)
					}
					frameSize = CGSize(width: CVPixelBufferGetWidth(sample.pixelBuffer),
						height: CVPixelBufferGetHeight(sample.pixelBuffer))
					publish()
				} else {
					// Shown in the details: a frame that fails before comparison used to
					// leave only "Samples 0", with nothing saying why.
					if let failure = result.failure {
						pending.lastProblem = Self.problemText(failure)
						lastProblem = pending.lastProblem
					}
					clearMatch()
				}
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
		faceLabels = []
		lockVerdict = "Not recognised"
		lockWillUnlock = false
		pending.lockVerdict = "Not recognised"
		pending.lockWillUnlock = false
	}

	private static func labelText(score: Float, matched: Bool) -> String {
		matched ? "\(Int((score * 100).rounded()))%" : "Not you"
	}

	@ViewBuilder private var faceBoxOverlay: some View {
		GeometryReader { geometry in
			ZStack {
				ForEach(faceLabels.indices, id: \.self) { index in
					let label = faceLabels[index]
					let rect = Self.mappedBox(label.box, frame: frameSize, in: geometry.size)
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.strokeBorder(label.matched ? Theme.faceID : Color.white.opacity(0.7), lineWidth: 2)
						.frame(width: rect.width, height: rect.height)
						.position(x: rect.midX, y: rect.midY)
					Text(label.text)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 8).padding(.vertical, 4)
						.background(.black.opacity(0.55), in: Capsule())
						.position(x: min(max(rect.minX + 30, 34), geometry.size.width - 34),
							y: max(rect.minY - 14, 14))
				}
			}
		}
		.accessibilityHidden(true)
	}

	/// Vision's normalized box (origin lower-left) into view points for the mirrored
	/// aspect-fill preview.
	private static func mappedBox(_ box: CGRect, frame: CGSize, in size: CGSize) -> CGRect {
		guard frame.width > 0, frame.height > 0, size.width > 0, size.height > 0 else { return .zero }
		let scale = max(size.width / frame.width, size.height / frame.height)
		let drawn = CGSize(width: frame.width * scale, height: frame.height * scale)
		let offset = CGSize(width: (size.width - drawn.width) / 2, height: (size.height - drawn.height) / 2)
		let left = box.minX * frame.width * scale
		let width = box.width * frame.width * scale
		let bottom = box.minY * frame.height * scale
		let height = box.height * frame.height * scale
		return CGRect(x: offset.width + drawn.width - left - width,
			y: offset.height + drawn.height - bottom - height,
			width: width, height: height)
	}

	private static func problemText(_ failure: UnlockFrameEvaluator.Failure) -> String {
		switch failure {
		case .noEnrollment: "No saved face is on"
		case .embeddingUnavailable: "Recognition model unavailable"
		case .invalidSimilarity: "Saved face needs adding again"
		case .unusableFrame: "Face too small or blurry"
		case .invalidConfiguration: "Recognition settings are invalid"
		case .cancelled: "Scan was cancelled"
		}
	}

	private func publish() {
		score = pending.score
		matched = pending.matched
		peak = pending.peak
		floor = pending.floor
		samples = pending.samples
		lastProblem = pending.lastProblem
		lockVerdict = pending.lockVerdict
		lockWillUnlock = pending.lockWillUnlock
	}
}

private actor RecognitionTestWorker {
	private let evaluator: UnlockFrameEvaluator
	private let spoof: SpoofDetector?

	init(embedder: any FaceEmbedder, faces: [FaceEnrollment], spoof: SpoofDetector?) {
		evaluator = UnlockFrameEvaluator(embedder: embedder, faces: faces, antiSpoof: AntiSpoofGate(spoof: spoof))
		self.spoof = spoof
	}

	func reset() async {
		await evaluator.resetSpoofCues()
	}

	/// Scores every face in view and picks the first that matches, else the first. The
	/// verdict is read from the chosen face; the deny cues count every evaluated frame.
	func evaluate(_ samples: [FaceSample]) async -> ([UnlockFrameEvaluator.Result], Int, Float?) {
		var results: [UnlockFrameEvaluator.Result] = []
		for sample in samples { results.append(await evaluator.evaluate(sample)) }
		let chosen = results.firstIndex { $0.matched && $0.failure == nil } ?? 0
		guard !Task.isCancelled, results[chosen].failure == nil else { return (results, chosen, nil) }
		return (results, chosen, spoof?.spoofConfidence(samples[chosen]))
	}
}
