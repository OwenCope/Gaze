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

	private let circleSize: CGFloat = 210

	var body: some View {
		VStack(spacing: 20) {
			header
			preview
			readout
			Spacer(minLength: 0)
		}
		.padding(28)
		.frame(width: 420, height: 560)
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
					matched ? Theme.accent : Theme.separator,
					lineWidth: matched ? 3 : 1)
				.frame(width: circleSize + 10, height: circleSize + 10)
				.animation(.easeOut(duration: 0.18), value: matched)
		}
	}

	private var readout: some View {
		VStack(spacing: 14) {
			// The bar is the point of this screen. A score that hovers just under the
			// threshold means recognition is unreliable; one that sits well clear of it
			// means it is usable.
			VStack(spacing: 6) {
				GeometryReader { geometry in
					ZStack(alignment: .leading) {
						Capsule().fill(Theme.surface)
						Capsule()
							.fill(matched ? Theme.accent : Theme.warning)
							.frame(width: geometry.size.width * CGFloat(max(0, min(1, score))))
						// Where the match threshold sits.
						Rectangle()
							.fill(Theme.label.opacity(0.5))
							.frame(width: 2)
							.offset(x: geometry.size.width * CGFloat(store.embedder.matchThreshold))
					}
				}
				.frame(height: 10)

				HStack {
					Text(String(format: "score %.3f", score))
					Spacer()
					Text(String(format: "threshold %.3f", store.embedder.matchThreshold))
				}
				.font(.system(size: 10, design: .monospaced))
				.foregroundStyle(Theme.tertiaryLabel)
			}

			Text(statusText)
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(matched ? Theme.accent : Theme.secondaryLabel)

			// Both ends matter, and which one matters depends on who is sitting there.
			// For the enrolled person the floor decides how often they get wrongly
			// rejected; for anyone else the peak decides how likely a wrong accept is.
			// A threshold set from a single reading is set from neither.
			VStack(spacing: 4) {
				HStack(spacing: 16) {
					Text(String(format: "low %.3f", floor == 1 ? 0 : floor))
						.foregroundStyle(Theme.warning)
					Text(String(format: "high %.3f", peak))
						.foregroundStyle(Theme.accent)
					Text("\(samples) samples")
						.foregroundStyle(Theme.tertiaryLabel)
				}
				.font(.system(size: 11, design: .monospaced))

				Text("If this is you, watch the low. If it isn't, watch the high.")
					.font(.system(size: 10))
					.foregroundStyle(Theme.tertiaryLabel)

				Button("Reset") {
					peak = 0
					floor = 1
					samples = 0
				}
				.buttonStyle(AccentButtonStyle())
				.padding(.top, 4)
			}
		}
	}

	private var statusText: String {
		if case .failed(let reason) = camera.state { return reason }
		if camera.state == .denied { return "Camera access is off" }
		if !store.isEnrolled { return "Not enrolled" }
		if camera.faceMissing { return "No face" }
		return matched ? "Recognised" : "Not recognised"
	}

	private func evaluate() {
		guard store.isEnrolled, !camera.faceMissing, let sample = camera.sample else {
			matched = false
			score = 0
			return
		}
		let result = store.matches(sample)
		score = result.score
		matched = result.matched
		peak = max(peak, result.score)
		floor = min(floor, result.score)
		samples += 1
	}
}
