import SwiftUI

struct GazeLessonPlayback {
	private(set) var motion: GazeFaceMotion
	private var startedAt: TimeInterval
	private var pausedAt: TimeInterval?
	private var origin: GazeCompanionPose?

	init(motion: GazeFaceMotion, at time: TimeInterval) {
		self.motion = motion
		startedAt = time
	}

	func pose(at time: TimeInterval) -> GazeCompanionPose {
		let elapsed = max(0, (pausedAt ?? time) - startedAt)
		let duration = GazeCompanionPresentation.standard.duration(for: motion)
		let cycle = duration.map { $0 + 1.0 }
		let progress = cycle.map { elapsed.truncatingRemainder(dividingBy: $0) } ?? elapsed
		let pose = motion == .resting ? GazeCuriosityMotion.pose(at: progress)
			: GazeCompanionPresentation.standard.pose(for: motion, at: progress)
		if let origin, elapsed < 0.24 {
			return origin.blended(to: pose, progress: GazeCompanionTiming.settle(elapsed / 0.24))
		}
		if let cycle, elapsed >= cycle, progress < 0.24 {
			return GazeCompanionPose(face: motion.stillPose).blended(to: pose,
				progress: GazeCompanionTiming.settle(progress / 0.24))
		}
		return pose
	}

	mutating func select(_ motion: GazeFaceMotion, at time: TimeInterval) {
		origin = pose(at: time)
		self.motion = motion
		startedAt = time
		pausedAt = nil
	}

	mutating func setPaused(_ paused: Bool, at time: TimeInterval) {
		if paused {
			if pausedAt == nil { pausedAt = time }
		} else if let pausedAt {
			startedAt += max(0, time - pausedAt)
			self.pausedAt = nil
		}
	}
}

struct GazeLessonAnimation: View {
	let motion: GazeFaceMotion
	var paused: Bool
	var material: GazeCompanionMaterial
	@State private var playback: GazeLessonPlayback
	@State private var visible = false
	@State private var rendererFailed = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	@Environment(\.scenePhase) private var scenePhase

	init(motion: GazeFaceMotion, paused: Bool, material: GazeCompanionMaterial) {
		self.motion = motion
		self.paused = paused
		self.material = material
		_playback = State(initialValue: GazeLessonPlayback(motion: motion, at: Date.timeIntervalSinceReferenceDate))
	}

	private var reduced: Bool { reduceMotion || previewReduceMotion }
	// A visible NSHostingView can report .inactive; only a background scene is hidden.
	private var running: Bool { visible && !paused && !reduced && scenePhase != .background }
	private var sampler: (TimeInterval) -> GazeCompanionPose {
		let playback = playback
		let reduced = reduced
		let motion = motion
		return { time in reduced ? GazeCompanionPose(face: motion.stillPose) : playback.pose(at: time) }
	}

	var body: some View {
		let sample = sampler
		Group {
			if rendererFailed {
				TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { context in
					let pose = sample(context.date.timeIntervalSinceReferenceDate)
					GeometryReader { geometry in
						let side = min(geometry.size.width, geometry.size.height)
						GazeFaceDrawing(pose: pose.face, motion: motion, material: material,
							bodyOpacity: reduceTransparency ? 1 : 0.68)
							.scaleEffect(x: 1 - pose.stretch * 0.5, y: 1 + pose.stretch)
							.rotationEffect(.degrees(pose.roll))
							.offset(x: pose.drift * side, y: pose.lift * side)
					}
				}
			} else {
				GazeCompanionRenderer(pose: sample, running: running, material: material,
					opacity: reduceTransparency ? 1 : 0.68, failure: { _ in rendererFailed = true })
			}
		}
		.accessibilityHidden(true)
		.onAppear {
			playback = GazeLessonPlayback(motion: motion, at: Date.timeIntervalSinceReferenceDate)
			visible = true
			playback.setPaused(!running, at: Date.timeIntervalSinceReferenceDate)
		}
		.onDisappear {
			visible = false
			playback.setPaused(true, at: Date.timeIntervalSinceReferenceDate)
		}
		.onChange(of: motion) { _, motion in
			playback.select(motion, at: Date.timeIntervalSinceReferenceDate)
			playback.setPaused(!running, at: Date.timeIntervalSinceReferenceDate)
		}
		.onChange(of: running) { _, isRunning in
			playback.setPaused(!isRunning, at: Date.timeIntervalSinceReferenceDate)
		}
	}
}
