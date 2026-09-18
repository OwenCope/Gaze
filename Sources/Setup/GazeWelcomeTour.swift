import SwiftUI

/// The opening screen of first-run setup: a nine-page introduction.
///
/// This is TourKit's embedded `TourSlideshowView`, not a `TourKitWindowController`,
/// so Gaze keeps its existing window lifecycle — the flow owns the window, the
/// slideshow only owns its pages. It deliberately does nothing else: no cameras are
/// started, no permissions are requested, no passwords are stored, and nothing here
/// can enable unlocking. That all happens on the later steps.
///
/// The movement demonstrations live inside this tour rather than as a second
/// onboarding: pages three through eight show each `GazeExpressionLesson`'s existing
/// title and explanation in the tour's bottom panel, with `GazeTourMovementPage`
/// rendering just the animation in the artwork region. There is no duplicate
/// heading or description inside the media, no waiting/result page, and no lesson
/// selector — the tour's own navigation and progress are the only way through.
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

	/// The movement demonstrations shown inside the tour, in page order.
	private static let movementLessons: [GazeExpressionLesson] = [
		.scanning, .turnLeft, .turnRight, .nod, .blink, .openMouth,
	]

	private func makePages() -> [TourPage] {
		var pages: [TourPage] = [
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
		]
		for lesson in Self.movementLessons {
			pages.append(TourPage(
				imageName: "",
				title: "\(lesson.title)",
				description: "\(lesson.explanation(movementCount: movementCount))"
			))
		}
		pages.append(TourPage(
			imageName: "Art/tour-practice.png",
			imageBundle: .main,
			title: "Choose how to unlock",
			description: "Automatic unlocking stays off unless you turn it on. It uses a saved Mac password. Next, set up any parts you still need."
		))
		return pages
	}

	var body: some View {
		GeometryReader { proxy in
			TourSlideshowView(
				pages: makePages(),
				width: max(proxy.size.width, 1),
				initialPageIndex: initialPageIndex,
				continueButtonTitle: "Continue",
				finishButtonTitle: "Continue setup",
				onFinish: onContinue,
				onClose: onClose,
				presentation: .windowContent,
				contentHeight: max(proxy.size.height, 1),
				pageMedia: { index in
					if index == 8 {
						return AnyView(Image(systemName: "key.fill")
							.font(.system(size: 72, weight: .regular))
							.foregroundStyle(.white.opacity(0.85))
							.accessibilityHidden(true))
					}
					let lessonIndex = index - 2
					guard lessonIndex >= 0 && lessonIndex < Self.movementLessons.count else { return nil }
					return AnyView(GazeTourMovementPage(lesson: Self.movementLessons[lessonIndex]))
				},
				onPageChange: onPageChange
			)
			// The slideshow cross-fades between slides; under Reduce Motion that
			// movement goes away rather than becoming a lesser movement.
			.transaction { transaction in
				if reduceMotion { transaction.disablesAnimations = true }
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		// Escape leaves the flow the same way Not Now did: close without setting up.
		.onExitCommand(perform: onClose)
	}
}
