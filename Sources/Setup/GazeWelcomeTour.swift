import AppKit
import SwiftUI

/// The opening screen of first-run setup: a five-page introduction.
///
/// This is TourKit's embedded `TourSlideshowView`, not a `TourKitWindowController`,
/// so Gaze keeps its existing window lifecycle — the flow owns the window, the
/// slideshow only owns its pages. It deliberately does nothing else: no cameras are
/// started, no permissions are requested, no passwords are stored, and nothing here
/// can enable unlocking. That all happens on the later steps.
///
/// The five steps, in order: hook (with the on-device statement), face data never
/// leaving this Mac, how unlock works, a single expressions guide, and a get-started
/// page stating automatic unlocking stays off unless turned on.
///
/// The copy states what Gaze is not: a regular camera, not Apple Face ID's depth
/// sensing; automatic unlocking stays optional and password-backed.
struct GazeWelcomeTour: View {
	var onContinue: () -> Void
	var onClose: () -> Void
	var movementCount: Int = 2
	var initialPageIndex: Int = 0
	var onPageChange: ((Int) -> Void)? = nil

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let pages: [TourPage] = [
		TourPage(
			imageName: "Art/tour-recognition.png",
			imageBundle: .main,
			title: "Meet Gaze",
			description: "Use your Mac’s camera to recognize your face at the lock screen. Face data never leaves this Mac."
		),
		TourPage(
			imageName: "Art/tour-privacy.png",
			imageBundle: .main,
			title: "Stays on your Mac",
			description: "Face templates stay encrypted on this Mac. It uses a regular camera, not depth sensing."
		),
		TourPage(
			imageName: "Art/how-unlock.png",
			imageBundle: .main,
			title: "How unlock works",
			description: "Look at the camera and follow the movements. Gaze enters your saved login password after checking."
		),
		TourPage(
			imageName: "Art/tour-practice.png",
			imageBundle: .main,
			title: "A quick movement check",
			description: "Gaze asks for a short turn, nod, or blink. Follow along, then face the camera again."
		),
		TourPage(
			imageName: "Art/how-keychain.png",
			imageBundle: .main,
			title: "Unlocking stays your choice",
			description: "It uses your saved Mac password. Automatic unlocking stays off unless you turn it on."
		),
	]

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .topTrailing) {
				TourSlideshowView(
					pages: Self.pages,
					width: max(proxy.size.width, 1),
					initialPageIndex: initialPageIndex,
					continueButtonTitle: "Next",
					finishButtonTitle: "Start setup",
					onFinish: onContinue,
					onClose: onClose,
					presentation: .windowContent,
					contentHeight: max(proxy.size.height, 1),
					onPageChange: onPageChange
				)
				// The slideshow cross-fades between slides; under Reduce Motion that
				// movement goes away rather than becoming a lesser movement.
				.transaction { transaction in
					if reduceMotion { transaction.disablesAnimations = true }
				}
				Button("Skip", action: onClose)
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 14)
					.padding(.top, 12)
					.help("Skip the introduction")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		// Escape leaves the flow the same way Not Now did: close without setting up.
		.onExitCommand(perform: onClose)
	}
}
