import AppKit
import MetalKit
import Observation
import OSLog
import SwiftUI

/// A visible, synthetic host for the production renderer. Never opens the camera.
@main
@MainActor
enum RenderTimingProbe {
	@Observable final class Input {
		var ticks = 0
		var notch = false
		var updating = false
		var reduced = false
		var motion = GazeFaceMotion.turnLeft
	}

	struct Host: View {
		let input: Input
		var body: some View {
			VStack(spacing: 16) {
				Text("Gaze render timing").font(.headline)
				Text("Simulated movement · camera and authentication off").font(.caption)
				GazeCompanionView(motion: input.motion, runsWhileInactive: input.notch,
					presentation: input.notch ? .notch : .standard)
					.frame(width: input.notch ? 72 : 160, height: input.notch ? 72 : 160)
					.frame(height: 180)
				Text("\(input.notch ? "Notch" : "Recognition") · \(input.updating ? "30 Hz parent updates" : "steady parent") · \(input.ticks)")
					.font(.caption).monospacedDigit()
			}
			.padding(24).frame(width: 480, height: 300)
			.background(.black).foregroundStyle(.white)
			.environment(\.scenePhase, input.notch ? .inactive : .active)
			.environment(\.notchReduceMotion, input.reduced)
		}
	}

	static func main() throws {
		precondition(GazeRenderDiagnostics.enabled, "Launch with GAZE_RENDER_DIAGNOSTICS=1")
		let app = NSApplication.shared
		app.setActivationPolicy(.accessory)
		let input = Input()
		let host = NSHostingView(rootView: Host(input: input))
		let window = NSWindow(contentRect: CGRect(x: 30, y: 60, width: 480, height: 300),
			styleMask: [.titled, .closable], backing: .buffered, defer: false)
		window.title = "Gaze render timing — simulated"
		window.isReleasedWhenClosed = false
		window.contentView = host
		window.orderFront(nil)
		defer { window.orderOut(nil); window.contentView = nil }
		let duration = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
		precondition(duration >= 5 && duration <= 60)
		Task { @MainActor in
			await measure(input: input, window: window, host: host, duration: duration)
			app.terminate(nil)
		}
		app.run()
	}

	private static func measure(input: Input, window: NSWindow, host: NSView, duration: Double) async {
		let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "RenderTiming")
		var cases = [(false, false), (false, true), (true, false), (true, true)]
		if CommandLine.arguments.contains("--reverse") { cases.reverse() }
		for (notch, updating) in cases {
			input.notch = notch
			input.updating = updating
			input.motion = notch ? .turnRight : .turnLeft
			print("BEGIN notch=\(notch) parentUpdates=\(updating) seconds=\(duration)")
			logger.notice("Probe case started; notch=\(notch) parentUpdates=\(updating) seconds=\(duration). Synthetic host, no camera.")
			fflush(stdout)
			let until = Date(timeIntervalSinceNow: duration)
			while Date() < until && window.isVisible {
				if updating { input.ticks += 1 }
				try? await Task.sleep(for: .seconds(1.0 / 30))
			}
			guard window.isVisible else { return }
		}
		input.reduced = true
		try? await Task.sleep(for: .milliseconds(200))
		let surfaces = CompanionCapture.surfaces(in: host)
		precondition(surfaces.count == 1 && surfaces[0].view.isPaused)
		precondition(surfaces[0].renderer.diagnostics == nil, "Paused rendering must discard timing history")
		print("PASS: natural Metal callbacks measured; Reduce Motion pauses and clears diagnostics. No camera or authentication used.")
	}
}
