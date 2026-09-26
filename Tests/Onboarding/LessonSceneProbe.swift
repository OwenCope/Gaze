import AppKit
import SwiftUI

@main
struct LessonSceneProbe: App {
    @NSApplicationDelegateAdaptor(LessonSceneProbeDelegate.self) private var delegate
    var body: some Scene {
        Window("Gaze Lesson Scene Probe", id: "lesson-probe") {
            LessonSceneProbeView()
        }
        .defaultSize(width: 420, height: 440)
    }
}

private final class LessonSceneProbeDelegate: NSObject, NSApplicationDelegate {
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { LessonSceneRecorder.shared.record() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

private struct LessonSceneProbeView: View {
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 20) {
            Text("Lesson visibility check").font(.title2)
            GazeLessonAnimation(motion: .turnLeft, paused: false, material: .charcoal)
                .frame(width: 240, height: 240)
            Text("Scene: \(String(describing: phase))")
            Text("Camera, credentials, and login items are off.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(30)
        .onChange(of: phase, initial: true) { _, phase in LessonSceneRecorder.shared.phase = phase }
    }
}

@MainActor private final class LessonSceneRecorder {
    static let shared = LessonSceneRecorder()
    var phase = ScenePhase.inactive
    private var previous: String?
    private var events: [[String: Any]] = []

    func record() {
        let window = NSApplication.shared.windows.first(where: { $0.title == "Gaze Lesson Scene Probe" })
        let surface = window?.contentView.flatMap { CompanionCapture.surfaces(in: $0).first }
        let time = Date.timeIntervalSinceReferenceDate
        let clockFrozen = surface?.renderer.pose.map { sample in
            [0.137, 0.419, 0.937, 1.331, 2.17, 3.01].allSatisfy { sample(time) == sample(time + $0) }
        }
        let state: [String: Any] = ["scenePhase": String(describing: phase),
            "appActive": NSApplication.shared.isActive, "appHidden": NSApplication.shared.isHidden,
            "windowPresent": window != nil, "windowVisible": window?.isVisible ?? false,
            "miniaturized": window?.isMiniaturized ?? false,
            "unoccluded": window?.occlusionState.contains(.visible) ?? false,
            "rendererAttached": surface != nil,
            "rendererPaused": surface?.view.isPaused as Any? ?? NSNull(),
            "clockFrozen": clockFrozen as Any? ?? NSNull()]
        guard let encoded = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
              let signature = String(data: encoded, encoding: .utf8), signature != previous else { return }
        previous = signature
        var event = state
        event["recordedUTC"] = ISO8601DateFormatter().string(from: Date())
        events.append(event)
        let path = CommandLine.arguments.dropFirst().first ?? NSTemporaryDirectory() + "gaze-lesson-scene-probe.json"
        do {
            try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            fputs("Could not save scene probe: \(error)\n", stderr)
        }
    }
}
