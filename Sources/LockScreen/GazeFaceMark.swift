import SwiftUI

private struct NotchReduceMotionKey: EnvironmentKey {
	static let defaultValue = false
}

extension EnvironmentValues {
	var notchReduceMotion: Bool {
		get { self[NotchReduceMotionKey.self] }
		set { self[NotchReduceMotionKey.self] = newValue }
	}
}

enum GazeFaceMotion: Equatable {
	case resting, scanning, turnLeft, turnRight, nod, blink, openMouth, returnToCenter, accepted, rejected

	init(phase: NotchCapsuleModel.Phase) {
		switch phase {
		case .locked, .unlocked, .pending: self = .resting
		case .scanning: self = .scanning
		case .success: self = .accepted
		case .notRecognised, .spoofRejected: self = .rejected
		case .challenge(_, let symbol, let horizontal, let vertical, _, _):
			if horizontal < 0 { self = .turnLeft }
			else if horizontal > 0 { self = .turnRight }
			else if vertical > 0 { self = .nod }
			else if symbol == "eye.fill" { self = .blink }
			else if symbol == "mouth.fill" { self = .openMouth }
			else if symbol == "viewfinder" { self = .returnToCenter }
			else { self = .resting }
		}
	}

	var isOneShot: Bool { self == .accepted || self == .rejected }

	var stillPose: GazeFacePose {
		var pose = GazeFacePose()
		pose.expression = self == .accepted ? 1 : (self == .rejected ? -1 : 0)
		return pose
	}

	var demonstratesAction: Bool {
		switch self {
		case .turnLeft, .turnRight, .nod, .blink, .openMouth: true
		default: false
		}
	}

	func pose(at elapsed: TimeInterval) -> GazeFacePose {
		GazeCompanionPresentation.notch.pose(for: self, at: elapsed).face
	}

	static func eased(_ value: Double) -> Double {
		let fraction = min(1, max(0, value))
		return fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10)
	}

}

struct GazeFacePose: Equatable {
	var turn = 0.0
	var nod = 0.0
	var eyesOpen = 1.0
	var mouthOpen = 0.0
	var breath = 0.0
	var gaze = 0.0
	var expression = 0.0

	func blended(to target: Self, progress: Double) -> Self {
		func blend(_ start: Double, _ end: Double) -> Double { start + (end - start) * progress }
		return Self(turn: blend(turn, target.turn), nod: blend(nod, target.nod),
			eyesOpen: blend(eyesOpen, target.eyesOpen), mouthOpen: blend(mouthOpen, target.mouthOpen),
			breath: blend(breath, target.breath), gaze: blend(gaze, target.gaze), expression: blend(expression, target.expression))
	}
}

struct GazeFacePlayback {
	private(set) var motion: GazeFaceMotion
	private var startedAt: TimeInterval
	private var origin: GazeFacePose?

	init(motion: GazeFaceMotion, at time: TimeInterval) {
		self.motion = motion
		startedAt = time
	}

	func pose(at time: TimeInterval) -> GazeFacePose {
		let elapsed = max(0, time - startedAt)
		let target = motion.pose(at: elapsed)
		guard let origin, elapsed < 0.14 else { return target }
		return origin.blended(to: target, progress: GazeFaceMotion.eased(elapsed / 0.14))
	}

	mutating func retarget(to motion: GazeFaceMotion, at time: TimeInterval) {
		origin = pose(at: time)
		self.motion = motion
		startedAt = time
	}
}

struct GazeFaceMark: View {
	let phase: NotchCapsuleModel.Phase
	var active = true

	var body: some View {
		GazeCompanionView(motion: GazeFaceMotion(phase: phase), active: active,
			runsWhileInactive: true, presentation: .notch)
		.scaleEffect(1.18)
		.accessibilityElement(children: .ignore)
		.accessibilityHidden(false)
		.accessibilityLabel(accessibilityLabel)
	}

	/// The VoiceOver label for the mark. Challenge prompts already carry the movement
	/// progress suffix ("· 1 of 2"), so the count is announced with the instruction.
	var accessibilityLabel: String {
		switch phase {
		case .challenge(let prompt, _, _, _, _, _): prompt
		case .scanning: "Looking for your face"
		case .pending: "Waiting for macOS"
		case .success: "Face verified"
		case .notRecognised: "Face not recognised"
		case .spoofRejected: "Verification failed"
		case .locked: "Locked"
		case .unlocked: "Unlocked"
		}
	}
}

struct GazeFaceDrawing: View {
	let pose: GazeFacePose
	let motion: GazeFaceMotion
	var material = GazeCompanionMaterial.charcoal
	var bodyOpacity = 1.0
	private var featureColor: Color { material == .pearl ? Color(white: 0.10) : .white }

	var body: some View {
		GeometryReader { geometry in
			let side = min(geometry.size.width, geometry.size.height)
			let shell = RoundedRectangle(cornerRadius: side * 0.36, style: .continuous)
			ZStack {
				shell
					.fill(LinearGradient(colors: material == .pearl
						? [Color(white: 0.95), Color(white: 0.865), Color(white: 0.90)]
						: material == .ink
							? [Color(white: 0.144), Color(white: 0.0624), Color(white: 0.096)]
							: [Color(white: 0.30), Color(white: 0.13), Color(white: 0.20)],
						startPoint: .topLeading, endPoint: .bottomTrailing))
					.padding(side * 0.045)
					.opacity(bodyOpacity)
				shell
					.strokeBorder(LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.03), .white.opacity(0.20)],
						startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(0.5, side * 0.015))
					.padding(side * 0.045)
				Ellipse()
					.fill(.white.opacity(0.20))
					.frame(width: side * 0.23, height: side * 0.06)
					.blur(radius: side * 0.035)
					.rotationEffect(.degrees(-35))
					.offset(x: -side * 0.27, y: -side * 0.31)
				HStack(spacing: side * 0.15) {
					eye(side: side, trailing: false)
					eye(side: side, trailing: true)
				}
				.offset(x: side * 0.10 * (pose.turn + pose.gaze), y: side * (0.09 + pose.nod * 0.045 - pose.mouthOpen * 0.09))
				GazeExpressionCurve(curvature: pose.expression)
					.stroke(featureColor, style: StrokeStyle(lineWidth: side * (pose.expression > 0 ? 0.044 : 0.032), lineCap: .round))
					.frame(width: side * 0.23, height: side * 0.15)
					.opacity(abs(pose.expression))
					.offset(x: side * 0.10 * pose.turn, y: side * (0.27 + max(0, pose.expression) * 0.035))
				Capsule()
					.fill(featureColor)
					.frame(width: side * 0.16, height: side * 0.19)
					.scaleEffect(x: 0.5 + pose.mouthOpen * 0.5, y: max(0.01, pose.mouthOpen))
					.opacity(pose.mouthOpen)
					.offset(y: side * 0.27)
			}
			.frame(width: side, height: side)
			.scaleEffect(1 + pose.breath * 0.014)
			.rotation3DEffect(.degrees(pose.turn * 28), axis: (x: 0, y: 1, z: 0), perspective: 0.32)
			.rotation3DEffect(.degrees(pose.nod * 22), axis: (x: 1, y: 0, z: 0), perspective: 0.32)
			.rotationEffect(.degrees(-3 + pose.turn * 2 + min(0, pose.expression) * 3))
			.offset(x: side * pose.turn * 0.04, y: side * pose.nod * 0.025)
			.frame(width: geometry.size.width, height: geometry.size.height)
		}
	}

	private func eye(side: CGFloat, trailing: Bool) -> some View {
		let sadness = max(0, -pose.expression)
		let eyeHeight = CGFloat(pose.eyesOpen * (1 - sadness * 0.26))
		let angle = Angle.degrees(sadness * (trailing ? -18.0 : 18.0))
		return Capsule()
			.fill(featureColor.opacity(0.96))
			.frame(width: side * 0.125, height: side * 0.25)
			.scaleEffect(y: eyeHeight)
			.rotationEffect(angle)
			.frame(width: side * 0.125, height: side * 0.25)
			.shadow(color: featureColor.opacity(0.18), radius: side * 0.035)
	}
}

private struct GazeExpressionCurve: Shape {
	var curvature: Double
	var animatableData: Double {
		get { curvature }
		set { curvature = newValue }
	}

	func path(in rect: CGRect) -> Path {
		var path = Path()
		let edgeHeight = rect.midY - curvature * rect.height * 0.24
		path.move(to: CGPoint(x: rect.minX, y: edgeHeight))
		path.addQuadCurve(to: CGPoint(x: rect.maxX, y: edgeHeight),
			control: CGPoint(x: rect.midX, y: rect.midY + curvature * rect.height * 0.72))
		return path
	}
}
