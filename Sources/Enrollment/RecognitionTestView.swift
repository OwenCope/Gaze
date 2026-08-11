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
			Spacer(minLength: 0)
		}
		.padding(26)
		.frame(width: 420, height: 620)
		.background(Theme.background)
		.preferredColorScheme(.dark)
		.task {
			AppActivation.bringToFront()
			await camera.start(pinnedDeviceID: store.enrollment?.cameraID)
		}
		.onDisappear {
			camera.stop()
			AppActivation.returnToBackgroundIfIdle()
		}
		.onChange(of: camera.frameID) { _, _ in evaluate() }
	}

	// MARK: - Sections

	private var header: some View {
		VStack(spacing: 6) {
			Text("Test Recognition")
				.font(.system(size: 19, weight: .semibold))
				.foregroundStyle(Theme.label)
			Text(store.isEnrolled
				? "Nothing is unlocked here. Look at the camera and watch the score."
				: "No face is enrolled yet.")
				.font(.system(size: 12))
				.foregroundStyle(Theme.secondaryLabel)
				.multilineTextAlignment(.center)
		}
	}

	/// The verdict, as a pill rather than bare text.
	private var verdict: some View {
		HStack(spacing: 7) {
			Image(systemName: matched ? "checkmark.circle.fill" : verdictSymbol)
				.font(.system(size: 13, weight: .semibold))
			Text(statusText)
				.font(.system(size: 14, weight: .medium))
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
				.font(.system(size: 11, weight: .medium, design: .monospaced))
			}

			// The two numbers that actually decide whether a threshold is usable: how low
			// the enrolled face drops, and how high anyone else reaches.
			HStack(spacing: 10) {
				statTile(
					label: "Lowest", value: floor == 1 ? 0 : floor,
					tint: Theme.warning, symbol: "arrow.down")
				statTile(
					label: "Highest", value: peak,
					tint: Theme.faceID, symbol: "arrow.up")
			}

			VStack(spacing: 8) {
				Text("If this is you, watch the lowest. If it isn't, watch the highest.")
					.font(.system(size: 11))
					.foregroundStyle(Theme.tertiaryLabel)
					.multilineTextAlignment(.center)

				Button("Reset") {
					pending.peak = 0
					pending.floor = 1
					pending.samples = 0
					publish()
				}
				.buttonStyle(AccentButtonStyle(role: .cancel))
			}
		}
	}

	private func statTile(label: String, value: Float, tint: Color, symbol: String) -> some View {
		VStack(spacing: 4) {
			HStack(spacing: 4) {
				Image(systemName: symbol)
					.font(.system(size: 9, weight: .bold))
				Text(label.uppercased())
					.font(.system(size: 10, weight: .semibold))
					.tracking(0.5)
			}
			.foregroundStyle(tint.opacity(0.9))

			Text(String(format: "%.3f", value))
				.font(.system(size: 20, weight: .semibold, design: .rounded))
				.foregroundStyle(Theme.label)
				.contentTransition(.numericText())

			Text("\(samples) samples")
				.font(.system(size: 9))
				.foregroundStyle(Theme.tertiaryLabel)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 12)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Theme.surface))
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
