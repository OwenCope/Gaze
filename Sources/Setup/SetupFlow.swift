import SwiftUI

/// The steps of setup.
///
/// Three, not four. Positioning and capturing are phases of one job in
/// `EnrollmentModel`, so they are one screen that follows the model rather than
/// two with a Continue between them — a button asking someone to confirm what the
/// app can already see.
enum SetupStep: Int, CaseIterable {
	case welcome
	case capture
	case done

	/// Someone already enrolled who opens setup anyway has no face to take, so
	/// there is nothing to show between the two ends. "Set Up Again" is a request
	/// to take it again and asks for the whole flow.
	static func shown(isEnrolled: Bool) -> [SetupStep] {
		isEnrolled ? [.welcome, .done] : allCases
	}
}

/// Setup, start to finish.
///
/// The flow owns the camera and the enrollment model rather than the steps owning
/// them. Steps come and go as people move through, and a camera owned by a step
/// would be opened and closed at every transition — a visible stall, a fresh
/// exposure ramp each time, and enrollment progress thrown away and restarted.
///
/// There is no step indicator and no back button. Both were in the first draft
/// and both were answering questions nobody asks during a three-screen flow that
/// cannot be got wrong: a progress dial for two screens is decoration, and the
/// only way back is out, which is what the window's own close button is for.
///
/// Dark throughout, like the rest of Gaze. Not decoration either: the screen is
/// mostly camera, and a dark surround stops the room behind the app competing
/// with the picture and keeps the face the brightest thing on it.
struct SetupFlow: View {

	let store: FaceEnrollmentStore
	/// Force the whole flow even when a face is saved. "Set Up Again" asks for
	/// exactly that, and skipping the capture there would silently do nothing.
	var forceFullFlow = false
	var onFinish: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var step: SetupStep = .welcome
	@State private var failure: String?

	private var steps: [SetupStep] {
		SetupStep.shown(isEnrolled: store.isEnrolled && !forceFullFlow)
	}

	var body: some View {
		Group {
			switch step {
			case .welcome:
				SetupWelcomeStep(onContinue: advance, onSkip: onFinish)
			case .capture:
				SetupCaptureStep(camera: camera, model: model, onAuthorized: startCamera)
			case .done:
				SetupDoneStep(failure: failure, onDone: onFinish, onRetry: retry)
			}
		}
		.transition(.opacity)
		.id(step)
		.frame(width: 440, height: 600)
		.background(Color.black)
		.preferredColorScheme(.dark)
		.onDisappear { camera.stop() }
		// Driven by the frame counter rather than the pose: two identical
		// consecutive poses are normal and must still advance the state machine.
		.onChange(of: camera.frameID) { _, _ in
			guard step == .capture else { return }
			model?.consume(camera.faceMissing ? nil : camera.sample)
		}
		.onChange(of: model?.phase) { _, phase in
			switch phase {
			case .complete: save()
			case .failed(let message): fail(message)
			default: break
			}
		}
	}

	// MARK: - Flow

	private func advance() {
		guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
		withAnimation(.easeInOut(duration: 0.3)) { step = steps[index + 1] }
	}

	/// Called once the capture screen has permission — not on entry.
	///
	/// Starting the camera before permission exists is what puts the system's own
	/// prompt on screen at a moment nobody asked for it.
	private func startCamera() {
		guard model == nil else { return }
		model = EnrollmentModel(embedder: store.embedder)
		Task { await camera.start() }
	}

	private func save() {
		guard let model, let cameraID = camera.boundDeviceID else { return }
		do {
			try store.save(prints: model.prints, cameraID: cameraID)
			camera.stop()
			failure = nil
			withAnimation(.easeInOut(duration: 0.3)) { step = .done }
		} catch {
			fail("Couldn't save your face: \(error.localizedDescription)")
		}
	}

	private func fail(_ message: String) {
		camera.stop()
		failure = message
		withAnimation(.easeInOut(duration: 0.3)) { step = .done }
	}

	/// Start over after a failure.
	///
	/// A fresh model rather than `reset()` on the old one: whatever it captured
	/// before giving up is exactly the material that failed, and carrying it into
	/// the retry is how the second attempt fails the same way as the first.
	private func retry() {
		failure = nil
		model = EnrollmentModel(embedder: store.embedder)
		withAnimation(.easeInOut(duration: 0.3)) { step = .capture }
		Task { await camera.start() }
	}
}
