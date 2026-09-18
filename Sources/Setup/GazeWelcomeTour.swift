import SwiftUI

/// The opening screen of first-run setup: a three-page introduction.
///
/// This is TourKit's embedded `TourSlideshowView`, not a `TourKitWindowController`,
/// so Gaze keeps its existing window lifecycle — the flow owns the window, the
/// slideshow only owns its pages. It deliberately does nothing else: no cameras are
/// started, no permissions are requested, no passwords are stored, and nothing here
/// can enable unlocking. That all happens on the later steps.
///
/// The copy states what Gaze is not: a regular camera, not Apple Face ID's depth
/// sensing; automatic unlocking stays optional and password-backed.
struct GazeWelcomeTour: View {
	var onContinue: () -> Void
	var onClose: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let pages: [TourPage] = [
		TourPage(
			imageName: "Art/tour-recognition.png",
			imageBundle: .main,
			title: "Meet Gaze",
			description: "Use your Mac’s camera to recognize your face at the lock screen."
		),
		TourPage(
			imageName: "Art/tour-privacy.png",
			imageBundle: .main,
			title: "Recognition stays on your Mac",
			description: "Face templates are encrypted locally. Gaze uses a regular camera and does not provide Apple Face ID’s depth sensing."
		),
		TourPage(
			imageName: "Art/tour-practice.png",
			imageBundle: .main,
			title: "Choose how to unlock",
			description: "Practice the movement prompts next. Automatic unlocking is optional and uses a saved Mac password."
		),
	]

	var body: some View {
		ScrollView(.vertical, showsIndicators: false) {
			TourSlideshowView(
				pages: Self.pages,
				width: 660,
				continueButtonTitle: "Continue",
				finishButtonTitle: "Practice movements",
				onFinish: onContinue,
				onClose: onClose
			)
			// The slideshow cross-fades between slides; under Reduce Motion that
			// movement goes away rather than becoming a lesser movement.
			.transaction { transaction in
				if reduceMotion { transaction.disablesAnimations = true }
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 12)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		// Escape leaves the flow the same way Not Now did: close without setting up.
		.onExitCommand(perform: onClose)
	}
}
