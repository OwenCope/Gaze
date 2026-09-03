import Observation
import SwiftUI

/// Live recognition diagnostics. It shows the camera state and confidence without unlocking
/// anything, so a user can build trust in the match before connecting it to the lock screen.
struct RecognitionTestView: View {

	let store: FaceEnrollmentStore

	@State private var camera = CameraController()
	@State private var score: Float = 0
	@State private var matched = false
	@State private var peak: Float = 0
	@State private var floor: Float = 1
	@State private var samples = 0
	@State private var lastDisplayUpdate = Date.distantPast

	/// Accumulated between publishes. It keeps the camera loop from redrawing the whole window
	/// thirty times per second while still retaining every sample for the summary metrics.
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
		VStack(spacing: 0) {
			RecognitionTestHeader(isEnrolled: store.isEnrolled)

			HStack(alignment: .top, spacing: 18) {
				RecognitionPreviewCard(
					camera: camera,
					matched: matched,
					status: statusText,
					symbol: verdictSymbol)

				RecognitionReadoutCard(
					score: score,
					threshold: store.embedder.matchThreshold,
					matched: matched,
					peak: peak,
					floor: floor == 1 ? 0 : floor,
					samples: samples,
					onReset: resetStats)
			}
			.padding(.horizontal, 28)
			.padding(.top, 22)

			HStack(spacing: 8) {
				Image(systemName: "info.circle")
					.foregroundStyle(Theme.secondaryLabel)
				Text("This window is diagnostic only. No password is entered and nothing is unlocked.")
					.font(Typography.caption)
					.foregroundStyle(Theme.tertiaryLabel)
				Spacer()
			}
			.padding(.horizontal, 30)
			.padding(.top, 16)
			.padding(.bottom, 22)
		}
		.frame(width: 720, height: 520)
		.background(WindowGlass(extraTranslucent: true))
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

	private var statusText: String {
		if case .failed(let reason) = camera.state { return reason }
		if camera.state == .denied { return "Camera access is off" }
		if !store.isEnrolled { return "Not enrolled" }
		if camera.faceMissing { return "No face detected" }
		return matched ? "Recognised" : "Not recognised"
	}

	private var verdictSymbol: String {
		if camera.state == .denied { return "video.slash.fill" }
		if !store.isEnrolled { return "person.crop.circle.badge.questionmark" }
		if camera.faceMissing { return "viewfinder" }
		return matched ? "checkmark" : "xmark"
	}

	private func resetStats() {
		pending.peak = 0
		pending.floor = 1
		pending.samples = 0
		publish()
	}

	/// Throttles visible updates to roughly 10Hz. Embedding still runs on every frame, so the
	/// peak and floor remain meaningful.
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

private struct RecognitionTestHeader: View {

	let isEnrolled: Bool

	var body: some View {
		HStack(alignment: .top, spacing: 11) {
			GazeMark(size: 40)
			VStack(alignment: .leading, spacing: 2) {
				Text("Recognition test")
					.font(.system(.title2, weight: .bold))
					.foregroundStyle(Theme.label)
				Text(isEnrolled ? "Measure confidence before enabling unlock" : "Set up Gaze before testing recognition")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
			}
			Spacer()
			StatusBadge(
				title: isEnrolled ? "LIVE DIAGNOSTICS" : "SETUP NEEDED",
				symbol: isEnrolled ? "waveform.path.ecg" : "exclamationmark",
				tint: isEnrolled ? Theme.faceID : Theme.warning)
		}
		.padding(.horizontal, 30)
		.padding(.top, 25)
	}
}

private struct RecognitionPreviewCard: View {

	let camera: CameraController
	let matched: Bool
	let status: String
	let symbol: String

	private let previewSize: CGFloat = 224

	var body: some View {
		DashboardCard(title: "Camera view", detail: "Only one face can be evaluated at a time.") {
			VStack(spacing: 14) {
				ZStack {
					Circle()
						.fill((matched ? Theme.faceID : Theme.action).opacity(0.10))
						.frame(width: previewSize + 22, height: previewSize + 22)

					switch camera.state {
					case .running:
						CameraPreview(controller: camera)
							.frame(width: previewSize, height: previewSize)
							.clipShape(.circle)
					case .denied, .failed:
						Circle()
							.fill(Theme.surfaceRaised)
							.frame(width: previewSize, height: previewSize)
							.overlay {
								Image(systemName: symbol)
									.font(.system(size: 28, weight: .medium))
									.foregroundStyle(Theme.warning)
							}
					case .idle:
						Circle()
							.fill(Theme.surfaceRaised)
							.frame(width: previewSize, height: previewSize)
							.overlay { ProgressView().controlSize(.large) }
					}

					Circle()
						.strokeBorder(matched ? Theme.faceID : Theme.softSeparator, lineWidth: matched ? 3 : 1)
						.frame(width: previewSize + 10, height: previewSize + 10)
				}

				StatusBadge(
					title: status.uppercased(),
					symbol: symbol,
					tint: matched ? Theme.faceID : (camera.state == .running ? Theme.secondaryLabel : Theme.warning))
			}
		}
		.frame(width: 326)
	}
}

private struct RecognitionReadoutCard: View {

	let score: Float
	let threshold: Float
	let matched: Bool
	let peak: Float
	let floor: Float
	let samples: Int
	let onReset: () -> Void

	var body: some View {
		DashboardCard(title: "Confidence", detail: "Your score needs to clear the threshold to match.") {
			VStack(alignment: .leading, spacing: 15) {
				HStack(alignment: .lastTextBaseline) {
					Text(String(format: "%.3f", score))
						.font(.system(size: 36, weight: .semibold, design: .rounded))
						.foregroundStyle(matched ? Theme.faceID : Theme.label)
						.monospacedDigit()
					Text(matched ? "MATCH" : "LIVE SCORE")
						.font(.system(.caption2, weight: .bold))
						.foregroundStyle(matched ? Theme.faceID : Theme.tertiaryLabel)
						.tracking(0.8)
						.padding(.leading, 7)
					Spacer()
				}

				ConfidenceMeter(score: score, threshold: threshold, matched: matched)

				HStack(spacing: 10) {
					RecognitionMetric(label: "LOWEST", value: floor, tint: Theme.warning, symbol: "arrow.down")
					RecognitionMetric(label: "HIGHEST", value: peak, tint: Theme.faceID, symbol: "arrow.up")
				}

				HStack {
					Text("\(samples) \(samples == 1 ? "sample" : "samples")")
						.font(Typography.caption)
						.foregroundStyle(Theme.tertiaryLabel)
					Text("Threshold \(String(format: "%.2f", threshold))")
						.font(Typography.mono)
						.foregroundStyle(Theme.secondaryLabel)
					Spacer()
				}

			Text("If this is you, watch the lowest. If it isn't, watch the highest.")
				.font(Typography.caption)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)

			Button("Reset measurements", action: onReset)
				.buttonStyle(.quiet)
				.frame(maxWidth: .infinity, alignment: .trailing)
			}
		}
		.frame(width: 326)
	}
}

private struct ConfidenceMeter: View {

	let score: Float
	let threshold: Float
	let matched: Bool

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				Capsule().fill(.white.opacity(0.08))
				Capsule()
					.fill(matched ? Theme.faceID : Theme.action)
					.frame(width: geometry.size.width * CGFloat(max(0, min(1, score))))
				Rectangle()
					.fill(Theme.label.opacity(0.70))
					.frame(width: 2)
					.offset(x: geometry.size.width * CGFloat(max(0, min(1, threshold))))
			}
		}
		.frame(height: 8)
		.animation(.smooth(duration: 0.16), value: score)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Recognition confidence")
		.accessibilityValue("\(String(format: "%.3f", score)); threshold \(String(format: "%.2f", threshold))")
	}
}

private struct RecognitionMetric: View {

	let label: String
	let value: Float
	let tint: Color
	let symbol: String

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(spacing: 4) {
				Image(systemName: symbol)
					.font(.system(.caption2, weight: .bold))
				Text(label)
					.font(.system(.caption2, weight: .semibold))
			}
			.foregroundStyle(tint)

			Text(String(format: "%.3f", value))
				.font(.system(.title3, design: .rounded, weight: .semibold))
				.foregroundStyle(Theme.label)
				.monospacedDigit()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(11)
		.background {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Theme.surfaceRaised.opacity(0.62))
			}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(label.lowercased()) score")
		.accessibilityValue(String(format: "%.3f", value))
	}
}
