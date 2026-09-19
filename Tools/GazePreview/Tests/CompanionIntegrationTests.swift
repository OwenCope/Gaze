import AppKit
import SwiftUI
import Vision

@main
struct CompanionIntegrationTests {
	@MainActor static func main() throws {
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		if CommandLine.arguments.contains("--captions-only") {
			try GuidanceCaptionTests.run(directory: directory)
			return
		}
		try verifyRecognitionPanelSizing(directory: directory)
		try GuidanceCaptionTests.run(directory: directory)
		try MovementProgressTests.run(directory: directory)
		RenderDiagnosticsTests.run()
		try CompanionDirectionTests.run(directory: directory)
		try CompanionLifecycleTests.run(directory: directory)
		for motion in [GazeFaceMotion.accepted, .rejected, .resting, .scanning, .nod, .turnLeft, .turnRight] {
			for frame in 0..<480 {
				let elapsed = Double(frame) / 120
				let presentation = GazeCompanionPresentation.notch
				var expected = GazeCompanionMotion.pose(for: motion, at: presentation.sampleTime(elapsed, motion: motion))
				if motion.isOneShot {
					expected.face.expression = (motion == .accepted ? 1 : -1) * GazeCompanionTiming.ease(elapsed / 0.14)
				}
				precondition(presentation.pose(for: motion, at: elapsed) == expected)
			}
		}
		let accepted = GazeCompanionPresentation.notch
		precondition(accepted.pose(for: .accepted, at: 0.18).face.nod > 0.4)
		precondition(accepted.pose(for: .accepted, at: 0.44).face == GazeFaceMotion.accepted.stillPose)
		precondition(accepted.pose(for: .accepted, at: 0.44).stretch == 0)
		for motion in [GazeFaceMotion.resting, .scanning] {
			for frame in 0..<1920 {
				let pose = GazeCompanionMotion.pose(for: motion, at: Double(frame) / 120)
				precondition(pose.face.eyesOpen == 1 && pose.face.nod == 0 && abs(pose.face.turn) <= 0.18 && pose.face.gaze == 0 && pose.stretch == 0 && abs(pose.lift) <= 0.019 && abs(pose.drift) <= 0.067)
			}
		}
		var playback = GazeCompanionPlayback(motion: .nod, at: 0, presentation: .notch)
		for (time, motion) in [(0.85, GazeFaceMotion.accepted), (0.88, .rejected), (0.91, .scanning)] {
			let before = playback.pose(at: time)
			playback.retarget(to: motion, at: time)
			precondition(playback.pose(at: time) == before)
			precondition(playback.pose(at: time, reducedMotion: true).face == motion.stillPose)
		}
		print("PASS: identical choreography source, 440ms notch nod, uninterrupted full-size success, anchored-eye idle glance, interrupted/reduced playback")

		for (name, view, paused) in [
			("notch-success", AnyView(GazeFaceMark(phase: .success).frame(width: 160, height: 160).environment(\.scenePhase, .inactive)), false),
			("notch-hidden", AnyView(GazeFaceMark(phase: .success, active: false).frame(width: 160, height: 160)), true),
			("notch-reduced", AnyView(GazeFaceMark(phase: .success).frame(width: 160, height: 160).environment(\.notchReduceMotion, true)), true),
			("recognition-dark", AnyView(GazeCompanionView(motion: .accepted).frame(width: 160, height: 160).environment(\.scenePhase, .active).environment(\.colorScheme, .dark)), false),
			("recognition-light", AnyView(GazeCompanionView(motion: .accepted).frame(width: 160, height: 160).environment(\.scenePhase, .active).environment(\.colorScheme, .light)), false),
			("setup-success", AnyView(SetupMark(kind: .success).environment(\.scenePhase, .active).environment(\.colorScheme, .dark)), false),
			("setup-failure", AnyView(SetupMark(kind: .failure).environment(\.scenePhase, .active).environment(\.colorScheme, .dark)), false),
			("setup-welcome", AnyView(SetupMark(kind: .looking).environment(\.scenePhase, .active).environment(\.colorScheme, .dark)), false),
			("setup-success-light", AnyView(SetupMark(kind: .success).environment(\.scenePhase, .active).environment(\.colorScheme, .light)), false),
			("setup-welcome-light", AnyView(SetupMark(kind: .looking).environment(\.scenePhase, .active).environment(\.colorScheme, .light)), false)
		] {
			try CompanionCapture.snapshot(view.padding(24).background(name.hasSuffix("-light") ? Color(white: 0.95) : .black),
				to: directory.appendingPathComponent("\(name).png"), sampleOffset: 2) { surfaces in
				precondition(surfaces.count == 1, "\(name) must contain exactly one shared Metal face")
				let surface = surfaces[0]
				precondition(surface.view.isPaused == paused, "\(name) has wrong animation lifecycle")
				precondition(surface.renderer.material == (name.hasPrefix("setup-") && !name.hasSuffix("-light") ? .ink : .charcoal), "\(name) must keep its intended material")
				let now = Date.timeIntervalSinceReferenceDate
				let pose = surface.renderer.pose!(now + 3)
				if name.contains("success") || name.contains("recognition") || name.contains("reduced") || name.contains("hidden") {
					precondition(pose.face.expression == 1 && pose.face.eyesOpen == 1 && pose.face.nod == 0)
				}
				if name == "notch-success" {
					precondition(surface.renderer.pose!(now + 0.45).face.nod == 0)
				}
				if name == "recognition-dark" {
					precondition(surface.renderer.pose!(now + 0.45).face.nod > 0.2)
				}
				if name == "setup-failure" { precondition(pose.face.expression == -1) }
				if name == "setup-welcome" { precondition(pose.face.eyesOpen == 1) }
			}
		}
		print("PASS: actual notch, recognition companion and setup wrappers use the shared Metal renderer; inactive lock panel animates, inactive/Reduce Motion views pause")
		let gpu = try SoftFaceGPU()
		let darkImage = try CompanionCapture.frame(gpu: gpu, pose: .init(face: GazeFaceMotion.accepted.stillPose),
			size: CGSize(width: 160, height: 160), material: .ink)
		let standardImage = try CompanionCapture.frame(gpu: gpu, pose: .init(face: GazeFaceMotion.accepted.stillPose),
			size: CGSize(width: 160, height: 160), material: .charcoal)
		let darkBitmap = NSBitmapImageRep(data: darkImage.tiffRepresentation!)!
		let standardBitmap = NSBitmapImageRep(data: standardImage.tiffRepresentation!)!
		let darkBody = darkBitmap.colorAt(x: 80, y: 53)!.usingColorSpace(.deviceRGB)!
		let standardBody = standardBitmap.colorAt(x: 80, y: 53)!.usingColorSpace(.deviceRGB)!
		precondition(darkBody.redComponent < standardBody.redComponent * 0.6)
		precondition(abs(darkBody.alphaComponent - standardBody.alphaComponent) < 0.01)
		let brightFeatures = (0..<160).flatMap { row in
			(0..<160).map { column in darkBitmap.colorAt(x: column, y: row)!.usingColorSpace(.deviceRGB)!.redComponent }
		}.filter { $0 > 0.9 }.count
		precondition(brightFeatures > 100, "Darker shell must preserve white eyes and smile")
		print("PASS: onboarding ink shell is darker without dimming facial features or changing translucency")
		for size in [23, 36, 72, 160] {
			for material in [GazeCompanionMaterial.charcoal] {
				let image = try CompanionCapture.frame(gpu: gpu, pose: .init(face: GazeFaceMotion.accepted.stillPose),
					size: CGSize(width: size, height: size), material: material)
				let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
				let body = bitmap.colorAt(x: size / 2, y: size / 3)!.usingColorSpace(.deviceRGB)!
				precondition(body.alphaComponent > 0.6 && body.alphaComponent < 0.9)
				precondition(body.redComponent < 0.4)
				try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(material)-\(size).png"))
			}
		}
		print("PASS: approved charcoal material retains alpha and success expression at ear, notch, and full sizes; no credential or camera access")
		let frames = directory.appendingPathComponent("success-frames", isDirectory: true)
		try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
		for frame in 0..<150 {
			try autoreleasepool {
				let elapsed = Double(frame) / 60
				let full = try CompanionCapture.frame(gpu: gpu, pose: GazeCompanionPresentation.standard.pose(for: .accepted, at: elapsed), size: CGSize(width: 216, height: 216), material: .charcoal)
				let notch = try CompanionCapture.frame(gpu: gpu, pose: GazeCompanionPresentation.notch.pose(for: .accepted, at: elapsed), size: CGSize(width: 72, height: 72), material: .charcoal)
				let content = HStack(spacing: 44) {
					VStack { Image(nsImage: full); Text("Setup / recognition").foregroundStyle(.white) }
					VStack { Image(nsImage: notch).frame(width: 216, height: 216); Text("Notch · 440 ms").foregroundStyle(.white) }
				}.padding(24).background(.black)
				let render = ImageRenderer(content: content)
				let bitmap = NSBitmapImageRep(cgImage: render.cgImage!)
				try bitmap.representation(using: .png, properties: [:])!.write(to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
			}
		}
	}

	@MainActor private static func verifyRecognitionPanelSizing(directory: URL) throws {
		let readout = RecognitionTestReadout(status: "Simulated", matched: false,
			score: 0.637, threshold: 0.45, instruction: "Face the camera and hold still.",
			complete: false, canChallenge: true,
			diagnosticRows: [
				("Analyzed / expired frames", "10535 / 1"),
				("Requested movement", "Face the camera and hold still."),
				("Match score", "0.637"), ("Match threshold", "0.45"),
				("Lowest / highest", "0.149 / 0.812"), ("Samples", "921"),
				("Yaw (raw)", "+0.31 rad"), ("Pitch (raw)", "-0.12 rad"),
				("Blink observed", "Yes"), ("Eye openness", "0.300 · open"),
				("Photo / screen detector", "Clear"),
				("Detector score / threshold", "0.010 / 0.50")
			], yaw: 0.31, pitch: -0.12)
		for expanded in [false, true] {
			for requested in [CGSize(width: 240, height: 300),
				CGSize(width: 480, height: 650),
				CGSize(width: 560, height: 820), CGSize(width: 800, height: 1100)] {
				let panel = RecognitionTestPanel(readout: readout,
					showsDetail: .constant(expanded), next: {}, reset: {}) {
						Color.gray.overlay { Text("Simulated camera").foregroundStyle(.black) }
					} companion: {
						Color.gray
					}
				let renderer = ImageRenderer(content: panel.background(.black).environment(\.colorScheme, .dark))
				renderer.proposedSize = ProposedViewSize(requested)
				renderer.scale = 2
				guard let image = renderer.cgImage else {
					preconditionFailure("Recognition panel must render with simulated content")
				}
				precondition(image.width == Int(max(480, requested.width)) * 2,
					"Recognition panel must accept a wider window, retaining its minimum width")
				precondition(image.height == Int(max(650, requested.height)) * 2,
					"Recognition panel must accept a taller window, retaining its minimum height")

				// OCR only the top 250 points, not the offscreen disclosure content.
				// Outer dimensions alone previously passed with every useful number hidden.
				let summary = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 500))!
				let request = VNRecognizeTextRequest()
				request.recognitionLevel = .fast
				request.usesCPUOnly = true
				request.usesLanguageCorrection = false
				try VNImageRequestHandler(cgImage: summary).perform([request])
				let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
				for expected in ["Match score", "Threshold", "Yaw", "Pitch",
					"0.637", "0.45", "+0.31", "-0.12"] {
					precondition(text.contains(expected), "Pinned \(expected) must be visible at \(requested), expanded=\(expanded). OCR: \(text)")
				}
				let bitmap = NSBitmapImageRep(cgImage: image)
				try bitmap.representation(using: .png, properties: [:])!.write(to:
					directory.appendingPathComponent("recognition-\(Int(requested.width))x\(Int(requested.height))-\(expanded).png"))
				if requested == CGSize(width: 480, height: 650) {
					// ImageRenderer does not reliably draw AppKit-backed scroll content.
					// Also mount the real panel offscreen to check its camera and controls.
					let url = directory.appendingPathComponent("recognition-mounted-\(expanded).png")
					try CompanionCapture.snapshot(panel.frame(width: 480, height: 650)
						.background(.black).environment(\.colorScheme, .dark), to: url)
					try VNImageRequestHandler(url: url).perform([request])
					let mountedText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
					for expected in ["0.637", "0.45", "+0.31", "-0.12", "Simulated camera",
						"Face the camera", "hold still.", "Try another movement", "Reset test"] {
						precondition(mountedText.contains(expected), "Mounted minimum-size panel must show \(expected), expanded=\(expanded). OCR: \(mountedText)")
					}
				}
			}
		}
		print("PASS: recognition panel sizes and visible pinned score/threshold/yaw/pitch with 12 detail rows, open and closed; simulated content only")
	}
}
