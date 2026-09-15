import SwiftUI

/// What setup could not finish, read at the moment the last screen is shown.
struct SetupUnfinished: Equatable {
	var needsPassword = false
	var needsAccessibility = false

	var isComplete: Bool { !needsPassword && !needsAccessibility }

	/// The one sentence that says what is still missing.
	///
	/// Both missing is one sentence rather than two bullets: they are skipped together
	/// by the same person pressing "later" twice, and a list of two makes it read like
	/// setup went badly when it went exactly as they asked.
	var summary: String {
		switch (needsPassword, needsAccessibility) {
		case (true, true):
			return "Gaze recognises you, but it can't unlock yet — it still needs your login "
				+ "password and Accessibility access. Both are in Settings whenever you want them."
		case (true, false):
			return "Gaze recognises you, but it can't unlock yet — it still needs your login "
				+ "password. You can add it in Settings whenever you want."
		case (false, true):
			return "Gaze recognises you, but it can't type at the lock screen until you turn on "
				+ "Accessibility access. It's in Settings whenever you want it."
		case (false, false):
			return "Lock your screen and look at your Mac. Your password still works whenever you want it."
		}
	}
}

/// The last screen — which is not always a success, and not always a failure either.
///
/// Enrollment can end badly: the camera covered, the face never resolved, the
/// keychain refusing to save. A flow whose final screen is always a green tick
/// would claim success for those too, and the person would find out at the lock
/// screen. Same screen, both outcomes, and the failure says what actually went
/// wrong rather than "something went wrong".
///
/// There is a third outcome between them, and it used to be reported as the first:
/// the face saved, but the password or the Accessibility permission skipped. That
/// is a working enrolment attached to an app that cannot unlock anything, and
/// "You're all set" was a straightforwardly false thing to tell someone about it.
/// It gets the tick — nothing went wrong, they chose this — and a sentence naming
/// what is still outstanding.
///
/// No progress row. Like the welcome, this is an end rather than a step, and a
/// filled-to-the-last-dash indicator on a screen you have already arrived at is
/// telling you something you can see.
struct SetupDoneStep: View {

	/// Nil when enrollment succeeded.
	let failure: String?
	/// What is still missing. Ignored when `failure` is set: a flow that never got a
	/// face has bigger news than a missing password.
	var unfinished = SetupUnfinished()
	var onDone: () -> Void
	var onRetry: () -> Void

	@State private var trigger = 0

	private var didFail: Bool { failure != nil }
	private var isComplete: Bool { !didFail && unfinished.isComplete }

	private var title: String {
		if didFail { return "Setup didn't finish" }
		return isComplete ? "You're all set" : "Your face is saved"
	}

	var body: some View {
		SetupScaffold(
			title: title,
			message: failure ?? unfinished.summary,
			figureHeight: 180
		) {
			SetupMark(kind: didFail ? .failure : .success, diameter: 180, trigger: trigger)
		} actions: {
			SetupButton(title: didFail ? "Try Again" : "Done", action: didFail ? onRetry : onDone)
			if didFail {
				Button("Close", action: onDone)
					.buttonStyle(.plain)
					.font(Typography.setupBody)
					.foregroundStyle(Theme.setupTertiary)
			}
		}
		// Played once the view is actually on screen rather than on appear, so it
		// does not run underneath the step transition and finish before it is seen.
		// Later than the scaffold's own arrival, so the tick lands on a settled screen
		// instead of bouncing while the words are still moving.
		.task {
			try? await Task.sleep(for: .milliseconds(260))
			trigger += 1
		}
	}
}
