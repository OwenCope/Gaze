import SwiftUI

/// The last screen — which is not always a success.
///
/// Enrollment can end badly: the camera covered, the face never resolved, the
/// keychain refusing to save. A flow whose final screen is always a green tick
/// would claim success for those too, and the person would find out at the lock
/// screen. Same screen, both outcomes, and the failure says what actually went
/// wrong rather than "something went wrong".
struct SetupDoneStep: View {

	/// Nil when enrollment succeeded.
	let failure: String?
	var onDone: () -> Void
	var onRetry: () -> Void

	@State private var trigger = 0

	private var didFail: Bool { failure != nil }

	var body: some View {
		VStack(spacing: 0) {
			Spacer()

			SetupMark(kind: didFail ? .failure : .success, diameter: 180, trigger: trigger)

			Spacer().frame(height: 36)

			Text(didFail ? "Setup didn't finish" : "You're all set")
				.font(.system(size: 30, weight: .bold))
				.multilineTextAlignment(.center)

			Text(failure ?? "Lock your screen and look at your Mac. Your password still works whenever you want it.")
				.font(.callout)
				.foregroundStyle(.white.opacity(0.6))
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 40)
				.padding(.top, 10)

			Spacer()

			VStack(spacing: 14) {
				SetupButton(title: didFail ? "Try Again" : "Done", action: didFail ? onRetry : onDone)
				if didFail {
					Button("Close", action: onDone)
						.buttonStyle(.plain)
						.font(.callout)
						.foregroundStyle(.white.opacity(0.5))
				}
			}
		}
		.padding(.horizontal, 32)
		.padding(.bottom, 32)
		// Played once the view is actually on screen rather than on appear, so it
		// does not run underneath the step transition and finish before it is seen.
		.task {
			try? await Task.sleep(for: .milliseconds(140))
			trigger += 1
		}
	}
}
