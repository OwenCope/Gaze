import AppKit
import ScreenCaptureKit
import SwiftUI

@main struct ProductCaptureApp: App {
    private let store = FaceEnrollmentStore()
    private let lockout = LockoutManager(load: { nil }, save: { _ in
        fatalError("Product capture cannot save lockout state")
    })
    private let kind = CommandLine.arguments.first { $0.hasPrefix("--capture=") }?
        .split(separator: "=").last.map(String.init) ?? "general"
    private var isTour: Bool { kind == "movement" || kind == "welcome" }

    var body: some Scene {
        Window("Gaze", id: "capture-tour") {
            content.containerBackground(.clear, for: .window)
        }
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .windowStyle(.plain)
        .defaultLaunchBehavior(isTour ? .presented : .suppressed)

        Window("Gaze", id: "capture-settings") { content }
            .defaultSize(width: 720, height: 600)
            .windowResizability(.contentMinSize)
            .restorationBehavior(.disabled)
            .windowToolbarStyle(.unified(showsTitle: false))
            .defaultLaunchBehavior(isTour ? .suppressed : .presented)
    }

    private var content: some View {
        Group {
            switch kind {
            case "welcome": GazeWelcomeTour(onContinue: {}, onClose: {})
            case "movement": GazeMovementTour(onClose: {}, initialPageIndex: 1)
            default: SettingsView(store: store, lockout: lockout)
            }
        }
        .preferredColorScheme(.dark)
        .task { await capture() }
    }

    @MainActor private func capture() async {
        do {
            try await Task.sleep(for: .seconds(1))
            guard let window = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible }) else {
                throw CaptureError.missingWindow
            }
            let destination = CommandLine.arguments.first { $0.hasPrefix("--output=") }!
                .dropFirst("--output=".count)
            let path = URL(fileURLWithPath: String(destination))
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let record: [String: Any] = ["windowID": window.windowNumber, "kind": kind,
                "width": window.frame.width, "height": window.frame.height]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: path.appendingPathComponent("window.json"))
            if CommandLine.arguments.contains("--inspect") { return }
            let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let target = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                throw CaptureError.missingWindow
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.encoding }
            try png.write(to: path.appendingPathComponent("\(kind).png"))
            print("Captured current \(kind) UI: \(image.width)x\(image.height); empty demo enrollment; no camera or credentials")
        } catch {
            fputs("Product capture failed: \(error)\n", stderr)
        }
        NSApp.terminate(nil)
    }

    enum CaptureError: Error { case missingWindow, encoding }
}
