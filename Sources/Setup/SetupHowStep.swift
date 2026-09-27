import SwiftUI

/// What Gaze actually does, before it asks for anything.
///
/// A single tour scene: the notch panel plays look, move, unlocked on a loop,
/// with one line underneath saying the password and Touch ID still work.
struct SetupHowStep: View {
	var position: SetupPosition?
	var onContinue: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)? = nil
	var movementCount = 2

	private var message: String {
		if movementCount == 0 {
			return "Look at your Mac and it unlocks. Your password and Touch ID still work."
		}
		let moves = movementCount == 2 ? "two small moves" : "one small move"
		return "Look at your Mac, make \(moves), and it unlocks. Your password and Touch ID still work."
	}

	private var page: TourPage {
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "How Gaze unlocks your Mac",
			description: LocalizedStringKey(message)
		)
	}

	var body: some View {
		TourSlideshowView(
			pages: [page],
			width: GazeTourSizing.panelWidth,
			continueButtonTitle: "Continue",
			finishButtonTitle: "Continue",
			onFinish: onContinue,
			onClose: onClose,
			pageMedia: { _ in AnyView(GazeTourUnlockDemo()) },
			footer: position.map { AnyView(SetupProgress(position: $0)) },
			onBack: onBack
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}
}
