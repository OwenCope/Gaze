import AppKit
import SwiftUI

@main
struct NotchTests {
	@MainActor static func main() throws {
		verifyPanelAlignment()
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let actions: [(String, NotchCapsuleModel.Phase, GazeFaceMotion)] = [
			("left", .challenge(prompt: "Turn your head left", symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false), .turnLeft),
			("right", .challenge(prompt: "Turn your head right", symbol: "arrowshape.right.fill", hintX: 1, hintY: 0, pulses: false), .turnRight),
			("nod", .challenge(prompt: "Nod your head", symbol: "arrowshape.down.fill", hintX: 0, hintY: 1, pulses: false), .nod),
			("blink", .challenge(prompt: "Blink", symbol: "eye.fill", hintX: 0, hintY: 0, pulses: true), .blink),
			("mouth", .challenge(prompt: "Open your mouth", symbol: "mouth.fill", hintX: 0, hintY: 0, pulses: true), .openMouth)
		]
		for (_, phase, expected) in actions {
			precondition(GazeFaceMotion(phase: phase) == expected)
		}
		precondition(GazeFaceMotion(phase: .challenge(prompt: "Look at the camera", symbol: "camera.fill", hintX: 0, hintY: 0, pulses: false)) == .resting)
		precondition(GazeFaceMotion(phase: .success) == .accepted)
		precondition(GazeFaceMotion(phase: .spoofRejected) == .rejected)
		for frame in 0...336 {
			let time = Double(frame) / 120
			let left = GazeFaceMotion.turnLeft.pose(at: time)
			let right = GazeFaceMotion.turnRight.pose(at: time)
			precondition(left.turn <= 0 && right.turn >= 0)
			precondition(abs(left.turn + right.turn) < 0.000001)
			for (_, _, motion) in actions {
				let current = motion.pose(at: time)
				let next = motion.pose(at: time + 1 / 120.0)
				precondition(abs(current.turn - next.turn) < 0.04)
				precondition(abs(current.nod - next.nod) < 0.04)
				precondition(abs(current.eyesOpen - next.eyesOpen) < 0.12)
				precondition(abs(current.mouthOpen - next.mouthOpen) < 0.04)
			}
		}
		for motion in [GazeFaceMotion.turnLeft, .turnRight] {
			let radians = abs(motion.pose(at: 1.2).turn) * 0.489
			precondition(radians > 0.30 && radians < 0.38, "Demonstration must stay near the required turn")
		}
		precondition(GazeFaceMotion.blink.pose(at: 0.95).eyesOpen < 0.1)
		precondition(GazeFaceMotion.openMouth.pose(at: 1.2).mouthOpen == 1)
		precondition(GazeFaceMotion.nod.pose(at: 2.79).nod == 0)
		print("PASS: five visual action mappings, mirrored directions, smooth loops, distinct blink/mouth cues")

		precondition(GazeFaceMotion.accepted.pose(at: 0.18).nod > 0.4)
		precondition(GazeFaceMotion.accepted.pose(at: 0.45) == GazeFaceMotion.accepted.stillPose)
		precondition(GazeFaceMotion.rejected.pose(at: 0.15).turn > 0)
		precondition(GazeFaceMotion.rejected.pose(at: 0.28).turn < 0)
		for time in [0.9, 2.8, 10.0, 100.0] {
			precondition(GazeFaceMotion.accepted.pose(at: time) == GazeFaceMotion.accepted.stillPose)
			precondition(GazeFaceMotion.rejected.pose(at: time) == GazeFaceMotion.rejected.stillPose)
		}
		for motion in [GazeFaceMotion.resting, .scanning] {
			for frame in 0...960 {
				let idle = motion.pose(at: Double(frame) / 120)
				precondition(idle.eyesOpen == 1 && abs(idle.turn) <= 0.18 && idle.gaze == 0 && idle.nod == 0 && idle.breath == 0)
			}
			precondition(motion.pose(at: 1.7).turn > 0)
			precondition(motion.pose(at: 5.7).turn < 0)
			precondition(motion.pose(at: 8) == motion.pose(at: 0))
			precondition(motion.stillPose == GazeFacePose())
		}
		var playback = GazeFacePlayback(motion: .turnRight, at: 0)
		for (time, motion) in [(1.2, GazeFaceMotion.accepted), (1.23, .rejected), (1.27, .turnLeft), (1.32, .scanning)] {
			let before = playback.pose(at: time)
			playback.retarget(to: motion, at: time)
			precondition(playback.pose(at: time) == before)
			let settledTime = time + 0.2
			precondition(playback.pose(at: settledTime) == motion.pose(at: settledTime - time))
		}
		for motion in [GazeFaceMotion.accepted, .rejected, .scanning] {
			for frame in 0..<1200 {
				let time = Double(frame) / 120
				let current = motion.pose(at: time)
				let next = motion.pose(at: time + 1 / 120.0)
				precondition(abs(current.turn - next.turn) < 0.08)
				precondition(abs(current.nod - next.nod) < 0.08)
				precondition(abs(current.expression - next.expression) < 0.14)
				precondition(abs(current.eyesOpen - next.eyesOpen) < 0.14)
			}
		}
		print("PASS: shared happy nod finishes within 480ms, sad shake settles, anchored-eye idle glance, interruption continuity, static expressions")
		let expressions: [(String, GazeFaceMotion, [Double])] = [
			("Idle", .scanning, [0, 1.7, 3.49, 5.7]),
			("Happy", .accepted, [0.08, 0.21, 0.34, 0.6]),
			("Sad", .rejected, [0.15, 0.28, 0.5, 0.9])
		]
		try render(VStack(spacing: 24) {
			ForEach(expressions.indices, id: \.self) { index in
				HStack(spacing: 30) {
					Text(expressions[index].0).frame(width: 64, alignment: .leading)
					ForEach(expressions[index].2, id: \.self) { time in
						GazeFaceDrawing(pose: expressions[index].1.pose(at: time), motion: expressions[index].1)
							.frame(width: 90, height: 90)
					}
				}
			}
		}.padding(32).foregroundStyle(.white).background(Color(white: 0.08)),
			to: directory.appendingPathComponent("expressions-contact-sheet.png"))

		var samples = 0
		for width: CGFloat in [200, 281.5, 346] {
			for height: CGFloat in [35, 64.5, 128] {
				for radius: CGFloat in [0, 4.25, 17] {
					let rect = CGRect(x: 3.25, y: 2.5, width: width, height: height)
					let path = NotchPanelShape(topRadius: radius, bottomRadius: 26).path(in: rect)
					for inset: CGFloat in [0.1, 0.5, 0.9, 1.5] {
						for offset: CGFloat in [0.1, 0.5, 1, 2, 4] {
							for edge in [rect.minX + radius + inset, rect.maxX - radius - inset] {
								precondition(path.contains(CGPoint(x: edge, y: rect.minY + offset)))
								samples += 1
							}
						}
					}
				}
			}
		}
		print("PASS: \(samples) notch seam samples")

		let sheet = VStack(spacing: 24) {
			ForEach(actions.indices, id: \.self) { index in
				HStack(spacing: 24) {
					Text(actions[index].0.capitalized).frame(width: 64, alignment: .leading)
					ForEach([0.0, 0.6, 0.78, 1.2, 2.1], id: \.self) { time in
						GazeFaceDrawing(pose: actions[index].2.pose(at: time), motion: actions[index].2)
							.frame(width: 90, height: 90)
					}
				}
			}
		}
		.padding(32)
		.foregroundStyle(.white)
		.background(Color(white: 0.08))
		try render(sheet, to: directory.appendingPathComponent("movement-contact-sheet.png"))
		for shape in Preferences.PanelShape.allCases {
			for style in Preferences.NotchStyle.allCases {
				let model = NotchCapsuleModel()
				model.shape = shape
				model.style = style
				model.isExpanded = true
				let view = NotchPreviewCanvas(model: model, background: Color(white: 0.6))
					.frame(width: 620, height: 252)
				try render(view, to: directory.appendingPathComponent("\(shape.rawValue)-\(style.rawValue).png"))
			}
			for (name, phase, _) in actions {
				let model = NotchCapsuleModel()
				model.shape = shape
				model.phase = phase
				model.isExpanded = true
				try render(NotchPreviewCanvas(model: model, widthAdjust: -40, heightAdjust: -20)
					.frame(width: 620, height: 252).environment(\.notchReduceMotion, true),
					to: directory.appendingPathComponent("\(shape.rawValue)-small-\(name).png"))
			}
		}
		let ear = NotchCapsuleModel()
		ear.glyphPlacement = .ear
		ear.isExpanded = true
		try render(NotchPreviewCanvas(model: ear).frame(width: 620, height: 252),
			to: directory.appendingPathComponent("ear-scanning.png"))
		for (name, phase) in [("verified", NotchCapsuleModel.Phase.success), ("rejected", .notRecognised), ("spoof-rejected", .spoofRejected)] {
			ear.phase = phase
			try render(NotchPreviewCanvas(model: ear).frame(width: 620, height: 252),
				to: directory.appendingPathComponent("ear-\(name).png"))
			let model = NotchCapsuleModel()
			model.phase = phase
			model.isExpanded = true
			try render(NotchPreviewCanvas(model: model).frame(width: 620, height: 252),
				to: directory.appendingPathComponent("connected-\(name).png"))
		}
		let reduced = NotchCapsuleModel()
		reduced.isExpanded = true
		reduced.phase = actions[0].1
		try render(NotchPreviewCanvas(model: reduced).frame(width: 620, height: 252)
			.environment(\.notchReduceMotion, true), to: directory.appendingPathComponent("reduced-motion.png"))
		print("PASS: rendered all styles/shapes and Reduce Motion guidance to \(directory.path)")
	}

	private static func verifyPanelAlignment() {
		let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
		let actual = NotchMetrics.panelFrame(
			size: CGSize(width: 179 * 1.56, height: 98 - 0.001003440366972086),
			screenFrame: screen, scale: 2)
		precondition(actual == CGRect(x: 595, y: 858, width: 280, height: 98))
		var cases = 0
		for scale: CGFloat in [1, 2] {
			for screen in [screen, CGRect(x: -1920, y: -200, width: 1920, height: 1080),
				CGRect(x: 1470, y: 140, width: 1512.5, height: 982)] {
				for width: CGFloat in [179, 239.24, 279.24, 319.24] {
					for height: CGFloat in [32, 77.999, 98, 128.25, 256.4] {
						let desired = CGSize(width: width, height: height)
						let aligned = NotchMetrics.panelFrame(size: desired, screenFrame: screen, scale: scale)
						precondition(aligned.width >= width && aligned.height >= height)
						precondition((aligned.width - width) * scale < 2.000001)
						precondition((aligned.height - height) * scale < 1.000001)
						precondition(aligned.maxY == screen.maxY)
						precondition(abs(aligned.midX - screen.midX) * scale <= 0.5)
						for edge in [(aligned.minX - screen.minX) * scale,
							(aligned.maxX - screen.minX) * scale, aligned.height * scale] {
							precondition(abs(edge - edge.rounded()) < 0.000001)
						}
						cases += 1
					}
				}
			}
		}
		print("PASS: \(cases) outward pixel-aligned panel layouts, including current screen and fractional size adjustments")
	}

	@MainActor private static func render<Content: View>(_ content: Content, to url: URL) throws {
		try CompanionCapture.snapshot(content, to: url, sampleOffset: 0.15)
	}
}
