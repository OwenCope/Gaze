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
	@State private var lastDisplayUpdate = Date.distantPast
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

	/// One label per face in view, so the test can be run with a friend beside the owner.
	@State private var faceLabels: [FaceLabel] = []
	@State private var frameSize: CGSize = .zero

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
		}
		.onDisappear {
			camera.stop()
			AppActivation.returnToBackgroundIfIdle()
		}
		.onChange(of: camera.frameID) { _, _ in evaluate() }
		.onChange(of: camera.state) { _, state in
			guard state != .running else { return }
			matched = false
			score = 0
			pending.matched = false
			pending.score = 0
			spoofConf = nil
			faceLabels = []
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
				.overlay { faceBoxOverlay }
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

	/// Throttles the visible score to ~10Hz. Embedding still runs on every frame — the peak
	/// and floor need every sample — but publishing to the view on all of them rebuilt this
	/// whole screen 30 times a second.
	private static let displayInterval: TimeInterval = 0.1

	private func evaluate() {
		guard store.isEnrolled, !camera.faceMissing, var sample = camera.sample else {
			if matched || score != 0 {
				matched = false
				score = 0
			}
			if !faceLabels.isEmpty { faceLabels = [] }
			return
		}

		let primary = sample
		var result = store.matches(sample)
		// Same rule as the lock screen: with several faces in view, the one that matches.
		if !result.matched {
			for other in sample.bystanders where FrameQuality.rejection(other) == nil {
				let candidate = store.matches(other)
				if candidate.matched { result = candidate; sample = other; break }
			}
		}

		pending.peak = max(pending.peak, result.score)
		pending.floor = min(pending.floor, result.score)
		pending.samples += 1
		pending.matched = result.matched
		pending.score = result.score

		let now = Date()
		guard now.timeIntervalSince(lastDisplayUpdate) >= Self.displayInterval else { return }
		lastDisplayUpdate = now
		// Score the anti-spoof signal on the throttled tick only — it's a Core ML pass, too
		// heavy to run on all 30 frames a second.
		spoofConf = spoof?.spoofConfidence(sample)
		pose = sample.pose
		updateBlink(sample)
		challenge.consume(sample)
		// Each face gets its own verdict, scored on the throttled tick for the same reason.
		var labels: [FaceLabel] = []
		for face in [primary] + primary.bystanders where FrameQuality.rejection(face) == nil {
			let verdict = store.matches(face)
			labels.append(FaceLabel(box: face.boundingBox,
				text: Self.labelText(score: verdict.score, matched: verdict.matched),
				matched: verdict.matched))
		}
		faceLabels = labels
		frameSize = CGSize(width: CVPixelBufferGetWidth(primary.pixelBuffer),
			height: CVPixelBufferGetHeight(primary.pixelBuffer))
		publish()
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

	private func publish() {
		score = pending.score
		matched = pending.matched
		peak = pending.peak
		floor = pending.floor
		samples = pending.samples
	}
}
