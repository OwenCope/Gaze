import SwiftUI

/// One movement demonstration inside the welcome tour's artwork region.
///
/// The lesson's title and explanation live in the tour's bottom panel (the
/// `TourPage`), so this shows only the animation, a pause control, and a
/// camera-off caption — no duplicate heading or description. It stays inside the
/// media region with room for the tour's own controls and page indicator, and it
/// adds no border, card, title, Previous/Next, menu, progress, camera,
/// permissions, persistence, or authentication. Playback reuses
/// `GazeLessonAnimation`'s lifecycle, which already stills the motion under
/// Reduce Motion.
struct GazeTourMovementPage: View {
	let lesson: GazeExpressionLesson

	@State private var paused = false
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion

	private var reduced: Bool { reduceMotion || previewReduceMotion }

	var body: some View {
		VStack(spacing: 12) {
			GazeLessonAnimation(motion: lesson.motion, paused: paused,
				material: colorScheme == .dark ? .ink : .charcoal)
				.frame(width: 240, height: 240)
			Button { paused.toggle() } label: {
				Label(paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
					.frame(minWidth: 64)
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.disabled(reduced)
			.help(paused ? "Resume this animation" : "Pause this animation")
			Text(reduced ? "Reduce Motion is on · Camera off" : "Just a demonstration · Camera off")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onChange(of: lesson) { _, _ in paused = false }
	}
}
