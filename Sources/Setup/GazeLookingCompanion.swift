import SwiftUI

struct GazeLookingCompanion: View {
	let look: Double
	let happy: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

	var body: some View {
		let direction = look.isFinite ? min(1, max(-1, look)) : 0
		GazeFaceDrawing(
			pose: GazeFacePose(turn: direction * 0.18, gaze: direction, expression: happy ? 1 : 0),
			motion: happy ? .accepted : .resting,
			bodyOpacity: reduceTransparency ? 1 : 0.68)
			.animation(reduceMotion || previewReduceMotion ? nil : .easeInOut(duration: 0.3), value: look)
			.animation(reduceMotion || previewReduceMotion ? nil : .easeInOut(duration: 0.3), value: happy)
			.accessibilityHidden(true)
	}
}
