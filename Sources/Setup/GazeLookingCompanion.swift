import SwiftUI

/// The companion for the tour demos: idles with its usual curiosity, and eases its whole
/// face toward `look` (-1 left, 1 right) and into a smile with `happy`.
///
/// The demos used to switch between whole movement lessons, and each switch cut to a new
/// clip after a quarter-second blend; a lesson "turn" also swings out and back instead of
/// looking. This eases continuously from wherever the face is, so it never snaps.
struct GazeLookingCompanion: View {
	var look: Double
	var happy: Bool
	@State private var start = Date.timeIntervalSinceReferenceDate
	@State private var from = Target(look: 0, smile: 0)
	@State private var to = Target(look: 0, smile: 0)
	@State private var changedAt = Date.timeIntervalSinceReferenceDate
	@State private var rendererFailed = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	struct Target: Equatable {
		var look: Double
		var smile: Double
	}

	private static let easeDuration = 0.7

	var body: some View {
		let sampler = makeSampler()
		Group {
			if rendererFailed {
				TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
					GazeFaceDrawing(pose: sampler(context.date.timeIntervalSinceReferenceDate).face,
						motion: .resting, material: .ink, bodyOpacity: 0.68)
				}
			} else {
				GazeCompanionRenderer(pose: sampler, running: !reduceMotion, material: .ink,
					opacity: 0.68, failure: { _ in rendererFailed = true })
			}
		}
		.accessibilityHidden(true)
		.onAppear { retarget() }
		.onChange(of: look) { _, _ in retarget() }
		.onChange(of: happy) { _, _ in retarget() }
	}

	private var target: Target { Target(look: look, smile: happy ? 1 : 0) }

	private func retarget() {
		let now = Date.timeIntervalSinceReferenceDate
		from = current(at: now)
		to = target
		changedAt = now
	}

	private func current(at time: TimeInterval) -> Target {
		let progress = Self.ease(min(1, max(0, (time - changedAt) / Self.easeDuration)))
		return Target(look: from.look + (to.look - from.look) * progress,
			smile: from.smile + (to.smile - from.smile) * progress)
	}

	private func makeSampler() -> (TimeInterval) -> GazeCompanionPose {
		let start = start, from = from, to = to, changedAt = changedAt, reduced = reduceMotion
		return { time in
			let progress = reduced ? 1 : Self.ease(min(1, max(0, (time - changedAt) / Self.easeDuration)))
			let look = from.look + (to.look - from.look) * progress
			let smile = from.smile + (to.smile - from.smile) * progress
			var pose = reduced ? GazeCompanionPose() : GazeCuriosityMotion.pose(at: time - start)
			pose.face.turn = pose.face.turn * 0.25 + look * 0.6
			pose.face.gaze = look * 0.25
			pose.face.expression = max(pose.face.expression, smile)
			pose.drift += look * 0.03
			return pose
		}
	}

	/// Ease in and out, so the face starts and stops moving gently.
	private static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}
