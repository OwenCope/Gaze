import SwiftUI

struct GazePeekSample {
	let reveal: Double
	let pose: GazeCompanionPose

	static func at(_ elapsed: Double) -> Self {
		let time = max(0, elapsed)
		return Self(reveal: 1, pose: GazeCuriosityMotion.pose(at: time))
	}
}

struct GazePeekingCompanion: View {
	var isActive = true
	var diameter: CGFloat = 94
	@State private var start = Date.timeIntervalSinceReferenceDate
	@State private var visible = false
	@State private var rendererFailed = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.colorScheme) private var colorScheme
	private var playing: Bool { isActive && visible && !reduceMotion && !previewReduceMotion && scenePhase == .active }

	var body: some View {
		GeometryReader { geometry in
				let startedAt = start
				let isPlaying = playing
				let sample: (TimeInterval) -> GazeCompanionPose = { time in
					isPlaying ? GazeCuriosityMotion.pose(at: time - startedAt) : GazeCompanionPose()
				}
				let material: GazeCompanionMaterial = colorScheme == .dark ? .ink : .charcoal
				Group {
					if rendererFailed {
						GazeFaceDrawing(pose: GazeFacePose(), motion: .resting, material: material)
					} else {
						GazeCompanionRenderer(pose: sample, running: playing, material: material,
							opacity: reduceTransparency ? 1 : 0.68, failure: { _ in rendererFailed = true })
					}
				}
				.frame(width: diameter, height: diameter)
				.position(x: diameter * 0.70,
					y: geometry.size.height - diameter * 0.9)
				.opacity(isActive ? 1 : 0)
				.animation(reduceMotion || previewReduceMotion ? nil : .easeOut(duration: 0.18), value: isActive)
		}
		.clipped()
		.allowsHitTesting(false)
		.accessibilityHidden(true)
		.onAppear { visible = true }
		.onDisappear { visible = false }
		.onChange(of: playing) { _, isPlaying in
			if isPlaying { start = Date.timeIntervalSinceReferenceDate }
		}
	}
}
