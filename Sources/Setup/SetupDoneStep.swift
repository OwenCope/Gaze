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
			return "Your face and unlock settings are saved.\nYour password and Touch ID remain available as usual."
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
	var isAddingFace = false
	var onDone: () -> Void
	var onRetry: () -> Void
	/// Opens Gaze Settings so a partial setup can be finished there. Nil where there
	/// is nothing to open (previews, tests): the screen stays a single button.
	/// Ignored on failure and add-face runs, which keep their existing buttons.
	var onOpenSettings: (() -> Void)? = nil
	/// Opens the recognition check without locking the Mac. Only shown after a
	/// complete first-run setup; nil keeps existing callers and previews unchanged.
	var onTestRecognition: (() -> Void)? = nil

	@State private var trigger = 0

	private var didFail: Bool { failure != nil }

	/// Whether the Done screen offers the secondary route into Settings.
	///
	/// Only a partial first-run setup: the face saved but the password or
	/// Accessibility skipped. Complete, failed and add-face runs keep their
	/// existing buttons, and a nil opener means a single Done button.
	static func showsFinishInSettings(failed: Bool, unfinished: SetupUnfinished, isAddingFace: Bool, canOpenSettings: Bool) -> Bool {
		canOpenSettings && !failed && !isAddingFace && !unfinished.isComplete
	}

	private var showsSettingsAction: Bool {
		Self.showsFinishInSettings(failed: didFail, unfinished: unfinished, isAddingFace: isAddingFace, canOpenSettings: onOpenSettings != nil)
	}

	private var showsRecognitionAction: Bool {
		!didFail && unfinished.isComplete && !isAddingFace && onTestRecognition != nil
	}

	static func title(failed: Bool, unfinished: SetupUnfinished, isAddingFace: Bool) -> String {
		if failed { return "Setup didn’t finish" }
		if isAddingFace { return "Face added" }
		return unfinished.isComplete ? "Enjoy a little less typing." : "Your face is saved"
	}

	private var message: String {
		if let failure { return failure }
		if isAddingFace { return "Your new face is saved.\nYour unlock settings haven’t changed." }
		return unfinished.summary
	}

	var body: some View {
		SetupScaffold(
			title: Self.title(failed: didFail, unfinished: unfinished, isAddingFace: isAddingFace),
			message: message,
			figureHeight: 180
		) {
			SetupMark(kind: didFail ? .failure : .success, diameter: 180, trigger: trigger)
		} detail: {
			if showsRecognitionAction {
				Text("Test Recognition uses the camera without locking or unlocking this Mac.")
					.font(.caption)
					.foregroundStyle(Theme.setupSecondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: 400)
					.padding(.top, 12)
			}
		} actions: {
			SetupButton(title: didFail ? "Try Again" : "Done", action: didFail ? onRetry : onDone)
			if didFail {
				SetupSecondaryButton(title: "Close", action: onDone)
			} else if showsSettingsAction {
				SetupSecondaryButton(title: "Finish in Settings", action: { onOpenSettings?() })
			} else if showsRecognitionAction, let onTestRecognition {
				SetupSecondaryButton(title: "Test Recognition", action: onTestRecognition)
					.help("Uses the camera to check your face. It does not lock or unlock the Mac.")
			}
		}
		// Played once the view is actually on screen rather than on appear, so it
		// does not run underneath the step transition and finish before it is seen.
		// Later than the scaffold's own arrival, so the tick lands on a settled screen
		// instead of bouncing while the words are still moving.
		.task {
			do { try await Task.sleep(for: .milliseconds(260)) }
			catch { return }
			trigger += 1
		}
	}
}
