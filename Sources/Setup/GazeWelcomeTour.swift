import AppKit
import SwiftUI

/// The opening screen of first-run setup: a four-page introduction.
///
/// This is the embedded slideshow view, not a window controller,
/// so Gaze keeps its existing window lifecycle — the flow owns the window, the
/// slideshow only owns its pages. It deliberately does nothing else: no cameras are
/// started, no permissions are requested, no passwords are stored, and nothing here
/// can enable unlocking. That all happens on the later steps.
///
/// The four steps, in order: hook (with the on-device statement), face data never
/// leaving this Mac, how unlock works, and a get-started page stating automatic
/// unlocking stays off unless turned on. Detailed movement guidance lives in a
/// separate TourKit guide.
///
/// The copy states what Gaze is not: a regular camera, not Apple Face ID's depth
/// sensing; automatic unlocking stays optional and password-backed.
struct GazeWelcomeTour: View {
	var onContinue: () -> Void
	var onClose: () -> Void
	var initialPageIndex: Int = 0

	private static let pages: [TourPage] = [
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "Meet Gaze",
			description: "Use your Mac’s camera to recognize your face at the lock screen. Face data never leaves this Mac."
		),
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "Stays on your Mac",
			description: "Face templates stay encrypted on this Mac. It uses a regular camera, not depth sensing."
		),
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "How unlock works",
			description: "Look at the camera and follow the movements. Gaze enters your saved login password after checking."
		),
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: "Unlocking stays your choice",
			description: "It uses your saved Mac password. Automatic unlocking stays off unless you turn it on."
		),
	]

	var body: some View {
		TourSlideshowView(
			pages: Self.pages,
			width: GazeTourSizing.panelWidth,
			initialPageIndex: initialPageIndex,
			continueButtonTitle: "Next",
			finishButtonTitle: "Start setup",
			onFinish: onContinue,
			onClose: onClose,
			// Every page plays live on Pro Black: the companion, privacy, unlock and choice.
			pageMedia: { index in
				switch index {
				case 0: AnyView(GazeTourMovementPage())
				case 1: AnyView(GazeTourPrivacyDemo())
				case 2: AnyView(GazeTourUnlockDemo())
				case 3: AnyView(GazeTourChoiceDemo())
				default: nil
				}
			}
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}
}
