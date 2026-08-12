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
			Spacer(minLength: 20)
			ringStack
			Spacer(minLength: 18)
			progressBar
			Spacer(minLength: 18)
			footer
		}
		.padding(.vertical, 36)
		.padding(.horizontal, 40)
		.frame(width: 480, height: 620)
		.background(Color.black)
		// Committed to dark, deliberately, rather than following the system.
		//
		// This window is mostly camera. A black surround is what keeps the eye on the preview
		// and stops the wall behind the app competing with the picture — the same reason Photo
		// Booth and QuickTime's recorder are dark whatever the system is set to. It also has a
		// hard `Color.black` ground, so following the appearance would put black text on it.
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
			// Which of the two passes is running. A ring that empties and refills with no
			// explanation reads as failure, so the step is stated before it happens.
			if let pass = currentPass {
				Text("Step \(pass) of 2")
					.font(Typography.metricLabel)
					.foregroundStyle(Theme.faceID)
					.tracking(0.6)
					.transition(.opacity)
			}

			Text(title)
				.font(.system(.largeTitle, weight: .bold))
				.foregroundStyle(Theme.label)

			Text(model?.instruction ?? "Starting the camera…")
				.font(Typography.row)
				.foregroundStyle(Theme.secondaryLabel)
				.multilineTextAlignment(.center)
				.frame(height: 40)
				.animation(.easeInOut(duration: 0.2), value: model?.instruction)
		}
		.animation(.easeInOut(duration: 0.25), value: currentPass)
	}

	private var currentPass: Int? {
		if case .capturing(let pass) = model?.phase { return pass }
		return nil
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
			// Blooms as coverage grows — a quiet reward for moving, and it keeps the
			// centre of the screen from being a dead black disc.
			Circle()
				.fill(
					RadialGradient(
						colors: [
							Theme.faceID.opacity(0.22 * (model?.progress ?? 0)),
							Theme.faceID.opacity(0),
						],
						center: .center, startRadius: 60, endRadius: 165))
				.frame(width: ringSize + 40, height: ringSize + 40)
				.animation(.easeOut(duration: 0.4), value: model?.progress)

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
				.foregroundStyle(Theme.warning)
			Text(title)
				.font(Typography.heroTitle)
				.foregroundStyle(Theme.label)
			Text(detail)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.multilineTextAlignment(.center)
		}
		.padding(.horizontal, 28)
		.frame(width: previewSize, height: previewSize)
		.background(Circle().fill(.white.opacity(0.05)))
	}

	/// A slim bar under the ring.
	///
	/// The ring alone is ambiguous about how much is left — the ticks fill in whatever
	/// order the head moves, so "nearly done" and "just started" can look similar. A
	/// linear bar answers that at a glance.
	private var progressBar: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				Capsule().fill(.white.opacity(0.08))
				Capsule()
					.fill(Theme.faceID)
					.frame(width: geometry.size.width * (model?.progress ?? 0))
			}
		}
		.frame(width: 190, height: 4)
		.animation(.easeOut(duration: 0.3), value: model?.progress)
		.opacity(currentPass == nil ? 0 : 1)
	}

	/// One button language, not three.
	///
	/// This stacked a `.borderedProminent` system button fourteen points above a bare green
	/// text button, with a third style waiting in the settings window — so a button looked
	/// like a different kind of object depending on which screen you were on. Both are the
	/// app's own style now: whichever action moves you forward is the filled one, and the
	/// way out is quiet beneath it.
	private var footer: some View {
		VStack(spacing: 10) {
			if let saveError {
				Text(saveError)
					.font(Typography.detail)
					.foregroundStyle(Theme.danger)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			if case .failed = model?.phase {
				Button {
					model?.reset()
				} label: {
					Text("Try Again").frame(maxWidth: .infinity)
				}
				.buttonStyle(.primaryAction)
				.keyboardShortcut(.defaultAction)
				.frame(width: 150)
			}

			if model?.phase == .complete {
				Button {
					onFinish()
				} label: {
					Text("Done").frame(maxWidth: .infinity)
				}
				.buttonStyle(.primaryAction)
				.keyboardShortcut(.defaultAction)
				.frame(width: 150)
			} else {
				Button("Cancel") { onFinish() }
					.buttonStyle(.quiet)
					.keyboardShortcut(.cancelAction)
			}
		}
	}

	// MARK: - Flow

	private func begin() async {
		// Nothing to do when the user is already enrolled — `EnrollmentWindow` is about to
		// dismiss itself. Starting the camera here meant an enrolled user paid for a live
		// 30fps preview, and a full SwiftUI redraw per frame, on every launch.
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
}
