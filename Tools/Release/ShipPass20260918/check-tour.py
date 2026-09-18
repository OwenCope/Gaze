#!/usr/bin/env python3
"""Run the actual Gaze welcome tour with inert completion callbacks."""
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/gaze-ship-20260918/compact-tour-interaction"
APP = OUT / "Tour Fixture.app"
BIN = APP / "Contents/MacOS/TourFixture"
BIN.parent.mkdir(parents=True, exist_ok=True)
resources = APP / "Contents/Resources/Art"
resources.mkdir(parents=True, exist_ok=True)
for name in ("tour-recognition.png", "tour-privacy.png", "tour-practice.png"):
    shutil.copyfile(ROOT / "Resources/Art" / name, resources / name)
with (APP / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleIdentifier": "local.gaze.tour-validation", "CFBundleExecutable": "TourFixture",
                   "CFBundleName": "Gaze Tour Fixture", "CFBundlePackageType": "APPL"}, stream)
swift = OUT / "TourFixture.swift"
swift.write_text(r'''
import AppKit
import SwiftUI

@main @MainActor struct TourFixture {
    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
    static func attribute(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    static func booleanAttribute(_ object: NSObject, _ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    static func nodes(_ root: NSObject) -> [NSObject] {
        var output: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 60, seen.insert(ObjectIdentifier(object)).inserted else { return }
            output.append(object)
            for child in attribute(object, "accessibilityChildren") as? [NSObject] ?? [] {
                walk(child, depth: depth + 1)
            }
            if let view = object as? NSView {
                for child in view.subviews { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return output
    }
    static func label(_ object: NSObject) -> String {
        for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let value = attribute(object, key) as? String, !value.isEmpty { return value }
        }
        if let title = attribute(object, "accessibilityTitleUIElement") as? NSObject {
            return attribute(title, "accessibilityValue") as? String ?? ""
        }
        return ""
    }
    static func button(_ title: String, host: NSView) -> NSObject? {
        nodes(host).first { label($0) == title && (attribute($0, "accessibilityRole") as? String) == "AXButton" }
    }
    static func press(_ title: String, host: NSView) {
        guard let object = button(title, host: host) else {
            print(nodes(host).map(label))
            preconditionFailure("Missing button: \(title)")
        }
        if object.accessibilityActionNames().contains(.press) {
            object.accessibilityPerformAction(.press)
        } else {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            precondition(object.responds(to: selector))
            typealias Action = @convention(c) (AnyObject, Selector) -> Bool
            let action = unsafeBitCast(object.method(for: selector), to: Action.self)
            precondition(action(object, selector))
        }
        settle()
    }
    static func capture(_ host: NSView, path: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // AppKit's cached display omits Metal layers; composite the actual renderer output.
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        for surface in CompanionCapture.surfaces(in: host) {
            guard let gpu = surface.renderer.gpu, let sample = surface.renderer.pose else { throw SoftFaceError.unavailable }
            var rect = surface.view.convert(surface.view.bounds, to: host)
            if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
            let image = try CompanionCapture.frame(gpu: gpu, pose: sample(Date.timeIntervalSinceReferenceDate),
                size: CGSize(width: rect.width * scale, height: rect.height * scale),
                material: surface.renderer.material, opacity: surface.renderer.opacity)
            image.draw(in: rect)
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    static func checkPage(_ index: Int, host: NSView) {
        let labels = nodes(host).map(label)
        precondition(labels.filter { $0 == "Page \(index + 1) of 9" }.count == 1, "One shared progress indicator")
        for title in ["Practice movements", "Continue Setup", "Next", "Previous", "Close introduction"] {
            precondition(button(title, host: host) == nil, "No nested walkthrough controls: \(title)")
        }
        let action = index == 8 ? "Continue setup" : "Continue"
        precondition(nodes(host).filter { label($0) == action && (attribute($0, "accessibilityRole") as? String) == "AXButton" }.count == 1)
    }
    static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        var completed = 0
        var closed = 0
        var savedPage = 0
        let host = NSHostingView(rootView: GazeWelcomeTour(onContinue: { completed += 1 }, onClose: { closed += 1 },
            onPageChange: { savedPage = $0 })
            .background(Color(white: 0.06)).preferredColorScheme(.dark)
            .transaction { $0.disablesAnimations = true })
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Gaze Tour Fixture — no camera or credentials"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        settle()
        precondition(button("Previous page", host: host) == nil, "First-page Back must be absent from accessibility")
        precondition(button("Close introduction", host: host) == nil, "The host window owns closing; no duplicate close button")
        checkPage(0, host: host)
        try capture(host, path: CommandLine.arguments[1] + "/step-1.png")
        press("Continue", host: host)
        precondition(button("Previous page", host: host) != nil)
        precondition(completed == 0 && closed == 0)
        try capture(host, path: CommandLine.arguments[1] + "/step-2.png")
        press("Previous page", host: host)
        precondition(button("Previous page", host: host) == nil)
        press("Continue", host: host)
        press("Continue", host: host)
        let titles = ["Looking for you", "Turn left", "Turn right", "Nod", "Blink", "Open mouth"]
        for index in 2...7 {
            checkPage(index, host: host)
            precondition(savedPage == index && completed == 0 && closed == 0)
            precondition(nodes(host).map(label).contains(titles[index - 2]))
            precondition(nodes(host).map(label).contains("Just a demonstration · Camera off"))
            precondition(CompanionCapture.surfaces(in: host).count == 1, "Only the current movement owns a renderer")
            press("Pause", host: host)
            precondition(button("Play", host: host) != nil)
            press("Play", host: host)
            if index == 3 {
                press("Previous page", host: host)
                checkPage(2, host: host)
                press("Continue", host: host)
                checkPage(3, host: host)
            }
            try capture(host, path: CommandLine.arguments[1] + "/step-\(index + 1).png")
            press("Continue", host: host)
        }
        checkPage(8, host: host)
        precondition(savedPage == 8)
        try capture(host, path: CommandLine.arguments[1] + "/step-9.png")
        press("Continue setup", host: host)
        precondition(completed == 1 && closed == 0)

        // SetupFlow restores this index when Back leaves capture, then resets it on a fresh run.
        let returned = NSHostingView(rootView: GazeWelcomeTour(onContinue: {}, onClose: {}, initialPageIndex: savedPage))
        returned.frame = host.frame
        window.contentView = returned
        settle()
        checkPage(8, host: returned)
        press("Previous page", host: returned)
        checkPage(7, host: returned)

        do {
            let reduced = NSHostingView(rootView: GazeWelcomeTour(onContinue: {}, onClose: {}, movementCount: 1, initialPageIndex: 2)
                .environment(\.notchReduceMotion, true)
                .preferredColorScheme(.dark))
            reduced.frame = host.frame
            window.contentView = reduced
            settle()
            checkPage(2, host: reduced)
            let labels = nodes(reduced).map(label)
            precondition(labels.contains("Reduce Motion is on · Camera off"))
            precondition(labels.contains { $0.contains("one short movement") })
            let pause = button("Pause", host: reduced)!
            precondition(booleanAttribute(pause, "isAccessibilityEnabled") == false, "Reduce Motion disables playback control")
            try capture(reduced, path: CommandLine.arguments[1] + "/reduced-motion.png")
        }
        window.performClose(nil)
        settle()
        precondition(!window.isVisible, "The native window close control must dismiss the tour")
        precondition(completed == 1 && closed == 0, "Native close does not invoke a removed in-content close button")
        print("PASS: nine-page integrated movement tour at 640x520, single navigation/progress, pause/play, Back, saved page restoration, one-movement copy, app Reduce Motion setting, native window close and inert callbacks; system Reduce Motion and raw Escape injection are not covered")
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
