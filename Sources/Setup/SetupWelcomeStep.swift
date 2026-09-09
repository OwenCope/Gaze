import SwiftUI

/// The opening screen.
///
/// One claim, one sentence saying what it costs, and a way out. The temptation
/// with a first screen is to explain the whole app; nobody reads that, and the
/// question actually being asked is only "do I want this at all". What the app
/// does with a face belongs on the screens where the face is taken, which is
/// where it appears.
///
/// The only screen set as a hero, and the only one with no progress row: you are
/// not on step one of anything until you have said yes.
struct SetupWelcomeStep: View {
	var onContinue: () -> Void
	var onSkip: () -> Void

	@State private var isSkipHovering = false

	var body: some View {
		SetupScaffold(
			title: "Unlock by looking",
			message:
				"Gaze watches for you when your screen is locked, and enters your password "
				+ "when it recognizes you.",
			isHero: true,
			// 216, not 180. The mark is the only object on an 880×660 window and it was
			// drawing at 130pt inside its own 180pt frame — small enough that the screen read
			// as a dialog that had lost its content rather than as a title page. The window
			// has the room; the one thing on it should use some of it.
			figureHeight: 216,
			showsHero: true
		) {
			SetupMark(kind: .looking, diameter: 216)
		} actions: {
			SetupButton(action: onContinue)

			// A control, not a line of grey text.
			//
			// "Not now" was `.buttonStyle(.plain)` with no padding and no hover, so it had a
			// hit target the exact size of the words and gave nothing back when the pointer
			// reached it — which on the one screen where somebody might genuinely want to
			// decline is the wrong thing to make hard to press. It stays quiet, because
			// declining should not compete with continuing, but it behaves like something
			// you can click.
			//
			// Lightens on hover rather than darkening: a darker chip on a dark ground reads
			// as a hole punched in the screen.
			Button("Not now", action: onSkip)
				.buttonStyle(.plain)
				.font(Typography.setupBody)
				.foregroundStyle(isSkipHovering ? Theme.setupSecondary : Theme.setupTertiary)
				.padding(.horizontal, 16)
				.padding(.vertical, 7)
				.background {
					Capsule().fill(.white.opacity(isSkipHovering ? 0.08 : 0))
				}
				.contentShape(.capsule)
				.onHover { isSkipHovering = $0 }
				.animation(Theme.Motion.quick, value: isSkipHovering)
		}
	}
}
