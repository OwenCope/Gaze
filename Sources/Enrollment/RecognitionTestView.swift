import Observation
import SwiftUI

/// Live recognition, with the numbers shown.
///
/// This exists to answer one question before any system authentication is touched: is
/// recognition actually good enough to unlock with? Enrolling a face proves nothing on
/// its own — what matters is the margin between your score and a stranger's, and the only
/// way to see that is to watch it run.
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
		// No trailing `Spacer`. It existed to fill a fixed 620pt frame, and once the frame
		// went content-sized it did nothing but manufacture dead air under the Reset button.
		.frame(width: 420)
		// The same glass as the settings window. This was the one surface still painted
		// opaque, and next to the glazed settings window it read as a prop from a different
		// app. The camera disc and score bar sit on glass just as legibly.
		.background(WindowGlass(keepsTitle: true))
		// Committed to dark, deliberately, rather than following the system.
		//
		// This window is mostly camera. A black surround is what keeps the eye on the preview
		// rather than on the wall behind it — the same reason Photo Booth and QuickTime's
		// recorder stay dark whatever the system is set to. Its readouts are tuned against a
		// dark ground too, so following the appearance leaves them washed out on light.
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

	/// No title.
	///
	/// The window's own title bar already says "Test Recognition" an inch above this, and it
	/// said it in a different size and weight — two headings for one window, disagreeing
	/// about how to draw the same six words. What is left is the line that says something
	/// the title bar cannot.
	private var header: some View {
		Text(store.isEnrolled
			? "Nothing is unlocked here. Look at the camera and watch the score."
			: "No face is enrolled yet.")
			.font(Typography.detail)
			.foregroundStyle(Theme.secondaryLabel)
			.multilineTextAlignment(.center)
			.fixedSize(horizontal: false, vertical: true)
	}

	/// The verdict, as a pill rather than bare text.
	private var verdict: some View {
		HStack(spacing: 7) {
			Image(systemName: matched ? "checkmark.circle.fill" : verdictSymbol)
				.font(.system(.body, weight: .semibold))
			Text(statusText)
				.font(.system(.body, weight: .medium))
		}
		.foregroundStyle(matched ? Theme.faceID : Theme.secondaryLabel)
		.padding(.horizontal, 14)
		.padding(.vertical, 7)
		.background(
			Capsule().fill((matched ? Theme.faceID : Color.white).opacity(matched ? 0.14 : 0.06)))
		.animation(.easeOut(duration: 0.2), value: matched)
	}

	private var verdictSymbol: String {
		if camera.state == .denied { return "video.slash.fill" }
		if !store.isEnrolled { return "person.crop.circle.badge.questionmark" }
		if camera.faceMissing { return "viewfinder" }
		return "xmark.circle.fill"
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
						Capsule().fill(.white.opacity(0.07))

						Capsule()
							.fill(
								LinearGradient(
									colors: matched
										? [Theme.faceID.opacity(0.7), Theme.faceID]
										: [Theme.warning.opacity(0.6), Theme.warning],
									startPoint: .leading, endPoint: .trailing)
							)
							.frame(width: geometry.size.width * CGFloat(max(0, min(1, score))))

						// Where the match threshold sits.
						Rectangle()
							.fill(Theme.label.opacity(0.65))
							.frame(width: 2)
							.offset(x: geometry.size.width * CGFloat(store.embedder.matchThreshold))
					}
				}
				.frame(height: 8)
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

			// The two numbers that actually decide whether a threshold is usable: how low
			// the enrolled face drops, and how high anyone else reaches.
			//
			// The sample count belongs to the run, not to either figure. Printing it under
			// both tiles put the same number on screen twice, side by side, reading as two
			// measurements that happened to agree.
			VStack(spacing: 8) {
				HStack(spacing: 10) {
					statTile(
						label: "Lowest", value: floor == 1 ? 0 : floor,
						tint: Theme.warning, symbol: "arrow.down")
					statTile(
						label: "Highest", value: peak,
						tint: Theme.faceID, symbol: "arrow.up")
				}

				Text("\(samples) \(samples == 1 ? "sample" : "samples")")
					.font(Typography.caption)
					.foregroundStyle(Theme.tertiaryLabel)
					.contentTransition(.numericText())
			}

			VStack(spacing: 10) {
				Text("If this is you, watch the lowest. If it isn't, watch the highest.")
					.font(Typography.detail)
					.foregroundStyle(Theme.tertiaryLabel)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)

				Button("Reset") {
					pending.peak = 0
					pending.floor = 1
					pending.samples = 0
					publish()
				}
				.buttonStyle(.accent)
			}
		}
	}

	private func statTile(label: String, value: Float, tint: Color, symbol: String) -> some View {
		VStack(spacing: 4) {
			HStack(spacing: 4) {
				Image(systemName: symbol)
					.font(.system(.caption2, weight: .bold))
				Text(label)
					.font(Typography.metricLabel)
			}
			// Sentence case. `LOWEST` letterspaced is an iOS group header, and this is a
			// caption on a figure, not a header at all.
			.foregroundStyle(tint)

			Text(String(format: "%.3f", value))
				.font(Typography.metric)
				.foregroundStyle(Theme.label)
				.monospacedDigit()
				.contentTransition(.numericText())
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 12)
		.glassSurface()
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(label) score")
		.accessibilityValue(String(format: "%.3f", value))
	}

	private var statusText: String {
		if case .failed(let reason) = camera.state { return reason }
		if camera.state == .denied { return "Camera access is off" }
		if !store.isEnrolled { return "Not enrolled" }
		if camera.faceMissing { return "No face" }
		return matched ? "Recognised" : "Not recognised"
	}

	/// Throttles the visible score to ~10Hz.
	///
	/// Embedding still runs on every frame — the peak and floor need every sample to be
	/// meaningful — but publishing `score` to the view on all of them rebuilt this whole
	/// screen 30 times a second. That is exactly the loop that had the app sitting at 79%
	/// CPU, and here the bar, tiles and gradients make each rebuild more expensive still.
	/// A score that updates ten times a second is indistinguishable to the eye.
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

		// Accumulate outside SwiftUI's observation.
		//
		// `peak`, `floor` and `samples` were @State, so writing them on every frame
		// invalidated the view 30 times a second no matter what the throttle below did —
		// the early return skipped the score but the extremes had already dirtied it.
		// Plain instance storage accumulates silently and is published on the same tick as
		// the score.
		pending.peak = max(pending.peak, result.score)
		pending.floor = min(pending.floor, result.score)
		pending.samples += 1
		pending.matched = result.matched
		pending.score = result.score

		let now = Date()
		guard now.timeIntervalSince(lastDisplayUpdate) >= Self.displayInterval else { return }
		lastDisplayUpdate = now
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
