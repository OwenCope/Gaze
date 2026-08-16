import SwiftUI

/// The opening screen.
///
/// One claim, one sentence saying what it costs, and a way out. The temptation
/// with a first screen is to explain the whole app; nobody reads that, and the
/// question actually being asked is only "do I want this at all". What the app
/// does with a face belongs on the screen where the face is taken, which is
/// where it appears.
struct SetupWelcomeStep: View {
	var onContinue: () -> Void
	var onSkip: () -> Void

	@State private var appeared = false

	var body: some View {
		VStack(spacing: 0) {
			Spacer()

			SetupMark(kind: .looking, diameter: 180)
				.scaleEffect(appeared ? 1 : 0.86)
				.opacity(appeared ? 1 : 0)
				.animation(.spring(response: 0.55, dampingFraction: 0.72), value: appeared)

			Spacer().frame(height: 36)

			Text("Unlock by looking")
				.font(.system(size: 30, weight: .bold))
				.multilineTextAlignment(.center)
				.opacity(appeared ? 1 : 0)
				.offset(y: appeared ? 0 : 10)
				.animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)

			Text("Gaze watches for you when your screen is locked, and enters your password when it recognizes you.")
				.font(.callout)
				.foregroundStyle(.white.opacity(0.6))
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 40)
				.padding(.top, 10)
				.opacity(appeared ? 1 : 0)
				.offset(y: appeared ? 0 : 10)
				.animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18), value: appeared)

			Spacer()

			VStack(spacing: 14) {
				SetupButton(action: onContinue)
				Button("Not now", action: onSkip)
					.buttonStyle(.plain)
					.font(.callout)
					.foregroundStyle(.white.opacity(0.5))
			}
			.opacity(appeared ? 1 : 0)
			.animation(.easeOut(duration: 0.4).delay(0.28), value: appeared)
		}
		.padding(.horizontal, 32)
		.padding(.bottom, 32)
		.onAppear { appeared = true }
	}
}
