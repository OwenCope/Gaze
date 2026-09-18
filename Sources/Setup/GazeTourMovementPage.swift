import SwiftUI

/// Live content for the movement guide; a nil lesson shows the resting companion.
struct GazeTourMovementPage: View {
	var lesson: GazeExpressionLesson? = nil
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		GazeLessonAnimation(motion: lesson?.motion ?? .resting, paused: false,
			material: colorScheme == .dark ? .ink : .charcoal)
			.frame(width: 240, height: 240)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
