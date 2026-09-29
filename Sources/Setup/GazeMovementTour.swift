import SwiftUI

/// The movement guide: a seven-page camera-free introduction to the unlock prompts.
///
/// This is the embedded slideshow view, not a window controller — the `movement-guide`
/// window owns presentation, the slideshow only owns its pages. It deliberately does
/// nothing else: no camera is started, no permission is requested, nothing is enrolled,
/// and nothing here can unlock anything. It is a preview of the prompts, not a check.
///
/// The seven pages, in order: an introduction stating how many movements unlocking asks
/// for, then the six movement prompts — turn left, turn right, nod, blink, open mouth,
/// follow the light —
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
				let lesson: GazeExpressionLesson? = index == 0 ? nil : Self.lessons[index - 1]
				if lesson == .followLight {
					return AnyView(ZStack {
						GazeTourMovementPage(lesson: lesson)
						GazeTourFollowLight()
					})
				}
				return AnyView(GazeTourMovementPage(lesson: lesson))
			}
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}

	/// Pro Black behind the animated face on every page. The face is drawn live by
	/// `GazeTourMovementPage`, so the page image is only ever the backdrop.
	private static let backdrop = "Art/tour-backdrop.png"

	private static let lessons: [GazeExpressionLesson] = [.turnLeft, .turnRight, .nod, .blink, .openMouth, .followLight]

	private static func pages(movementCount: Int) -> [TourPage] {
		var pages = [
			TourPage(
				imageName: Self.backdrop,
				imageBundle: .main,
				title: "Practice the movements",
				description: LocalizedStringKey(
					stringLiteral: movementCount == 0
						? "Movements are off, so Gaze unlocks without one. Try them here in case you turn them on. This guide keeps the camera off."
						: "Gaze asks for \(movementCount == 1 ? "one small movement" : "two small movements") before unlocking. Try each one here. This guide keeps the camera off."
				)
			)
		]
		pages += lessons.map { lesson in
			TourPage(
				imageName: Self.backdrop,
				imageBundle: .main,
				title: LocalizedStringKey(stringLiteral: lesson.title),
				description: LocalizedStringKey(stringLiteral: lesson.explanation(movementCount: movementCount))
			)
		}
		return pages
	}
}

/// The gliding light on the follow-the-light page: a small glowing dot that moves out
/// from the centre, left then right, while the face stays still. Under Reduce Motion it
/// holds still on one side.
private struct GazeTourFollowLight: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// Each leg of the trip takes about 1.2 s; the full loop is centre-left-centre-right.
	private static let leg: TimeInterval = 1.2
	private static let travel: CGFloat = 130

	var body: some View {
		TimelineView(.animation) { timeline in
			ZStack {
				Circle()
					.fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.18), .clear],
						center: .center, startRadius: 2, endRadius: 18))
					.frame(width: 36, height: 36)
				Circle()
					.fill(.white)
					.frame(width: 12, height: 12)
			}
			.offset(x: reduceMotion ? Self.travel : Self.offset(at: timeline.date))
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	private static func offset(at date: Date) -> CGFloat {
		let position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: leg * 4) / leg
		let index = Int(position)
		let eased = 0.5 - 0.5 * cos(.pi * (position - CGFloat(index)))
		switch index {
		case 0: return -travel * eased
		case 1: return -travel * (1 - eased)
		case 2: return travel * eased
		default: return travel * (1 - eased)
		}
	}
}
