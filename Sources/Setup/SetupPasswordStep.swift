import AppKit
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
	var onClose: (() -> Void)? = nil

	@State private var password = ""
	@State private var isChecking = false
	@State private var error: String?
	@State private var shake = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var canSubmit: Bool { !password.isEmpty && !isChecking }

	private var buttonTitle: String { isChecking ? "Checking…" : "Save Password" }

	private var page: TourPage {
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "Your login password",
			description: "Enter the password you type at login on this Mac. macOS checks it before Gaze saves an encrypted copy in the keychain."
		)
	}

	private var fieldBlock: some View {
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
				.frame(height: 22, alignment: .top)
				.padding(.horizontal, 30)
				.padding(.top, 9)
			Text("If you skip this, Gaze recognises you without unlocking until you add your password in Settings.")
				.font(.caption)
				.foregroundStyle(Color.white.opacity(0.6))
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 30)
		}
	}

	var body: some View {
		TourSlideshowView(
			pages: [page],
			width: GazeTourSizing.panelWidth,
			continueButtonTitle: "\(buttonTitle)",
			finishButtonTitle: "\(buttonTitle)",
			onFinish: submit,
			onClose: onClose ?? onSkip,
			pageMedia: { _ in AnyView(SetupPasswordFigure()) },
			mediaHeight: 250,
			pageAccessory: { _ in AnyView(fieldBlock) },
			primaryEnabled: canSubmit,
			secondaryButtonTitle: "Set Up Later",
			onSecondary: onSkip,
			footer: position.map { AnyView(SetupProgress(position: $0)) },
			onBack: onBack
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
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
					password = ""
				}
			}
		}
	}
}

/// The password step has no saved state of its own — a successful save calls
/// `onSaved` and leaves the step — so the companion stays neutral and the key
/// stays put. Kept as its own view so the figure reads as one piece.
private struct SetupPasswordFigure: View {
	var body: some View {
		ZStack {
			HStack(spacing: 40) {
				GazeLookingCompanion(look: 1, happy: false)
					.frame(width: 110, height: 110)
				Image(systemName: "key.fill")
					.font(.system(size: 52, weight: .medium))
					.foregroundStyle(.white)
					.symbolRenderingMode(.monochrome)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityHidden(true)
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
