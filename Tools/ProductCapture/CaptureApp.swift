import AppKit
import ScreenCaptureKit
import SwiftUI

@main struct ProductCaptureApp: App {
    @MainActor private static var captureStarted = false
    init() {
        Preferences.shared.appTheme = .glass
        Preferences.shared.notchStyle = .semiLiquidGlass
    }
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
        guard !Self.captureStarted else { return }
        Self.captureStarted = true
        do {
            try await Task.sleep(for: .seconds(1))
            guard let window = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible }) else {
                throw CaptureError.missingWindow
            }
            guard let screen = window.screen else { throw CaptureError.missingWindow }
            if kind == "security", let content = window.contentView,
               let scrollView = Self.scrollView(in: content), let document = scrollView.documentView {
                let bottom = max(0, document.bounds.height - scrollView.contentView.bounds.height)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? bottom : 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            backdrop.isReleasedWhenClosed = false
            backdrop.hasShadow = false
            backdrop.ignoresMouseEvents = true
            let wallpaperURL = URL(fileURLWithPath: "/System/Library/Wallpapers/.default/DefaultAerial.heic")
            guard let wallpaper = NSImage(contentsOf: wallpaperURL) else { throw CaptureError.missingWallpaper }
            backdrop.contentView = NSHostingView(rootView:
                Image(nsImage: wallpaper).resizable().scaledToFill()
                    .frame(width: screen.frame.width, height: screen.frame.height).clipped())
            defer { backdrop.close() }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            backdrop.order(.below, relativeTo: window.windowNumber)
            try await Task.sleep(for: .seconds(0.5))
            let destination = CommandLine.arguments.first { $0.hasPrefix("--output=") }!
                .dropFirst("--output=".count)
            let path = URL(fileURLWithPath: String(destination))
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let record: [String: Any] = ["windowID": window.windowNumber, "kind": kind,
                "width": window.frame.width, "height": window.frame.height]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: path.appendingPathComponent("window.json"))
            if CommandLine.arguments.contains("--inspect") { return }
            let shareable = try await SCShareableContent.currentProcess
            guard shareable.windows.contains(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                throw CaptureError.missingWindow
            }
            guard let display = shareable.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                throw CaptureError.missingWindow
            }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: window.frame.minX, y: screen.frame.maxY - window.frame.maxY,
                                              width: window.frame.width, height: window.frame.height)
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, including: shareable.windows), configuration: configuration)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.encoding }
            try png.write(to: path.appendingPathComponent("\(kind).png"))
            print("Captured current \(kind) UI: \(image.width)x\(image.height); empty demo enrollment; no camera or credentials")
        } catch {
            fputs("Product capture failed: \(error)\n", stderr)
        }
        NSApp.terminate(nil)
    }

    enum CaptureError: Error { case missingWindow, missingWallpaper, encoding }

    @MainActor private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let result = scrollView(in: child) { return result }
        }
        return nil
    }
}
