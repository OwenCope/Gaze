import AppKit
import SwiftUI

/// The panel's contents: one step at a time, each laid out at its natural height.
///
/// Nothing here sets a height. Every step is a stack that takes the room its content needs,
/// and `measuringPanelHeight()` at the root reports the result so the window can follow.
/// That is the difference from the previous three attempts, all of which failed at the same
/// seam — a container sized independently of the thing inside it.
struct SetupNotchContent: View {

	let store: FaceEnrollmentStore
	@Bindable var model: SetupNotchModel
	let onFinish: () -> Void

	var body: some View {
		VStack(spacing: 16) {
			step
				// Steps swap by fading and travelling a few points in the direction of
				// travel, while the panel itself changes height. Two movements, one
				// direction, one spring — so it reads as the panel turning a page rather
				// than as content being replaced inside a box that happens to resize.
				.transition(
					.asymmetric(
						insertion: .opacity.combined(with: .offset(y: 8)),
						removal: .opacity.combined(with: .offset(y: -8))))
				.id(model.step)

			if let progress = model.progress, model.step != .done {
				SetupNotchProgress(index: progress.index, count: progress.count)
			}
		}
		.padding(.horizontal, SetupNotchMetrics.horizontalPadding)
		.padding(.top, 18)
		.padding(.bottom, SetupNotchMetrics.verticalPadding)
		.animation(SetupNotchMetrics.morph, value: model.step)
		.measuringPanelHeight()
	}

	@ViewBuilder
	private var step: some View {
		switch model.step {
		case .intro: IntroStep(onContinue: { model.advance() }, onSkip: onFinish)
		case .permission: PermissionStep(model: model)
		case .enrol: EnrolStep(store: store, onDone: { model.advance() })
		case .password: PasswordStep(onDone: { model.advance() })
		case .done: DoneStep(onFinish: onFinish)
		}
	}
}

// MARK: - Intro

private struct IntroStep: View {

	let onContinue: () -> Void
	let onSkip: () -> Void

	@State private var arrived = false

	var body: some View {
		VStack(spacing: 12) {
			// The app's own icon, which is the keyhole. Drawn from the running app rather
			// than re-rendered, so it can never disagree with what is in the Dock.
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 56, height: 56)
				.scaleEffect(arrived ? 1 : 0.88)
				.opacity(arrived ? 1 : 0)

			VStack(spacing: 5) {
				Text("Unlock by looking")
					.font(.system(size: 20, weight: .semibold))
					.foregroundStyle(.white)
				Text("Gaze watches for you when the screen is locked, and types your password when it recognises you.")
					.font(.system(size: 12))
					.foregroundStyle(.white.opacity(0.6))
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(spacing: 6) {
				SetupNotchButton(title: "Continue", action: onContinue)
				SetupNotchQuietButton(title: "Not now", action: onSkip)
			}
			.padding(.top, 2)
		}
		.task {
			// The icon settles a beat after the panel has finished dropping, so the two
			// movements are sequential rather than simultaneous.
			try? await Task.sleep(for: .milliseconds(120))
			withAnimation(SetupNotchMetrics.morph) { arrived = true }
		}
	}
}

// MARK: - Permission

private struct PermissionStep: View {

	@Bindable var model: SetupNotchModel

	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: "hand.raised.fill")
				.font(.system(size: 30))
				.foregroundStyle(Theme.warning)

			VStack(spacing: 5) {
				Text("Let Gaze type for you")
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white)
				Text("macOS has no way for an app to authorise a login, so Gaze enters your password at the lock screen. That needs Accessibility.")
					.font(.system(size: 12))
					.foregroundStyle(.white.opacity(0.6))
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(spacing: 6) {
				SetupNotchButton(title: "Open System Settings") {
					NSWorkspace.shared.open(
						URL(
							string:
								"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
						)!)
				}
				SetupNotchButton(title: "I've granted it", isProminent: false) {
					model.refreshPlan()
					if AXIsProcessTrusted() { model.advance() }
				}
			}
			.padding(.top, 2)
		}
	}
}

// MARK: - Enrol

/// The centrepiece. The ring is the largest thing in the flow because it is the only step
/// that asks anything of you, and because it is the one moment the panel is doing something
/// rather than saying something.
private struct EnrolStep: View {

	let store: FaceEnrollmentStore
	let onDone: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var failure: String?

	var body: some View {
		VStack(spacing: 14) {
			ZStack {
				if let model {
					EnrollmentRing(
						covered: model.covered,
						currentAngle: model.currentAngle,
						isEngaged: model.isEngaged)
				} else {
					Circle().stroke(.white.opacity(0.12), lineWidth: 2)
				}
			}
			.frame(width: 176, height: 176)

			Text(failure ?? model?.instruction ?? "Starting the camera…")
				.font(.system(size: 13, weight: failure == nil ? .medium : .regular))
				.foregroundStyle(failure == nil ? .white.opacity(0.85) : Theme.warning)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				// Cross-fades between prompts instead of the text snapping, which at this
				// size is the difference between a hint and a flicker.
				.animation(SetupNotchMetrics.morph, value: model?.instruction)

			if failure != nil {
				SetupNotchButton(title: "Try again", action: restart)
			}
		}
		.task { await start() }
		.onDisappear { camera.stop() }
		// Driven off the frame counter: a sample is only worth consuming when there is a
		// new one, and the counter is what says so.
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
			failure = "The camera didn't start. Check nothing else is using it."
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
			try store.add(prints: model.prints, cameraID: camera.boundDeviceID ?? "")
			onDone()
		} catch {
			// Said out loud rather than swallowed. A capture that appears to finish and
			// saves nothing is the worst outcome here — the user believes they are enrolled
			// and finds out at the lock screen.
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
		VStack(spacing: 12) {
			Image(systemName: "key.fill")
				.font(.system(size: 26))
				.foregroundStyle(.white.opacity(0.8))

			VStack(spacing: 5) {
				Text("Your Mac password")
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white)
				Text(error ?? "Kept in the Secure Enclave, and only ever typed into your own lock screen.")
					.font(.system(size: 12))
					.foregroundStyle(error == nil ? .white.opacity(0.6) : Theme.warning)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(spacing: 6) {
				SecureField("Password", text: $password)
					.textFieldStyle(.plain)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background {
						Capsule()
							.fill(.white.opacity(focused ? 0.16 : 0.11))
							.overlay {
								Capsule().stroke(.white.opacity(focused ? 0.28 : 0), lineWidth: 1)
							}
					}
					.animation(SetupNotchMetrics.hover, value: focused)
					.focused($focused)
					.onSubmit(save)

				SetupNotchButton(title: "Save", isEnabled: !password.isEmpty, action: save)
			}
			.padding(.top, 2)
		}
		.task {
			// After the panel has settled, or the caret lands while the window is still
			// growing and jumps as it arrives.
			try? await Task.sleep(for: .milliseconds(SetupNotchMetrics.morphDuration * 1000 + 60))
			focused = true
		}
	}

	private func save() {
		guard !password.isEmpty else { return }
		do {
			// Verified before it is kept: a wrong password stored here fails silently at
			// the lock screen days later, with nothing pointing back to this moment.
			guard try PasswordVault.store(password) else {
				withAnimation(SetupNotchMetrics.morph) { error = "That isn't your Mac password." }
				password = ""
				return
			}
			onDone()
		} catch {
			withAnimation(SetupNotchMetrics.morph) {
				self.error = "Couldn't save it. \(error.localizedDescription)"
			}
		}
	}
}

// MARK: - Done

private struct DoneStep: View {

	let onFinish: () -> Void

	@State private var arrived = false

	var body: some View {
		VStack(spacing: 10) {
			Image(systemName: "checkmark.circle.fill")
				.font(.system(size: 34))
				.foregroundStyle(Theme.faceID)
				// Arrives from slightly small rather than from nothing. Nothing in the real
				// world appears from zero; it arrives from a little out of place.
				.scaleEffect(arrived ? 1 : 0.6)
				.opacity(arrived ? 1 : 0)

			Text("Gaze is set up")
				.font(.system(size: 18, weight: .semibold))
				.foregroundStyle(.white)

			SetupNotchButton(title: "Done", action: onFinish)
				.padding(.top, 2)
		}
		.task {
			withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) { arrived = true }
		}
	}
}
