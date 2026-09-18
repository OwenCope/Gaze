import Foundation

enum GazeCuriosityMotion {
	static let duration = 13.2

	static func pose(at elapsed: Double) -> GazeCompanionPose {
		let time = max(0, elapsed).truncatingRemainder(dividingBy: duration)
		let notice = GazeCompanionTiming.pulse(time, 1.0, 1.5, 3.9, 4.7)
		let inspect = GazeCompanionTiming.pulse(time, 1.7, 2.7, 4.6, 5.9)
		let approach = GazeCompanionTiming.pulse(time, 2.1, 3.0, 4.9, 6.4)
		let secondLook = GazeCompanionTiming.pulse(time, 9.3, 9.9, 10.8, 11.5)
		let secondLean = GazeCompanionTiming.pulse(time, 9.9, 10.8, 11.3, 12.7)
		let settle = GazeCompanionTiming.pulse(time, 2.0, 2.3, 2.4, 2.9)
			- 0.5 * GazeCompanionTiming.pulse(time, 2.8, 3.1, 3.2, 3.7)
		return GazeCompanionPose(
			face: GazeFacePose(turn: 0.22 * inspect - 0.12 * secondLean,
				gaze: 0.24 * notice - 0.15 * secondLook),
			roll: -2.8 * inspect + 1.5 * secondLean,
			stretch: -0.035 * settle,
			lift: -0.014 * GazeCompanionTiming.pulse(time, 2.3, 2.9, 3.1, 3.7),
			drift: 0.065 * approach - 0.02 * secondLean)
	}
}
