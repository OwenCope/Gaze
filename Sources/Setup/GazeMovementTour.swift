import SwiftUI

/// The movement guide: a six-page camera-free introduction to the unlock prompts.
///
/// This is the embedded slideshow view, not a window controller — the `movement-guide`
/// window owns presentation, the slideshow only owns its pages. It deliberately does
/// nothing else: no camera is started, no permission is requested, nothing is enrolled,
/// and nothing here can unlock anything. It is a preview of the prompts, not a check.
///
/// The six pages, in order: an introduction stating how many movements unlocking asks
/// for, then the five movement prompts — turn left, turn right, nod, blink, open mouth —
/// reusing `GazeExpressionLesson` titles and explanations so the directions stay correct.
struct GazeMovementTour: View {
	var onClose: () -> Void
	var movementCount: Int = 2
	var initialPageIndex: Int = 0

	var body: some View {
		TourSlideshowView(
			pages: Self.pages(movementCount: movementCount),
			width: GazeTourSizing.panelWidth,
			initialPageIndex: initialPageIndex,
			continueButtonTitle: "Next",
			finishButtonTitle: "Done",
			onFinish: onClose,
			onClose: onClose,
			pageMedia: { index in
				AnyView(GazeTourMovementPage(lesson: index == 0 ? nil : Self.lessons[index - 1]))
			}
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}

	private static let lessons: [GazeExpressionLesson] = [.turnLeft, .turnRight, .nod, .blink, .openMouth]

	private static func pages(movementCount: Int) -> [TourPage] {
		var pages = [
			TourPage(
				imageName: "Art/onboarding-recognition.png",
				imageBundle: .main,
				title: "Practice the movements",
				description: LocalizedStringKey(
					stringLiteral: "Gaze asks for \(movementCount == 1 ? "one small movement" : "two small movements") before unlocking. Try each one here. This guide keeps the camera off."
				)
			)
		]
		let movements: [(GazeExpressionLesson, String)] = [
			(.turnLeft, "Art/movement-left.png"),
			(.turnRight, "Art/movement-right.png"),
			(.nod, "Art/movement-nod.png"),
			(.blink, "Art/movement-blink.png"),
			(.openMouth, "Art/movement-mouth.png"),
		]
		pages += movements.map { lesson, imageName in
			TourPage(
				imageName: imageName,
				imageBundle: .main,
				title: LocalizedStringKey(stringLiteral: lesson.title),
				description: LocalizedStringKey(stringLiteral: lesson.explanation(movementCount: movementCount))
			)
		}
		return pages
	}
}
