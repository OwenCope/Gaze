import Foundation

enum GazeCompanionMaterial: Equatable {
	case charcoal, pearl, ink
}

enum GazeCompanionPresentation: Equatable {
	case standard, notch

	func sampleTime(_ elapsed: Double, motion: GazeFaceMotion) -> Double {
		guard self == .notch else { return elapsed }
		if motion == .accepted { return elapsed * (1.4 / 0.44) }
		if motion == .rejected { return elapsed * (1.85 / 0.80) }
		return elapsed
	}

	func duration(for motion: GazeFaceMotion) -> Double? {
		if motion == .accepted { return self == .notch ? 0.44 : 1.4 }
		if motion == .rejected { return self == .notch ? 0.80 : 1.85 }
		return nil
	}

	func pose(for motion: GazeFaceMotion, at elapsed: Double, reducedMotion: Bool = false) -> GazeCompanionPose {
		var pose = GazeCompanionMotion.pose(for: motion, at: sampleTime(elapsed, motion: motion), reducedMotion: reducedMotion)
		if self == .notch, motion.isOneShot, !reducedMotion {
			pose.face.expression = (motion == .accepted ? 1 : -1) * GazeCompanionTiming.ease(max(0, elapsed) / 0.14)
		}
		return pose
	}
}

struct GazeCompanionPlayback {
	private(set) var motion: GazeFaceMotion
	private(set) var startedAt: Double
	let presentation: GazeCompanionPresentation
	private var origin: GazeCompanionPose?

	init(motion: GazeFaceMotion, at time: Double, presentation: GazeCompanionPresentation = .standard) {
		self.motion = motion
		startedAt = time
		self.presentation = presentation
	}

	func pose(at time: Double, reducedMotion: Bool = false) -> GazeCompanionPose {
		let elapsed = max(0, time - startedAt)
		let target = presentation.pose(for: motion, at: elapsed, reducedMotion: reducedMotion)
		let blendDuration = presentation == .notch && motion.isOneShot ? 0.12 : 0.24
		guard !reducedMotion, let origin, elapsed < blendDuration else { return target }
		return origin.blended(to: target, progress: GazeCompanionTiming.settle(elapsed / blendDuration))
	}

	mutating func retarget(to motion: GazeFaceMotion, at time: Double) {
		origin = pose(at: time)
		self.motion = motion
		startedAt = time
	}
}

struct GazeCompanionPose: Equatable {
	var face = GazeFacePose()
	var roll = 0.0
	var stretch = 0.0
	var lift = 0.0
	var drift = 0.0

	func blended(to target: Self, progress: Double) -> Self {
		Self(face: face.blended(to: target.face, progress: progress),
			roll: roll + (target.roll - roll) * progress,
			stretch: stretch + (target.stretch - stretch) * progress,
			lift: lift + (target.lift - lift) * progress,
			drift: drift + (target.drift - drift) * progress)
	}
}

enum GazeCompanionTiming {
	static func idleGlance(_ amount: Double) -> GazeCompanionPose {
		var pose = GazeCompanionPose()
		pose.face.turn = amount * 0.32
		pose.drift = amount * 0.12
		pose.lift = -0.06 * amount * amount
		return pose
	}

	static func ease(_ value: Double) -> Double { min(1, max(0, GazeFaceMotion.eased(value))) }
	static func settle(_ value: Double) -> Double { 1 - pow(1 - min(1, max(0, value)), 5) }
	static func pulse(_ time: Double, _ start: Double, _ peak: Double, _ hold: Double, _ end: Double) -> Double {
		ease((time - start) / (peak - start)) * (1 - ease((time - hold) / (end - hold)))
	}
	static func guidance(_ motion: GazeFaceMotion, at time: Double) -> GazeCompanionPose {
		let time = time.truncatingRemainder(dividingBy: 3.2)
		let movement = pulse(time, 0.28, 1.05, 1.65, 2.55)
		var pose = GazeCompanionPose()
		switch motion {
		case .turnLeft: pose.face.turn = -0.74 * movement
		case .turnRight: pose.face.turn = 0.74 * movement
		case .nod: pose.face.nod = 0.78 * pulse(time, 0.28, 0.82, 1.04, 1.90)
		case .blink: pose.face.eyesOpen = 1 - 0.96 * pulse(time, 0.70, 0.85, 1.05, 1.30)
		case .openMouth: pose.face.mouthOpen = movement
		default: break
		}
		return pose
	}
}

enum GazeCompanionMotion {
	static func pose(for motion: GazeFaceMotion, at elapsed: Double, reducedMotion: Bool = false) -> GazeCompanionPose {
		if motion == .returnToCenter { return GazeCompanionPose() }
		if reducedMotion { return GazeCompanionPose(face: motion.stillPose) }
		let time = max(0, elapsed)
		var pose = GazeCompanionPose()
		if motion.demonstratesAction {
			pose = GazeCompanionTiming.guidance(motion, at: time)
			let time = time.truncatingRemainder(dividingBy: 3.2)
			let direction = motion == .turnLeft ? -1.0 : (motion == .turnRight ? 1.0 : 0.0)
			pose.face.gaze = direction * 0.42 * GazeCompanionTiming.pulse(time, 0.03, 0.25, 0.55, 1.05)
			return pose
		}
		switch motion {
		case .accepted:
			pose.face.expression = GazeCompanionTiming.settle(time / 0.45)
			pose.face.nod = 0.46 * GazeCompanionTiming.pulse(time, 0.10, 0.48, 0.62, 1.18)
			pose.stretch = -0.065 * GazeCompanionTiming.pulse(time, 0, 0.26, 0.32, 0.64)
				+ 0.035 * GazeCompanionTiming.pulse(time, 0.42, 0.76, 0.84, 1.40)
			pose.lift = -0.025 * GazeCompanionTiming.pulse(time, 0.35, 0.72, 0.82, 1.40)
		case .rejected:
			pose.face.expression = -GazeCompanionTiming.settle(time / 0.45)
			pose.face.turn = 0.30 * sin(time * .pi * 2 / 0.90) * GazeCompanionTiming.pulse(time, 0.05, 0.28, 0.90, 1.65)
			pose.roll = -4 * sin(time * .pi * 2 / 0.90) * GazeCompanionTiming.pulse(time, 0.10, 0.35, 0.90, 1.80)
			pose.stretch = -0.065 * GazeCompanionTiming.pulse(time, 0.10, 0.44, 0.80, 1.85)
		default:
			let time = time.truncatingRemainder(dividingBy: 8)
			pose = GazeCompanionTiming.idleGlance(0.45 * GazeCompanionTiming.pulse(time, 0.6, 1.45, 2.1, 3.0)
				- 0.38 * GazeCompanionTiming.pulse(time, 4.25, 5.1, 5.8, 7.0))
		}
		return pose
	}
}
