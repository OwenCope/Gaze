import SwiftUI

/// The face setup flow: a calm, guided capture experience with the live preview at its centre.
struct EnrollmentView: View {

	let store: FaceEnrollmentStore
	var onFinish: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var saveError: String?
	@State private var isRestoring = false

	private let ringSize: CGFloat = 280
	private let ring = EnrollmentRing(covered: [], currentAngle: 0, isEngaged: false)

	var body: some View {
		VStack(spacing: 0) {
			EnrollmentTopBar(
				onCancel: onFinish,
				canRestore: store.legacyDataAvailable,
				isRestoring: isRestoring,
				onRestore: restorePreviousSetup)

			HStack(alignment: .center, spacing: 30) {
				EnrollmentGuidance(
					title: title,
					instruction: model?.instruction ?? "Starting the camera…",
					currentPass: currentPass,
					progress: model?.progress ?? 0,
					cameraState: camera.state)

				EnrollmentCapturePreview(
					camera: camera,
					model: model,
					ringSize: ringSize,
					previewInset: ring.previewInset)
			}
			.padding(.horizontal, 30)
			.padding(.top, 26)

			EnrollmentFooter(
				phase: model?.phase,
				error: saveError,
				onRetry: { model?.reset() },
				onDone: onFinish,
				onCancel: onFinish)
			.padding(.horizontal, 30)
			.padding(.top, 22)
			.padding(.bottom, 24)
		}
		.frame(width: 700, height: 590)
		.background(WindowGlass(extraTranslucent: true))
		.preferredColorScheme(.dark)
		.task { await begin() }
		.onDisappear { camera.stop() }
		// Drive the state machine from each delivered frame, not from pose changes. A still head
		// is exactly what the user should be allowed to do between two directions.
		.onChange(of: camera.frameID) { _, _ in
			model?.consume(camera.faceMissing ? nil : camera.sample)
		}
		.onChange(of: model?.phase) { _, phase in
			if phase == .complete { finish() }
		}
	}

	private var currentPass: Int? {
		if case .capturing(let pass) = model?.phase { return pass }
		return nil
	}

	private var title: String {
		switch model?.phase {
		case .complete: return "Gaze is ready"
		case .capturing(let pass) where pass == 2: return "One more scan"
		default: return "Set up Gaze"
		}
	}

	private func begin() async {
		guard !store.isEnrolled else { return }

		model = EnrollmentModel(embedder: store.embedder)
		await camera.start()
	}

	private func finish() {
		guard let model, let cameraID = camera.boundDeviceID else { return }
		do {
			try store.save(prints: model.prints, cameraID: cameraID)
			camera.stop()
			onFinish()
		} catch {
			saveError = "Couldn't save your face: \(error.localizedDescription)"
		}
	}

	private func restorePreviousSetup() {
		guard !isRestoring else { return }
		isRestoring = true
		saveError = nil

		do {
			let count = try store.restoreLegacyData()
			isRestoring = false
			if store.isEnrolled {
				onFinish()
			} else if count > 0 {
				saveError = "Previous Gaze data was restored. Set up a face to continue."
			} else {
				saveError = "No previous Gaze data was found."
			}
		} catch {
			isRestoring = false
			saveError = "Couldn't restore the previous setup: \(error.localizedDescription)"
		}
	}
}

private struct EnrollmentTopBar: View {

	let onCancel: () -> Void
	let canRestore: Bool
	let isRestoring: Bool
	let onRestore: () -> Void

	var body: some View {
		HStack(spacing: 11) {
			GazeMark(size: 38)
			VStack(alignment: .leading, spacing: 1) {
				Text("Gaze setup")
					.font(.system(.headline, weight: .semibold))
					.foregroundStyle(Theme.label)
				Text("On-device face enrollment")
					.font(Typography.caption)
					.foregroundStyle(Theme.secondaryLabel)
			}
			Spacer()
			if canRestore {
				Button(isRestoring ? "Restoring…" : "Restore previous setup", action: onRestore)
					.buttonStyle(.quiet)
					.disabled(isRestoring)
					.help("Import data from an earlier Gaze build")
			}
			Button("Cancel", action: onCancel)
				.buttonStyle(.quiet)
				.keyboardShortcut(.cancelAction)
		}
		.padding(.horizontal, 30)
		.padding(.top, 24)
	}
}

private struct EnrollmentGuidance: View {

	let title: String
	let instruction: String
	let currentPass: Int?
	let progress: Double
	let cameraState: CameraController.State

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if let currentPass {
				StatusBadge(
					title: "STEP \(currentPass) OF 2",
					symbol: "arrow.triangle.2.circlepath",
					tint: Theme.faceID)
				.padding(.bottom, 18)
			}

			Text(title)
				.font(.system(.largeTitle, weight: .bold))
				.foregroundStyle(Theme.label)
				.fixedSize(horizontal: false, vertical: true)

			Text(instruction)
				.font(.system(.title3, weight: .medium))
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.top, 8)

			if currentPass != nil {
				VStack(alignment: .leading, spacing: 7) {
					HStack {
						Text("Capture progress")
							.font(Typography.caption)
							.foregroundStyle(Theme.tertiaryLabel)
						Spacer()
						Text("\(Int(progress * 100))%")
							.font(Typography.mono)
							.foregroundStyle(Theme.faceID)
					}
					ProgressView(value: progress)
						.progressViewStyle(.linear)
						.tint(Theme.faceID)
				}
				.padding(.top, 26)
			}

			VStack(alignment: .leading, spacing: 13) {
				EnrollmentTip(symbol: "move.3d", title: "Move slowly", detail: "Turn your head through a comfortable range.")
				EnrollmentTip(symbol: "light.max", title: "Find soft light", detail: "Keep your face evenly lit and easy to see.")
				EnrollmentTip(symbol: "lock.shield", title: "Kept on this Mac", detail: "Only faceprints are saved, never camera images.")
			}
			.padding(.top, 28)

			if case .denied = cameraState {
				Text("Allow camera access in System Settings › Privacy & Security › Camera.")
					.font(Typography.caption)
					.foregroundStyle(Theme.warning)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, 20)
			}
		}
		.frame(maxWidth: 270, alignment: .leading)
	}
}

private struct EnrollmentTip: View {

	let symbol: String
	let title: String
	let detail: String

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: symbol)
				.font(.system(.body, weight: .medium))
				.foregroundStyle(Theme.faceID)
				.frame(width: 20)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(Theme.label)
				Text(detail)
					.font(Typography.caption)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

private struct EnrollmentCapturePreview: View {

	let camera: CameraController
	let model: EnrollmentModel?
	let ringSize: CGFloat
	let previewInset: CGFloat

	var body: some View {
		VStack(spacing: 13) {
			ZStack {
				Circle()
					.fill(Theme.faceID.opacity(0.05))
					.frame(width: ringSize + 26, height: ringSize + 26)

				preview

				if let model {
					EnrollmentRing(
						covered: model.covered,
						currentAngle: model.currentAngle,
						isEngaged: model.isEngaged)
				}
			}
			.frame(width: ringSize, height: ringSize)

			HStack(spacing: 7) {
				Circle()
					.fill(statusTint)
					.frame(width: 7, height: 7)
				Text(statusTitle)
					.font(Typography.caption)
					.foregroundStyle(Theme.secondaryLabel)
			}
		}
		.frame(width: 320)
	}

	@ViewBuilder
	private var preview: some View {
		switch camera.state {
		case .running:
			CameraPreview(controller: camera)
				.frame(width: ringSize - previewInset * 2, height: ringSize - previewInset * 2)
				.clipShape(.circle)
				.overlay {
					Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1)
				}
		case .denied:
				captureMessage(title: "Camera access is off", symbol: "video.slash.fill", tint: Theme.warning)
		case .failed:
				captureMessage(title: "Camera unavailable", symbol: "exclamationmark.triangle.fill", tint: Theme.warning)
		case .idle:
				ZStack {
					Circle().fill(.white.opacity(0.06))
					ProgressView().controlSize(.large)
				}
				.frame(width: ringSize - previewInset * 2, height: ringSize - previewInset * 2)
		}
	}

	private func captureMessage(title: String, symbol: String, tint: Color) -> some View {
		VStack(spacing: 10) {
			Image(systemName: symbol)
				.font(.system(size: 25, weight: .medium))
				.foregroundStyle(tint)
			Text(title)
				.font(.system(.headline, weight: .semibold))
				.foregroundStyle(Theme.label)
				.multilineTextAlignment(.center)
		}
		.padding(22)
		.frame(width: ringSize - previewInset * 2, height: ringSize - previewInset * 2)
		.background(Circle().fill(.white.opacity(0.06)))
	}

	private var statusTitle: String {
		switch camera.state {
		case .running:
			if model?.isEngaged == true { return "Move through the ring" }
			return "Position your face to begin"
		case .denied: return "Camera permission required"
		case .failed: return "Camera could not start"
		case .idle: return "Starting camera…"
		}
	}

	private var statusTint: Color {
		switch camera.state {
		case .running: return model?.isEngaged == true ? Theme.faceID : Theme.secondaryLabel
		case .denied, .failed: return Theme.warning
		case .idle: return Theme.secondaryLabel
		}
	}
}

private struct EnrollmentFooter: View {

	let phase: EnrollmentModel.Phase?
	let error: String?
	let onRetry: () -> Void
	let onDone: () -> Void
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 10) {
			if let error {
				Text(error)
					.font(Typography.caption)
					.foregroundStyle(Theme.danger)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack {
				Text("Faceprints are encrypted by the Secure Enclave.")
					.font(Typography.caption)
					.foregroundStyle(Theme.tertiaryLabel)
				Spacer()

				switch phase {
				case .failed:
					Button("Try Again", action: onRetry)
						.buttonStyle(.accent)
						.keyboardShortcut(.defaultAction)
				case .complete:
					Button("Done", action: onDone)
						.buttonStyle(.primaryAction)
						.keyboardShortcut(.defaultAction)
				default:
					Button("Cancel", action: onCancel)
						.buttonStyle(.quiet)
						.keyboardShortcut(.cancelAction)
				}
			}
		}
	}
}
