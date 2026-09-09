import AppKit
import SwiftUI

/// The panel's contents: one small view per step, switched between.
///
/// Nothing here reimplements enrolment. `EnrollmentModel`, `EnrollmentRing` and
/// `CameraController` are the same ones the window flow uses — what changes is only the
/// frame they sit in. Rewriting the recognition side to change container would mean two
/// enrolments to keep in agreement, and the one that got less use would quietly rot.
struct SetupNotchContent: View {

	let store: FaceEnrollmentStore
	@Bindable var model: SetupNotchModel
	let onFinish: () -> Void

	var body: some View {
		Group {
			switch model.step {
			case .intro: intro
			case .permission: permission
			case .enrol: EnrolStep(store: store, onDone: { model.advance() })
			case .password: PasswordStep(onDone: { model.advance() })
			case .done: done
			}
		}
		// Steps cross-fade in place while the panel itself springs to the new height. The
		// movement is the window's job; if the content slid as well, two different things
		// would be moving at once and neither would read.
		.transition(.opacity)
		.animation(SetupNotchMetrics.resize, value: model.step)
	}

	// MARK: - Intro

	private var intro: some View {
		SetupNotchStepFrame(
			title: "Unlock by looking",
			detail: "Gaze watches for you when the screen is locked, and types your password when it recognises you."
		) {
			VStack(spacing: 8) {
				SetupNotchButton(title: "Continue") { model.advance() }
				Button("Not now") { onFinish() }
					.buttonStyle(.plain)
					.font(.system(size: 12))
					.foregroundStyle(.white.opacity(0.5))
			}
		}
	}

	// MARK: - Permission

	private var permission: some View {
		SetupNotchStepFrame(
			title: "Let Gaze type for you",
			detail: "macOS has no way for an app to authorise a login, so Gaze enters your password at the lock screen. That needs Accessibility."
		) {
			VStack(spacing: 8) {
				SetupNotchButton(title: "Open System Settings") {
					NSWorkspace.shared.open(
						URL(
							string:
								"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
						)!)
				}
				SetupNotchButton(title: "I've granted it", isProminent: false) {
					// Re-plan rather than advance blindly: if it still is not granted, the
					// step stays and the button can be pressed again.
					model.refreshPlan()
					if AXIsProcessTrusted() { model.advance() }
				}
			}
		}
	}

	// MARK: - Done

	private var done: some View {
		SetupNotchStepFrame(title: "Gaze is set up") {
			VStack(spacing: 8) {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(size: 26))
					.foregroundStyle(Theme.faceID)
				SetupNotchButton(title: "Done") { onFinish() }
			}
		}
	}
}

// MARK: - Enrol

/// The one step that does real work.
private struct EnrolStep: View {

	let store: FaceEnrollmentStore
	let onDone: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var failure: String?

	var body: some View {
		SetupNotchStepFrame(
			title: failure == nil ? "Look at the camera" : "That didn't work",
			detail: failure ?? model?.instruction
		) {
			ZStack {
				if let model {
					EnrollmentRing(
						covered: model.covered,
						currentAngle: model.currentAngle,
						isEngaged: model.isEngaged)
				}
			}
			.frame(width: 168, height: 168)
			.overlay {
				if failure != nil {
					SetupNotchButton(title: "Try again") { restart() }
						.frame(width: 140)
				}
			}
		}
		.task { await start() }
		.onDisappear { camera.stop() }
		// Driven off the frame counter rather than a timer: a sample is only worth
		// consuming when there is a new one, and the counter is what says so.
		.onChange(of: camera.frameID) { _, _ in
			guard let model, failure == nil else { return }
			model.consume(camera.sample)
			if model.phase == .complete { save(model) }
		}
	}

	private func start() async {
		guard model == nil else { return }
		model = EnrollmentModel(embedder: store.embedder)
		await camera.start()
		if camera.state != .running {
			failure = "The camera didn't start. Check that nothing else is using it."
		}
	}

	private func restart() {
		failure = nil
		model = EnrollmentModel(embedder: store.embedder)
		Task { await camera.start() }
	}

	private func save(_ model: EnrollmentModel) {
		camera.stop()
		do {
			// `boundDeviceID` is optional — the camera may have started without pinning a
			// device. Enrolling against no particular camera is still valid; it just means
			// the "built-in only" check has nothing to compare against later.
			try store.add(prints: model.prints, cameraID: camera.boundDeviceID ?? "")
			onDone()
		} catch {
			// Said out loud rather than swallowed. A capture that appears to finish and
			// silently saves nothing is the worst outcome here — the user believes they
			// are enrolled and finds out at the lock screen.
			failure = "Your face couldn't be saved. \(error.localizedDescription)"
		}
	}
}

// MARK: - Password

private struct PasswordStep: View {

	let onDone: () -> Void

	@State private var password = ""
	@State private var error: String?
	@FocusState private var focused: Bool

	var body: some View {
		SetupNotchStepFrame(
			title: "Your Mac password",
			detail: error
				?? "Stored in the Secure Enclave and only ever typed into your own lock screen."
		) {
			VStack(spacing: 8) {
				SecureField("Password", text: $password)
					.textFieldStyle(.plain)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.padding(.horizontal, 12)
					.padding(.vertical, 7)
					.background(Capsule().fill(.white.opacity(0.12)))
					.focused($focused)
					.onSubmit(store)

				SetupNotchButton(title: "Save", isEnabled: !password.isEmpty) { store() }
			}
		}
		.task {
			// After the panel has settled at its new height, or the field takes focus
			// while it is still growing and the caret jumps as it lands.
			try? await Task.sleep(for: .milliseconds(480))
			focused = true
		}
	}

	private func store() {
		guard !password.isEmpty else { return }
		do {
			// Verified before it is kept: a wrong password stored here fails silently at
			// the lock screen, days later, with nothing pointing back to this moment.
			guard try PasswordVault.store(password) else {
				error = "That isn't your Mac password."
				password = ""
				return
			}
			onDone()
		} catch {
			self.error = "Couldn't save it. \(error.localizedDescription)"
		}
	}
}
