#!/usr/bin/env python3
"""Run the actual Gaze welcome tour with inert completion callbacks."""
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/gaze-ship-20260918/guided-setup-interaction"
APP = OUT / "Tour Fixture.app"
BIN = APP / "Contents/MacOS/TourFixture"
BIN.parent.mkdir(parents=True, exist_ok=True)
resources = APP / "Contents/Resources/Art"
resources.mkdir(parents=True, exist_ok=True)
for name in ("onboarding-recognition.png", "onboarding-local.png", "onboarding-unlock.png", "onboarding-choice.png", "onboarding-success.png", "onboarding-failure.png", "movement-left.png", "movement-right.png", "movement-nod.png", "movement-blink.png", "movement-mouth.png"):
    shutil.copyfile(ROOT / "Resources/Art" / name, resources / name)
with (APP / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleIdentifier": "local.gaze.tour-validation", "CFBundleExecutable": "TourFixture",
                   "CFBundleName": "Gaze Tour Fixture", "CFBundlePackageType": "APPL"}, stream)
swift = OUT / "TourFixture.swift"
swift.write_text(r'''
import AppKit
import SwiftUI

final class FixtureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct CompletionScenario {
    let name: String
    let title: String
    let primary: String
    let expectedAction: String
    var failure: String? = nil
    var unfinished = SetupUnfinished()
    var addingFace = false
    var canOpenSettings = false
    var canTest = false
}

@main @MainActor struct TourFixture {
    static let headings = [
        "Meet Gaze",
        "Stays on your Mac",
        "How unlock works",
        "Unlocking stays your choice",
    ]

    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4)) }

    // AX traversal through the Accessibility API. SwiftUI's AX nodes are not
    // NSViews, so in-process accessibility messaging cannot reach them; the
    // C API below is what observes (and presses) the real elements.
    static func axCopy(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        axCopy(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }
    static func axRole(_ element: AXUIElement) -> String {
        axCopy(element, kAXRoleAttribute as String) as? String ?? ""
    }
    static func axLabel(_ element: AXUIElement) -> String {
        for name in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] as [String] {
            if let text = axCopy(element, name) as? String, !text.isEmpty { return text }
        }
        return ""
    }
    static func axIdent(_ element: AXUIElement) -> String {
        axCopy(element, kAXIdentifierAttribute as String) as? String ?? ""
    }
    static func axNodes(_ root: AXUIElement) -> [AXUIElement] {
        var output: [AXUIElement] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40 else { return }
            output.append(element)
            for child in axChildren(element) { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return output
    }
    static func axWindow(titled title: String) -> AXUIElement {
        let appElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        let windows = axCopy(appElement, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
        if let match = windows.first(where: { (axCopy($0, kAXTitleAttribute as String) as? String) == title }) {
            return match
        }
        print("visible window titles=\(windows.map { axCopy($0, kAXTitleAttribute as String) as? String ?? "?" })")
        preconditionFailure("Missing fixture window: \(title)")
    }
    static func axDump(_ host: AXUIElement) {
        for element in axNodes(host) {
            print("ax role=\(axRole(element)) label=[\(axLabel(element))] ident=[\(axIdent(element))]")
        }
    }
    static func axButton(_ label: String, host: AXUIElement) -> AXUIElement? {
        axNodes(host).first { axRole($0) == (kAXButtonRole as String) && axLabel($0) == label }
    }
    static func press(_ label: String, host: AXUIElement) {
        guard let element = axButton(label, host: host) else {
            axDump(host)
            preconditionFailure("Missing button: \(label)")
        }
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        precondition(error == .success, "Press failed for \(label): \(error.rawValue)")
        settle()
    }
    /// Upstream close control: TourKit's checkmark icon button, observed as
    /// AXButton desc "Selected" ident "checkmark" (the SF Symbol default label).
    static func closeControl(host: AXUIElement) -> AXUIElement? {
        axNodes(host).first { axRole($0) == (kAXButtonRole as String) && axIdent($0) == "tour-close" }
    }
    /// Upstream back control: TourKit's chevron icon button, observed as
    /// AXButton desc "Back". Absent on the first page.
    static func backControl(host: AXUIElement) -> AXUIElement? {
        axButton("Back", host: host)
    }
    static func capture(_ container: NSView, card host: NSView, path: String) throws {
        container.layoutSubtreeIfNeeded()
        precondition(container.bounds.insetBy(dx: -0.5, dy: -0.5).contains(host.frame), "The tour must fit without clipping")
        pageBounds.append(["containerWidth": container.bounds.width, "containerHeight": container.bounds.height,
                           "cardX": host.frame.origin.x, "cardY": host.frame.origin.y,
                           "cardWidth": host.frame.width, "cardHeight": host.frame.height,
                           "capture": URL(fileURLWithPath: path).lastPathComponent])
        let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
        container.cacheDisplay(in: container.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    static var pageBounds: [[String: Any]] = []
    static func checkPage(_ index: Int, host: AXUIElement, pageHeadings: [String]? = nil, finishTitle: String = "Start setup") {
        let titles = pageHeadings ?? headings
        let nodes = axNodes(host)
        let labels = nodes.map(axLabel)
        precondition(labels.filter { $0 == "Page \(index + 1) of \(titles.count)" }.count == 1, "Exactly one page indicator")
        precondition(labels.contains(titles[index]), "Heading on page \(index): \(titles[index])")
        let primary = index == titles.count - 1 ? finishTitle : "Next"
        let primaryButtons = nodes.filter { axRole($0) == (kAXButtonRole as String) && axLabel($0) == primary }
        precondition(primaryButtons.count == 1, "Exactly one primary button \(primary) on page \(index)")
        let other = index == titles.count - 1 ? "Next" : finishTitle
        precondition(axButton(other, host: host) == nil, "No \(other) on page \(index)")
        for absent in ["Skip", "Continue", "Previous page", "Close introduction", "Step 1 of 1"] {
            precondition(!labels.contains(absent), "No \(absent) control on page \(index)")
        }
    }
    static func mount<Content: View>(_ content: Content, in container: NSView) -> NSView {
        for child in container.subviews { child.removeFromSuperview() }
        let host = NSHostingView(rootView: content.preferredColorScheme(.dark).environment(\.scenePhase, .inactive))
        host.frame = container.bounds
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        host.frame = CGRect(x: (container.bounds.width - fitting.width) / 2,
                            y: (container.bounds.height - fitting.height) / 2,
                            width: fitting.width, height: fitting.height)
        host.autoresizingMask = []
        container.addSubview(host)
        host.layoutSubtreeIfNeeded()
        settle()
        return host
    }
    static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        var completed = 0
        var closed = 0
        let host = NSHostingView(rootView: SetupWelcomeStep(onContinue: { completed += 1 }, onClose: { closed += 1 })
            .preferredColorScheme(.dark)
            .transaction { $0.disablesAnimations = true })
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 680)
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 760, height: 680))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.autoresizingMask = [.width, .height]
        host.autoresizingMask = []
        host.frame = CGRect(x: (760 - fitting.width) / 2, y: (680 - fitting.height) / 2, width: fitting.width, height: fitting.height)
        container.addSubview(host)
        let window = FixtureWindow(contentRect: container.frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.title = "Gaze Tour Fixture — no camera or credentials"
        window.contentMinSize = NSSize(width: 760, height: 680)
        window.contentMaxSize = NSSize(width: 760, height: 680)
        precondition(!window.styleMask.contains(.titled) && window.standardWindowButton(.closeButton) == nil)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        settle()
        var ax = axWindow(titled: window.title)
        guard closeControl(host: ax) != nil else {
            axDump(ax)
            preconditionFailure("Missing upstream close control on page 0")
        }
        precondition(backControl(host: ax) == nil, "Upstream Back must be absent from the first page")
        checkPage(0, host: ax)
        try capture(container, card: host, path: CommandLine.arguments[1] + "/intro-1.png")
        for page in 1...3 {
            press("Next", host: ax)
            precondition(completed == 0 && closed == 0, "Paging must not fire callbacks")
            ax = axWindow(titled: window.title)
            checkPage(page, host: ax)
            if page == 1 {
                guard backControl(host: ax) != nil else {
                    axDump(ax)
                    preconditionFailure("Missing upstream Back on page 1")
                }
                press("Back", host: ax)
                precondition(completed == 0 && closed == 0)
                ax = axWindow(titled: window.title)
                checkPage(0, host: ax)
                precondition(backControl(host: ax) == nil, "Back gone after returning to page 0")
                press("Next", host: ax)
                ax = axWindow(titled: window.title)
                checkPage(1, host: ax)
            }
            try capture(container, card: host, path: CommandLine.arguments[1] + "/intro-\(page + 1).png")
        }
        press("Start setup", host: ax)
        precondition(completed == 1 && closed == 0, "Final callback fires exactly once")

        // Upstream close control in a fresh host.
        var completedFresh = 0
        var closedFresh = 0
        let fresh = NSHostingView(rootView: SetupWelcomeStep(onContinue: { completedFresh += 1 }, onClose: { closedFresh += 1 })
            .preferredColorScheme(.dark)
            .transaction { $0.disablesAnimations = true })
        fresh.frame = host.frame
        fresh.autoresizingMask = []
        host.removeFromSuperview()
        container.addSubview(fresh)
        fresh.layoutSubtreeIfNeeded()
        settle()
        ax = axWindow(titled: window.title)
        checkPage(0, host: ax)
        precondition(backControl(host: ax) == nil, "Fresh host starts on page 0 with no Back")
        guard let close = closeControl(host: ax) else {
            axDump(ax)
            preconditionFailure("Missing upstream close control in fresh host")
        }
        precondition(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success, "Upstream close press")
        settle()
        precondition(closedFresh == 1 && completedFresh == 0, "Close fires onClose only")

        let movementHeadings = ["Practice the movements", "Turn left", "Turn right", "Nod", "Blink", "Open mouth"]
        var movementClosed = 0
        let movementHost = mount(GazeMovementTour(onClose: { movementClosed += 1 }, movementCount: 1), in: container)
        ax = axWindow(titled: window.title)
        precondition(axNodes(ax).map(axLabel).contains { $0.contains("one small movement") && $0.contains("camera off") })
        var movementPerformance: [[String: Any]] = []
        for page in 0..<movementHeadings.count {
            ax = axWindow(titled: window.title)
            checkPage(page, host: ax, pageHeadings: movementHeadings, finishTitle: "Done")
            precondition(movementClosed == 0)
            precondition(axButton("Pause", host: ax) == nil && axButton("Play", host: ax) == nil, "No playback chrome in the movement guide")
            let surfaces = CompanionCapture.surfaces(in: movementHost)
            precondition(surfaces.count == 1, "Only the current page owns a renderer")
            let mediaFrame = surfaces[0].view.convert(surfaces[0].view.bounds, to: movementHost)
            precondition(abs(mediaFrame.midX - movementHost.bounds.midX) < 1, "Movement is horizontally centered")
            let surface = surfaces[0]
            precondition(!surface.view.isPaused, "The current movement plays automatically")
            let probe = LessonMotionTests.FrameProbe(renderer: surface.renderer)
            surface.view.delegate = probe
            let start = Date.timeIntervalSinceReferenceDate
            while Date.timeIntervalSinceReferenceDate - start < 6 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
            }
            precondition(probe.samples.count > 180, "Glass guide must submit continuous drawable frames")
            precondition(probe.samples.contains { $0.1 != probe.samples[0].1 }, "The visible guide must animate")
            let intervals = zip(probe.samples.dropFirst(), probe.samples).map { ($0.0 - $1.0) * 1000 }.sorted()
            let p95 = intervals[Int(Double(intervals.count - 1) * 0.95)]
            movementPerformance.append(["page": movementHeadings[page], "frames": probe.samples.count,
                "durationSeconds": 6, "medianMS": intervals[intervals.count / 2], "p95MS": p95])
            surface.view.delegate = surface.renderer
            print("PASS: movement guide \(movementHeadings[page]), \(probe.samples.count) frames, p95 \(p95)ms")
            fflush(stdout)
            try capture(container, card: movementHost, path: CommandLine.arguments[1] + "/movement-\(page + 1).png")
            press(page == movementHeadings.count - 1 ? "Done" : "Next", host: ax)
        }
        precondition(movementClosed == 1, "Movement guide closes without entering setup")

        let scenarios = [
            CompletionScenario(name: "complete-test", title: "Enjoy a little less typing.", primary: "Test Recognition", expectedAction: "test", canTest: true),
            CompletionScenario(name: "complete-done", title: "Enjoy a little less typing.", primary: "Done", expectedAction: "done"),
            CompletionScenario(name: "needs-password", title: "Your face is saved", primary: "Finish in Settings", expectedAction: "settings", unfinished: .init(needsPassword: true), canOpenSettings: true, canTest: true),
            CompletionScenario(name: "needs-permission", title: "Your face is saved", primary: "Finish in Settings", expectedAction: "settings", unfinished: .init(needsAccessibility: true), canOpenSettings: true, canTest: true),
            CompletionScenario(name: "needs-both", title: "Your face is saved", primary: "Finish in Settings", expectedAction: "settings", unfinished: .init(needsPassword: true, needsAccessibility: true), canOpenSettings: true),
            CompletionScenario(name: "partial-no-opener", title: "Your face is saved", primary: "Done", expectedAction: "done", unfinished: .init(needsPassword: true)),
            CompletionScenario(name: "failed", title: "Setup didn’t finish", primary: "Try Again", expectedAction: "retry", failure: "Fixture storage failure.", unfinished: .init(needsPassword: true, needsAccessibility: true), canOpenSettings: true, canTest: true),
            CompletionScenario(name: "added-face", title: "Face added", primary: "Done", expectedAction: "done", addingFace: true, canOpenSettings: true, canTest: true),
        ]
        for scenario in scenarios {
            var actions: [String] = []
            let settingsAction: (() -> Void)? = scenario.canOpenSettings ? { actions.append("settings") } : nil
            let testAction: (() -> Void)? = scenario.canTest ? { actions.append("test") } : nil
            let completionHost = mount(SetupDoneStep(failure: scenario.failure, unfinished: scenario.unfinished,
                isAddingFace: scenario.addingFace, onDone: { actions.append("done") }, onRetry: { actions.append("retry") },
                onOpenSettings: settingsAction, onTestRecognition: testAction), in: container)
            ax = axWindow(titled: window.title)
            checkPage(0, host: ax, pageHeadings: [scenario.title], finishTitle: scenario.primary)
            try capture(container, card: completionHost, path: CommandLine.arguments[1] + "/completion-\(scenario.name).png")
            press(scenario.primary, host: ax)
            precondition(actions == [scenario.expectedAction], "Correct completion action for \(scenario.name)")
            actions.removeAll()
            ax = axWindow(titled: window.title)
            guard let close = closeControl(host: ax) else { preconditionFailure("Completion close is missing") }
            precondition(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success)
            settle()
            precondition(actions == ["done"], "Completion close never starts a camera/test or retries")
        }

        let performanceData = try JSONSerialization.data(withJSONObject: movementPerformance, options: [.prettyPrinted, .sortedKeys])
        try performanceData.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/movement-performance.json"))
        let layout: [String: Any] = [
            "requestedWindow": ["width": 760, "height": 680],
            "hostFittingSize": ["width": fitting.width, "height": fitting.height],
            "hostBoundsAtCapture": pageBounds,
            "windowFrame": ["width": window.frame.width, "height": window.frame.height],
            "introPages": 4,
            "movementPages": movementHeadings.count,
            "completionScenarios": scenarios.count,
            "cardWidth": 720,
            "upstreamWidth": 660,
            "uniformScale": 720.0 / 660.0,
            "borderless": true,
        ]
        let layoutData = try JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys])
        try layoutData.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/tour-layout.json"))

        window.close()
        settle()
        precondition(!window.isVisible, "The borderless host must close")
        print("PASS: four-page introduction, separate six-page movement guide, eight truthful completion/action states, optional test/close, borderless 760x680 host, no clipping, one navigation system, Back/Next/finish/close and inert callbacks; not covered: dragging, live camera, Escape, state restoration or real security operations")
    }
}
''')
env = os.environ.copy()
env["DEVELOPER_DIR"] = "/Applications/Xcode-beta.app/Contents/Developer"
# Reuse the regression runner's real views and fake services, replacing only its entry point.
sources = []
for relative, wildcard in re.findall(r'"\$ROOT/([^"]+)"(\*\.swift)?',
                                     (ROOT / "Tools/OnboardingRegression/run.sh").read_text()):
    if wildcard:
        sources.extend(str(path) for path in sorted((ROOT / relative).glob(wildcard)))
    elif relative.endswith(".swift") and not relative.endswith("OnboardingTests.swift"):
        sources.append(str(ROOT / relative))
subprocess.run(["xcrun", "swiftc", "-parse-as-library", *sources, str(swift), "-o", str(BIN)], env=env, check=True)
subprocess.run([str(BIN), str(OUT)], env=env, check=True)
