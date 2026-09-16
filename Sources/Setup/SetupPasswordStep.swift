import SwiftUI

/// Takes the account password, which is what makes the unlock an unlock.
///
/// Without this the flow used to end on "You're all set" while the keystroke backend had
/// nothing to type — a success screen for an app that could recognise you and then do
/// nothing about it. The password belongs here rather than in Settings for the same
/// reason the camera permission does: it is not a preference, it is the thing the app
/// needs to work at all.
///
/// `PasswordVault.store` verifies against the local directory before saving, so a typo is
/// caught here rather than at the lock screen, where there is no way to fix it. The
/// verification is a directory call and can block, so it runs off the main actor and the
/// button says so while it is running.
struct SetupPasswordStep: View {

	var position: SetupPosition?
	var onSaved: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?

	@State private var password = ""
	@State private var isChecking = false
	@State private var error: String?
	@State private var shake = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var canSubmit: Bool { !password.isEmpty && !isChecking }

	var body: some View {
		SetupScaffold(
			position: position,
			title: "Your login password",
			message:
				"Use the password you enter to log in to this Mac.\nmacOS checks it before Gaze saves an encrypted copy.\nIf you change your Mac password later, save the new one in Gaze Settings.",
			figureHeight: 132,
			onBack: onBack
		) {
			SetupGlyph(symbol: "key.fill")
		} detail: {
			VStack(spacing: 0) {
				GlassField(
					placeholder: "Mac login password",
					text: $password,
					isEnabled: !isChecking,
					onSubmit: { if canSubmit { submit() } }
				)
					// The one place in setup where something is *wrong* rather than
					// merely unfinished, and the only place a nudge is warranted.
					.modifier(ShakeEffect(travel: shake, isEnabled: !reduceMotion))

				// Reserved whether or not it is filled, so the buttons below do not jump
				// up the screen the first time a password is wrong.
				Text(error ?? " ")
					.font(.caption)
					.foregroundStyle(error == nil ? .clear : Theme.danger)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
					.frame(height: 30, alignment: .top)
					.padding(.horizontal, 30)
					.padding(.top, 9)
			}
			.padding(.top, 22)
		} actions: {
			SetupButton(title: isChecking ? "Checking…" : "Save Password", action: submit)
				.disabled(!canSubmit)
			SetupSecondaryButton(title: "Set Up Later", action: onSkip)
				.disabled(isChecking)
		}
	}

	private func submit() {
		guard canSubmit else { return }
		let candidate = password
		isChecking = true
		error = nil

		Task {
			// Off the main actor: `verifyPassword` talks to OpenDirectory and a slow or
			// unreachable node would otherwise freeze the window mid-setup.
			let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Bool, Error> in
				do { return .success(try PasswordVault.store(candidate)) } catch { return .failure(error) }
			}.value

			await MainActor.run {
				isChecking = false
				switch outcome {
				case .success(true):
					password = ""
					onSaved()
				case .success(false):
					// Verified and rejected — the password itself is wrong.
					error = "That isn't the password for \(NSUserName())."
					password = ""
					if !reduceMotion { withAnimation(Theme.Motion.arrive) { shake += 1 } }
				case .failure(let failure):
					// Verified and then failed to save: the keychain refused, which is a
					// different problem and must not read as a typo.
					error = "Couldn't save it: \(failure.localizedDescription)"
				}
			}
		}
	}
}

/// A short horizontal shake, the length of one rejection.
///
/// A damped sine rather than a spring: a spring settles from wherever it is, so a second
/// wrong password entered before the first shake finished would start from an offset and
/// travel further than the first. This always covers the same distance and always ends at
/// zero, however often it is retriggered.
struct ShakeEffect: GeometryEffect {
	private var progress: CGFloat
	var isEnabled: Bool

	init(travel: Int, isEnabled: Bool = true) {
		progress = CGFloat(travel)
		self.isEnabled = isEnabled
	}

	var animatableData: CGFloat {
		get { progress }
		set { progress = newValue }
	}

	func effectValue(size: CGSize) -> ProjectionTransform {
		guard isEnabled else { return ProjectionTransform(.identity) }
		let phase = animatableData.truncatingRemainder(dividingBy: 1)
		let offset = sin(phase * .pi * 3) * 7 * (1 - phase)
		return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
	}
}
