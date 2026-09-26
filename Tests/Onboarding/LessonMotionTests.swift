import AppKit
import MetalKit
import Observation
import SwiftUI

@MainActor
enum LessonMotionTests {
	@Observable final class LessonInput {
		var phase = ScenePhase.inactive
		var motion = GazeFaceMotion.turnLeft
		var paused = false
		var reduced = false
	}

	struct LessonHost: View {
		let input: LessonInput
		var body: some View {
			GazeLessonAnimation(motion: input.motion, paused: input.paused, material: .charcoal)
				.frame(width: 240, height: 240)
				.environment(\.scenePhase, input.phase)
				.environment(\.notchReduceMotion, input.reduced)
		}
	}

	final class FrameProbe: NSObject, MTKViewDelegate {
		let renderer: GazeCompanionRenderer.Coordinator
		var samples: [(Double, GazeCompanionPose)] = []
		init(renderer: GazeCompanionRenderer.Coordinator) { self.renderer = renderer }
		func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
			renderer.mtkView(view, drawableSizeWillChange: size)
		}
		func draw(in view: MTKView) {
			guard view.currentDrawable != nil, let pose = renderer.pose else { return }
			let time = Date.timeIntervalSinceReferenceDate
			samples.append((time, pose(time)))
			renderer.draw(in: view)
		}
	}

	static func run() -> [[String: Any]] {
		NSApplication.shared.setActivationPolicy(.regular)
		checkBackgroundPause()
		let durationArgument = CommandLine.arguments.first { $0.hasPrefix("--motion-seconds=") }
		let extendedDuration = durationArgument.flatMap { Double($0.dropFirst("--motion-seconds=".count)) }
		precondition(durationArgument == nil || extendedDuration.map { $0.isFinite && (4.3...30).contains($0) } == true,
			"Motion duration must be between 4.3 and 30 seconds per lesson")
		var measurements: [[String: Any]] = []
		let firstGPU = try! SoftFaceGPU.shared()
		precondition(firstGPU === (try! SoftFaceGPU.shared()), "Step changes must reuse the compiled shader pipeline")
		for lesson in [GazeExpressionLesson.waiting, .turnLeft, .success, .retry] {
			let host = NSHostingView(rootView: GazeExpressionGuide(lesson: lesson)
				.frame(width: 560, height: 380).environment(\.scenePhase, .inactive))
			host.frame = CGRect(x: 0, y: 0, width: 560, height: 380)
			let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
			window.title = "Gaze Motion Check — Camera off"
			window.contentView = host
			window.center()
			window.orderFront(nil)
			host.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
			let surfaces = CompanionCapture.surfaces(in: host)
			precondition(surfaces.count == 1)
			let surface = surfaces[0]
			precondition(!surface.view.isPaused, "Visible lesson must animate even without an active SwiftUI scene")
			let probe = FrameProbe(renderer: surface.renderer)
			surface.view.delegate = probe
			let start = Date.timeIntervalSinceReferenceDate
			let duration = extendedDuration ?? (lesson == .turnLeft ? 1.3 : 4.3)
			while Date.timeIntervalSinceReferenceDate - start < duration {
				RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
				host.layoutSubtreeIfNeeded()
			}
			precondition(probe.samples.count > 20, "Display-driven lesson must submit multiple drawable frames without manual drawing")
			precondition(probe.samples.contains { $0.1 != probe.samples[0].1 }, "Lesson cannot be a static picture")
			if lesson == .waiting {
				precondition(probe.samples.contains { $0.1.face.gaze > 0 && $0.1.drift == 0 }, "Eyes notice before approaching")
				precondition(probe.samples.contains { $0.1.drift > 0.02 }, "Curious body follows its eyes")
				precondition(probe.samples.allSatisfy { $0.1.face.eyesOpen == 1 }, "Idle cannot blink")
			}
			if lesson == .success {
				precondition(probe.samples.contains { $0.0 > start + 2.4 && $0.1.face.nod > 0.2 }, "Happy nod must repeat, not disappear before it can be learned")
			}
			if lesson == .retry {
				precondition(probe.samples.contains { $0.0 > start + 2.85 && abs($0.1.face.turn) > 0.1 }, "Head shake must repeat")
			}
			window.orderOut(nil)
			window.contentView = nil
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
			precondition(surface.view.isPaused, "Detached lesson must stop rendering")
			let intervals = zip(probe.samples.dropFirst(), probe.samples).map { ($0.0 - $1.0) * 1000 }.sorted()
			let median = intervals[intervals.count / 2]
			let percentile = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
			measurements.append(["lesson": lesson.title, "frames": probe.samples.count,
				"durationSeconds": duration, "medianMS": median, "p95MS": percentile,
				"p99MS": intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.99))],
				"maximumMS": intervals.last!, "intervalsOver33MS": intervals.filter { $0 > 33.333 }.count,
				"intervalsOver50MS": intervals.filter { $0 > 50 }.count])
			print(String(format: "PASS: %@ submitted %d display-driven frames in %.1fs; median %.1fms, p95 %.1fms", lesson.title, probe.samples.count, duration, median, percentile))
		}
		for reduced in [true, false] {
			let host = NSHostingView(rootView: GazeExpressionGuide(lesson: .nod)
				.frame(width: 560, height: 380).environment(\.notchReduceMotion, reduced)
				.environment(\.scenePhase, .inactive))
			let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 380), styleMask: [.borderless], backing: .buffered, defer: false)
			window.contentView = host
			window.orderFront(nil)
			host.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
			let surface = CompanionCapture.surfaces(in: host)[0]
			precondition(surface.view.isPaused == reduced)
			window.orderOut(nil)
			window.contentView = nil
		}
		print("PASS: live lesson submits changing Metal drawable frames in inactive scenes, repeats happy nod/head shake, pauses for Reduce Motion and stops on detach")
		return measurements
	}

	private static func checkBackgroundPause() {
		let input = LessonInput()
		let host = NSHostingView(rootView: LessonHost(input: input))
		host.frame = CGRect(x: 0, y: 0, width: 240, height: 240)
		let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
		window.title = "Gaze Lesson Lifecycle — Camera off"
		window.contentView = host
		window.orderFront(nil)
		defer { window.orderOut(nil); window.contentView = nil }
		func settle(_ seconds: Double = 0.12) {
			host.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
			host.layoutSubtreeIfNeeded()
		}
		settle(0.35)
		let surface = CompanionCapture.surfaces(in: host)[0]
		precondition(!surface.view.isPaused, "Visible inactive hosting windows must keep teaching the movement")
		input.phase = .background
		settle()
		precondition(surface.view.isPaused, "Background lessons must stop continuous rendering")
		let time = Date.timeIntervalSinceReferenceDate
		let frozen = surface.renderer.pose!(time)
		precondition(surface.renderer.pose!(time + 60) == frozen, "Background time must not advance the lesson clock")
		input.motion = .accepted
		settle()
		let selected = surface.renderer.pose!(Date.timeIntervalSinceReferenceDate)
		precondition(surface.renderer.pose!(Date.timeIntervalSinceReferenceDate + 60) == selected,
			"Selecting another lesson in the background must keep its clock paused")
		input.phase = .active
		settle()
		precondition(!surface.view.isPaused, "Foreground lessons must resume")
		let resumedTime = Date.timeIntervalSinceReferenceDate
		precondition(surface.renderer.pose!(resumedTime) != surface.renderer.pose!(resumedTime + 0.6),
			"A resumed lesson must advance again")
		input.paused = true
		settle()
		input.phase = .background
		settle()
		input.phase = .inactive
		settle()
		precondition(surface.view.isPaused, "Returning to a visible window must preserve explicit pause")
		input.paused = false
		input.reduced = true
		settle()
		precondition(surface.view.isPaused, "Reduce Motion must stop continuous rendering")
		precondition(surface.renderer.pose!(Date.timeIntervalSinceReferenceDate).face == input.motion.stillPose,
			"Reduce Motion must show the selected lesson's static pose")
		input.reduced = false
		settle()
		precondition(!surface.view.isPaused, "Disabling Reduce Motion must resume a visible lesson")
		window.contentView = nil
		settle()
		precondition(surface.view.isPaused, "Detached lessons must stop rendering")
		print("PASS: mounted lesson background freeze/resume, selection while paused, explicit pause, Reduce Motion and detach")
	}
}
