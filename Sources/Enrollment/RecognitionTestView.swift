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

	@State private var camera = CameraController()
	@State private var score: Float = 0
	@State private var matched = false
	@State private var peak: Float = 0
	@State private var floor: Float = 1
	@State private var samples = 0
	@State private var lastDisplayUpdate = Date.distantPast
	/// Shut by default — see the note on the disclosure in `readout`.
	@State private var showsDetail = false

	/// Object-detector anti-spoof (`SpoofDetector`): how confidently the Roboflow-trained
	/// detector sees a held phone/screen/photo in the frame. nil when no model is installed.
	/// This is the signal that catches the held-photo attack — it looks for the device, not
	/// the face's texture.
	@State private var spoofConf: Float?
	private let spoof = SpoofDetector()

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

	/// The head's measured orientation, shown under Details.
	///
	/// Which way Vision's yaw runs has been got wrong three times in this app — the turn
	/// challenge asked for the opposite of what it said, the enrolment ring lit the tick
	/// across from the one being looked at, and the nod completed on a raised chin. Each
	/// time it was settled by argument about which way a camera faces, and each time the
	/// argument lost to the camera.
	///
	/// So the figure is on screen, with the word the code derives from it beside it. If the
	/// word says "left" while the head is turning right, the convention is wrong and it takes
	/// two seconds rather than a rebuild to find out. It sits under the Details disclosure
	/// with the other raw numbers, shut by default.
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

	private let circleSize: CGFloat = 210

	var body: some View {
		VStack(spacing: 20) {
			header
			preview
			readout
		}
		.padding(26)
		// Room for the traffic lights: the title bar is transparent and content runs under
		// it, so the top inset is the window's own chrome now.
		.padding(.top, 18)
		.frame(width: 420)
		// The same glass as the settings window.
		.background(WindowGlass(keepsTitle: true))
		// Committed to dark, deliberately, rather than following the system. This window is
		// mostly camera, and a dark surround keeps the eye on the preview.
		.preferredColorScheme(.dark)
		.task {
			AppActivation.bringToFront()
			await camera.start(pinnedDeviceID: store.pinnedCameraID)
		}
		.onDisappear {
			camera.stop()
			AppActivation.returnToBackgroundIfIdle()
		}
		.onChange(of: camera.frameID) { _, _ in evaluate() }
	}

	// MARK: - Sections

	private var header: some View {
		Text(store.isEnrolled
			? "Nothing is unlocked here. Look at the camera and watch the score."
			: "No face is enrolled yet.")
			.font(Typography.detail)
			.foregroundStyle(Theme.secondaryLabel)
			.multilineTextAlignment(.center)
			.fixedSize(horizontal: false, vertical: true)
	}

	/// The verdict: a status dot and a word. No pill, no glow — colour only when it means
	/// something (green = recognised), grey otherwise.
	private var verdict: some View {
		HStack(spacing: 8) {
			Circle()
				.fill(matched ? Theme.faceID : Theme.tertiaryLabel)
				.frame(width: 7, height: 7)
			Text(statusText)
				.font(.system(.callout, weight: .medium))
				.foregroundStyle(matched ? Theme.label : Theme.secondaryLabel)
		}
		.animation(.easeOut(duration: 0.2), value: matched)
	}

	@ViewBuilder
	private var preview: some View {
		ZStack {
			if camera.state == .running {
				CameraPreview(controller: camera)
					.frame(width: circleSize, height: circleSize)
					.clipShape(.circle)
			} else {
				Circle()
					.fill(Theme.surface)
					.frame(width: circleSize, height: circleSize)
					.overlay { ProgressView() }
			}

			Circle()
				.strokeBorder(
					matched ? Theme.faceID : Theme.separator,
					lineWidth: matched ? 3 : 1)
				.frame(width: circleSize + 10, height: circleSize + 10)
				.animation(.easeOut(duration: 0.18), value: matched)
		}
	}

	private var readout: some View {
		VStack(spacing: 16) {
			verdict

			// Scores are only meaningful against the threshold, so the marker is drawn on
			// the bar rather than quoted as a number beside it.
			VStack(spacing: 7) {
				GeometryReader { geometry in
					ZStack(alignment: .leading) {
						Capsule().fill(Theme.label.opacity(0.08))

						Capsule()
							.fill(matched ? Theme.faceID : Theme.secondaryLabel)
							.frame(width: geometry.size.width * CGFloat(max(0, min(1, score))))

						// Where the match threshold sits.
						Rectangle()
							.fill(Theme.label.opacity(0.55))
							.frame(width: 1.5)
							.offset(x: geometry.size.width * CGFloat(store.embedder.matchThreshold))
					}
				}
				.frame(height: 6)
				.animation(.easeOut(duration: 0.12), value: score)

				HStack {
					Text(String(format: "%.3f", score))
						.foregroundStyle(matched ? Theme.faceID : Theme.secondaryLabel)
					Spacer()
					Text("threshold \(String(format: "%.2f", store.embedder.matchThreshold))")
						.foregroundStyle(Theme.tertiaryLabel)
				}
				.font(Typography.mono)
			}

			// The liveness checks stay in the open: they are the part of this window someone
			// is asked to *do* something about.
			antiSpoofSection

			// Everything numeric goes behind a disclosure, shut by default.
			//
			// This window is reachable from Settings by anyone, and it opened on `spoof
			// 0.000`, `threshold 0.50`, `eye openness 0.290` and a run of three-decimal
			// figures — a panel that answers "is this working" in a language only the person
			// who wrote it speaks. The question almost everybody has is answered by the word
			// under the camera and the bar under that; the figures matter to the one person
			// tuning a threshold, and they are still one click away for them.
			DisclosureGroup(isExpanded: $showsDetail) {
				VStack(spacing: 0) {
					statRow("Lowest", String(format: "%.3f", floor == 1 ? 0 : floor))
					RowDivider(inset: 0)
					statRow("Highest", String(format: "%.3f", peak))
					RowDivider(inset: 0)
					statRow("Samples", "\(samples)")
					RowDivider(inset: 0)
					statRow("Turn", String(format: "%@  %+.2f", turnWord, pose.yaw))
					RowDivider(inset: 0)
					statRow("Nod", String(format: "%@  %+.2f", nodWord, pose.pitch))
				}
				.glassSurface()
				.padding(.top, 8)

				Text("If this is you, watch the lowest. If it isn't, watch the highest.")
					.font(Typography.detail)
					.foregroundStyle(Theme.tertiaryLabel)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.top, 8)
			} label: {
				Text("Details")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
			}
			.animation(Theme.Motion.quick, value: showsDetail)

			VStack(spacing: 10) {

				Button("Reset") {
					pending.peak = 0
					pending.floor = 1
					pending.samples = 0
					blinked = false
					eyesShut = false
					challenge.next()
					publish()
				}
				.gazeButton()
			}
		}
	}

	/// Which way the code currently believes the head is turned. Derived from the one stated
	/// convention on `FacePose.yaw` — negative is the user's own left — so a disagreement
	/// between this word and the head in the preview is a bug in that convention, visible.
	private var turnWord: String {
		if pose.yaw < -0.15 { return "left " }
		if pose.yaw > 0.15 { return "right" }
		return "centre"
	}

	/// Same, for pitch: Vision reports chin-down as positive. The rest value is not
	/// necessarily zero, so read this as a direction of travel rather than an absolute.
	private var nodWord: String {
		if pose.pitch > 0.15 { return "down " }
		if pose.pitch < -0.15 { return "up   " }
		return "level "
	}

	/// A label-left, mono-value-right row. The whole readout is a spec list, not a grid of
	/// tiles — no glass, no arrows, no per-figure colour.
	private func statRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
			Spacer()
			Text(value)
				.font(Typography.mono)
				.foregroundStyle(Theme.label)
				.contentTransition(.numericText())
		}
		.padding(.horizontal, 13)
		.padding(.vertical, 9)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(label)
		.accessibilityValue(value)
	}

	// MARK: - Anti-spoof

	/// Average eye openness (height/width of the eye landmarks). A photo sits at one value;
	/// a blink makes it dip and recover.
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

	/// The three liveness signals, as one group.
	///
	/// These were three blocks separated by a bare `Divider`, floating on the window ground
	/// under three more floating figures — the window read as a printout because nothing on
	/// it was ever bounded. On a surface, with rules between the rows, they read as what they
	/// are: a short list of checks, each with a verdict.
	private var antiSpoofSection: some View {
		VStack(spacing: 0) {
			// Active challenge — a randomly chosen action the user has to perform. This is the
			// real anti-spoof: a photo can't do it, and because the ask is random a recording
			// of one action can't answer a demand for another.
			HStack(spacing: 11) {
				Image(systemName: challenge.isComplete ? "checkmark.circle.fill" : challenge.action.symbol)
					.font(.system(size: 19, weight: .semibold))
					.foregroundStyle(challenge.isComplete ? Theme.faceID : Theme.label)
					.contentTransition(.symbolEffect(.replace))
					.frame(width: 24)
				VStack(alignment: .leading, spacing: 1) {
					Text("Prove you're really here")
						.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
					Text(challenge.isComplete ? "Passed" : challenge.action.prompt)
						.font(.system(.callout, weight: .semibold))
						.foregroundStyle(challenge.isComplete ? Theme.faceID : Theme.label)
						.contentTransition(.opacity)
				}
				Spacer(minLength: 8)
				Button(challenge.isComplete ? "Again" : "Skip") { challenge.next() }
					.gazeButton(size: .small)
			}
			.padding(.horizontal, 13)
			.padding(.vertical, 10)
			.animation(.easeOut(duration: 0.2), value: challenge.isComplete)

			RowDivider(inset: 0)

			// Object detector — looks for a held phone/screen/photo in the whole frame. The
			// verdict inverts: a high confidence means a device is present, so low is good.
			if spoof != nil {
				let conf = spoofConf ?? 0
				let threshold = spoof?.threshold ?? 0.5
				signalBar(
					title: "Photo or screen held up",
					value: conf,
					threshold: threshold,
					pass: conf < threshold,
					passWord: "Clear", failWord: "Device seen",
					valueLabel: "spoof",
					invert: true)
				RowDivider(inset: 0)
			}

			// Blink — the one thing a photo can't do, in any light. Openness dips on a blink
			// and this latches "Live"; a flat image holds one value and never trips.
			VStack(spacing: 7) {
				HStack {
					Text("Blink")
						.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
					Spacer()
					Text(blinked ? "Live — blinked" : "Blink to prove")
						.font(.system(.caption, weight: .semibold))
						.foregroundStyle(blinked ? Theme.faceID : Theme.tertiaryLabel)
				}
				if showsDetail {
					HStack {
						Text(String(format: "eye openness %.3f", eyeOpen))
							.foregroundStyle(Theme.secondaryLabel)
						Spacer()
						Text(eyesShut ? "shut" : "open")
							.foregroundStyle(Theme.tertiaryLabel)
					}
					.font(Typography.mono)
				}
			}
			.padding(.horizontal, 13)
			.padding(.vertical, 10)
		}
		.glassSurface()
	}

	/// One anti-spoof signal: a label, a pass/fail word, a bar with the threshold marked, and
	/// the raw value. `invert` is for a signal where *high* is bad (the object detector).
	private func signalBar(
		title: String, value: Float, threshold: Float, pass: Bool,
		passWord: String, failWord: String, valueLabel: String, invert: Bool = false
	) -> some View {
		let barColor = pass ? Theme.faceID : Theme.warning
		return VStack(spacing: 7) {
			HStack {
				Text(title)
					.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
				Spacer()
				Text(pass ? passWord : failWord)
					.font(.system(.caption, weight: .semibold))
					.foregroundStyle(pass ? Theme.faceID : Theme.warning)
			}
			GeometryReader { geometry in
				ZStack(alignment: .leading) {
					Capsule().fill(.white.opacity(0.07))
					Capsule()
						.fill(invert ? Theme.secondaryLabel : barColor)
						.frame(width: geometry.size.width * CGFloat(max(0, min(1, value))))
					Rectangle().fill(Theme.label.opacity(0.65)).frame(width: 2)
						.offset(x: geometry.size.width * CGFloat(threshold))
				}
			}
			.frame(height: 8)
			.animation(.easeOut(duration: 0.12), value: value)
			// The figure and its threshold follow the Details disclosure. The bar already
			// says where this signal sits against the line it has to stay under, which is
			// the whole content of the number — printing `spoof 0.000 threshold 0.50` under
			// it as well tells a general reader nothing they can act on.
			if showsDetail {
				HStack {
					Text(String(format: "%@ %.3f", valueLabel, value))
						.foregroundStyle(pass ? Theme.faceID : Theme.secondaryLabel)
					Spacer()
					Text("threshold \(String(format: "%.2f", threshold))")
						.foregroundStyle(Theme.tertiaryLabel)
				}
				.font(Typography.mono)
			}
		}
		.padding(.horizontal, 13)
		.padding(.vertical, 10)
	}

	private var statusText: String {
		if case .failed(let reason) = camera.state { return reason }
		if camera.state == .denied { return "Camera access is off" }
		if !store.isEnrolled { return "Not enrolled" }
		// The reason, not just the fact. This window exists to explain why recognition is or
		// is not happening, and "No face" over a picture of your own face — which is what a
		// second face in the background produced — is the least useful thing it could say.
		if camera.faceMissing { return camera.absence?.summary ?? "No face" }
		return matched ? "Recognised" : "Not recognised"
	}

	/// Throttles the visible score to ~10Hz. Embedding still runs on every frame — the peak
	/// and floor need every sample — but publishing to the view on all of them rebuilt this
	/// whole screen 30 times a second.
	private static let displayInterval: TimeInterval = 0.1

	private func evaluate() {
		guard store.isEnrolled, !camera.faceMissing, let sample = camera.sample else {
			if matched || score != 0 {
				matched = false
				score = 0
			}
			return
		}

		let result = store.matches(sample)

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
		publish()
	}

	private func publish() {
		score = pending.score
		matched = pending.matched
		peak = pending.peak
		floor = pending.floor
		samples = pending.samples
	}
}
