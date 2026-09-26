import SwiftUI

/// Live content for the movement guide; a nil lesson shows the resting companion.
struct GazeTourMovementPage: View {
	var lesson: GazeExpressionLesson? = nil
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		GazeLessonAnimation(motion: lesson?.motion ?? .resting, paused: false,
			material: colorScheme == .dark ? .ink : .charcoal)
			.frame(width: 240, height: 240)
			// The face's body is translucent, so the Pro Black backdrop's curves showed
			// through it. A soft dark halo keeps it reading as one solid object; a gradient,
			// because a blur re-rasterises on every animated frame.
			.background {
				RadialGradient(colors: [.black.opacity(0.7), .clear], center: .center, startRadius: 60, endRadius: 170)
					.frame(width: 340, height: 340)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
