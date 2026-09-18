import SwiftUI

/// Live content for the movement guide; a nil lesson shows the resting companion.
struct GazeTourMovementPage: View {
	var lesson: GazeExpressionLesson? = nil

	@State private var paused = false
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion

	private var reduced: Bool { reduceMotion || previewReduceMotion }

	var body: some View {
		VStack(spacing: 12) {
			GazeLessonAnimation(motion: lesson?.motion ?? .resting, paused: paused,
				material: colorScheme == .dark ? .ink : .charcoal)
				.frame(width: 240, height: 240)
			Button { paused.toggle() } label: {
				Label(paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
					.frame(minWidth: 64)
					.foregroundStyle(.primary)
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.disabled(reduced)
			.help(paused ? "Resume this animation" : "Pause this animation")
			Text(reduced ? "Reduce Motion is on. Camera off." : "Camera off")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onChange(of: lesson) { _, _ in paused = false }
	}
}
