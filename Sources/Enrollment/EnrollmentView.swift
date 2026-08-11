import SwiftUI

/// The face setup flow: a circular live preview inside the coverage ring.
///
/// Dark throughout, like Face ID setup on every Apple platform. The dark ground is not
/// decoration — it is what makes the unfilled ticks recede and the green ones read at a
/// glance, and it keeps the user's own lit face the brightest thing on screen.
struct EnrollmentView: View {

	let store: FaceEnrollmentStore
	var onFinish: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var saveError: String?

	private let ringSize: CGFloat = 300
	private let ring = EnrollmentRing(covered: [], currentAngle: 0, isEngaged: false)

	var body: some View {
		VStack(spacing: 0) {
			header
			Spacer(minLength: 24)
			ringStack
			Spacer(minLength: 24)
			footer
		}
		.padding(.vertical, 36)
		.padding(.horizontal, 40)
		.frame(width: 480, height: 620)
		.background(Color.black)
		.preferredColorScheme(.dark)
		.task { await begin() }
		.onDisappear { camera.stop() }
		// Driven by the frame counter, not the pose: identical consecutive poses are
		// normal and must still advance the state machine.
		.onChange(of: camera.frameID) { _, _ in
			model?.consume(camera.faceMissing ? nil : camera.sample)
		}
		.onChange(of: model?.phase) { _, phase in
			if phase == .complete { finish() }
		}
	}

	// MARK: - Sections

	private var header: some View {
		VStack(spacing: 10) {
			Text(title)
				.font(.system(size: 26, weight: .bold))
				.foregroundStyle(.white)
			Text(model?.instruction ?? "Starting the camera…")
				.font(.system(size: 14))
				.foregroundStyle(.white.opacity(0.6))
				.multilineTextAlignment(.center)
				.frame(height: 40)
				.animation(.easeInOut(duration: 0.2), value: model?.instruction)
		}
	}

	private var title: String {
		switch model?.phase {
		case .complete: return "Face ID Is Set Up"
		case .capturing(let pass) where pass == 2: return "Second Scan"
		default: return "Set Up Face ID"
		}
	}

	private var ringStack: some View {
		ZStack {
			preview
			if let model {
				EnrollmentRing(
					covered: model.covered,
					currentAngle: model.currentAngle,
					isEngaged: model.isEngaged)
			}
		}
		.frame(width: ringSize, height: ringSize)
	}

	private var previewSize: CGFloat { ringSize - ring.previewInset * 2 }

	@ViewBuilder
	private var preview: some View {
		switch camera.state {
		case .running:
			CameraPreview(controller: camera)
				.frame(width: previewSize, height: previewSize)
				.clipShape(.circle)
				.overlay {
					Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
				}
		case .denied:
			message(
				"Camera Access Is Off",
				detail: "Allow camera access for Face ID in System Settings › Privacy & Security.")
		case .failed(let reason):
			message("Can't Use the Camera", detail: reason)
		case .idle:
			ZStack {
				Circle().fill(.white.opacity(0.05))
				ProgressView().controlSize(.large)
			}
			.frame(width: previewSize, height: previewSize)
		}
	}

	private func message(_ title: String, detail: String) -> some View {
		VStack(spacing: 8) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 26))
				.foregroundStyle(.orange)
			Text(title)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(.white)
			Text(detail)
				.font(.system(size: 12))
				.foregroundStyle(.white.opacity(0.55))
				.multilineTextAlignment(.center)
		}
		.padding(.horizontal, 28)
		.frame(width: previewSize, height: previewSize)
		.background(Circle().fill(.white.opacity(0.05)))
	}

	/// Live numbers from the pipeline.
	///
	/// Kept in the build because when enrolment stalls there is no way to tell from the
	/// UI alone whether the camera, Vision's pose estimation, or the coverage logic is at
	/// fault — and "nothing happens" is the failure mode this flow has.
	private var diagnostics: some View {
		let pose = camera.sample?.pose
		return VStack(spacing: 3) {
			Text(
				camera.faceMissing
					? "no single face in frame"
					: String(
						format: "yaw %+.2f   pitch %+.2f   quality %.2f",
						pose?.yaw ?? 0, pose?.pitch ?? 0, camera.sample?.quality ?? 0))
			Text(
				String(
					format: "frames %llu   covered %.0f%%   prints %d",
					camera.frameID, (model?.progress ?? 0) * 100, model?.prints.count ?? 0))
		}
		.font(.system(size: 10, design: .monospaced))
		.foregroundStyle(.white.opacity(0.35))
	}

	private var footer: some View {
		VStack(spacing: 14) {
			diagnostics
			if let saveError {
				Text(saveError)
					.font(.system(size: 12))
					.foregroundStyle(.red)
					.multilineTextAlignment(.center)
			}

			if case .failed = model?.phase {
				Button("Try Again") { model?.reset() }
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
					.keyboardShortcut(.defaultAction)
			}

			Button(model?.phase == .complete ? "Done" : "Cancel") { onFinish() }
				.buttonStyle(.plain)
				.foregroundStyle(Color(red: 0.20, green: 0.82, blue: 0.35))
				.font(.system(size: 14, weight: .medium))
				.keyboardShortcut(.cancelAction)
		}
	}

	// MARK: - Flow

	private func begin() async {
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
}
