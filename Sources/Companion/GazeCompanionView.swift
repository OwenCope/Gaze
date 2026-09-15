import SwiftUI

struct GazeCompanionView: View {
	let motion: GazeFaceMotion
	var active = true
	var runsWhileInactive = false
	var presentation = GazeCompanionPresentation.standard
	var material = GazeCompanionMaterial.charcoal
	var trigger = 0
	@Environment(\.accessibilityReduceMotion) private var systemReduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	@Environment(\.scenePhase) private var scenePhase
	@State private var playback: GazeCompanionPlayback?
	@State private var renderError: String?
	@State private var visible = false
	@State private var settled = false
	private var reducedMotion: Bool { systemReduceMotion || previewReduceMotion }
	private var resolvedOpacity: Float { reduceTransparency ? 1 : 0.68 }
	private var canAnimate: Bool { active && visible && !reducedMotion && (runsWhileInactive || scenePhase == .active) }

	private struct PlaybackKey: Equatable {
		let motion: GazeFaceMotion
		let trigger: Int
		let presentation: GazeCompanionPresentation
	}

	private struct SettlementKey: Equatable {
		let startedAt: Double?
		let active: Bool
	}

	var body: some View {
		let sample = poseSampler
		Group {
			if renderError != nil {
				TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !canAnimate || settled)) { context in
					let pose = sample(context.date.timeIntervalSinceReferenceDate)
					GeometryReader { geometry in
						let side = min(geometry.size.width, geometry.size.height)
						GazeFaceDrawing(pose: pose.face, motion: motion, material: material, bodyOpacity: Double(resolvedOpacity))
							.scaleEffect(x: 1 - pose.stretch * 0.5, y: 1 + pose.stretch)
							.rotationEffect(.degrees(pose.roll))
							.offset(x: pose.drift * side, y: pose.lift * side)
					}
				}
			} else {
				GazeCompanionRenderer(pose: sample, running: canAnimate && !settled,
					material: material, opacity: resolvedOpacity,
					diagnosticContext: "\(presentation == .notch ? "notch" : "standard").\(motion)",
					failure: { renderError = $0 })
			}
		}
		.accessibilityHidden(true)
		.onAppear { visible = true }
		.onDisappear { visible = false }
		.task(id: PlaybackKey(motion: motion, trigger: trigger, presentation: presentation)) {
			let time = Date.timeIntervalSinceReferenceDate
			if playback == nil || playback?.presentation != presentation {
				playback = GazeCompanionPlayback(motion: motion, at: time, presentation: presentation)
			} else {
				playback?.retarget(to: motion, at: time)
			}
			settled = false
		}
		.task(id: SettlementKey(startedAt: playback?.startedAt, active: canAnimate)) {
			guard canAnimate, let playback, let duration = playback.presentation.duration(for: playback.motion) else { return }
			let remaining = max(0, duration - (Date.timeIntervalSinceReferenceDate - playback.startedAt) + 0.04)
			do { try await Task.sleep(for: .seconds(remaining)) }
			catch { return }
			settled = true
		}
	}

	private var poseSampler: (TimeInterval) -> GazeCompanionPose {
		let playback = playback
		let still = !canAnimate || settled
		let motion = motion
		let presentation = presentation
		return { time in
			if still { return GazeCompanionPose(face: motion.stillPose) }
			guard let playback else { return presentation.pose(for: motion, at: 0) }
			return playback.pose(at: time)
		}
	}
}
