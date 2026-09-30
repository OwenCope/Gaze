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

/// The gliding light on the follow-the-light page: the lock-screen light at tour
/// scale, gliding out from the centre on the same clock the real challenge scores
/// against, alternating sides each pass while the face stays still. Under Reduce
/// Motion it holds still on one side.
private struct GazeTourFollowLight: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// The lock-screen target's 44 pt glow and 18 pt core, scaled ~0.6.
	private static let glowDiameter: CGFloat = 26
	private static let coreDiameter: CGFloat = 11
	private static let travel: CGFloat = 130

	var body: some View {
		TimelineView(.animation) { timeline in
			ZStack {
				Circle()
					.fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
						center: .center, startRadius: 0, endRadius: Self.glowDiameter / 2))
					.frame(width: Self.glowDiameter, height: Self.glowDiameter)
				Circle()
					.fill(.white)
					.frame(width: Self.coreDiameter, height: Self.coreDiameter)
			}
			.offset(x: reduceMotion ? Self.travel : Self.offset(at: timeline.date))
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	/// The lock screen's pass: rest, glide out, hold, glide back (as in
	/// LivenessChallenge.lookTargetPosition). Copied so setup builds without it.
	private static let period = 1.3
	private static func position(_ t: Double) -> Double {
		func ease(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * (3 - 2 * u) }
		switch t {
		case ..<0.1: return 0
		case ..<0.55: return ease((t - 0.1) / 0.45)
		case ..<0.75: return 1
		case ..<1.2: return 1 - ease((t - 0.75) / 0.45)
		default: return 0
		}
	}

	private static func offset(at date: Date) -> CGFloat {
		let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period * 2)
		let cycle = Int(elapsed / period)
		let position = Self.position(elapsed - Double(cycle) * period)
		let side: CGFloat = cycle % 2 == 0 ? -1 : 1
		return side * travel * CGFloat(position)
	}
}
