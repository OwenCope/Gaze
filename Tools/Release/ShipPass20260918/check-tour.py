#!/usr/bin/env python3
"""Run the actual Gaze welcome tour with inert completion callbacks."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/gaze-ship-20260918/tour-interaction"
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
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        var completed = 0
        var closed = 0
        let host = NSHostingView(rootView: GazeWelcomeTour(onContinue: { completed += 1 }, onClose: { closed += 1 })
            .background(Color(white: 0.06)).preferredColorScheme(.dark)
            .transaction { $0.disablesAnimations = true })
        host.frame = CGRect(x: 0, y: 0, width: 880, height: 660)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Gaze Tour Fixture — no camera or credentials"
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        settle()
        precondition(button("Previous page", host: host) == nil, "First-page Back must be absent from accessibility")
        precondition(button("Close introduction", host: host) != nil)
        try capture(host, path: CommandLine.arguments[1] + "/step-1.png")
        press("Continue", host: host)
        precondition(button("Previous page", host: host) != nil)
        precondition(completed == 0 && closed == 0)
        try capture(host, path: CommandLine.arguments[1] + "/step-2.png")
        press("Previous page", host: host)
        precondition(button("Previous page", host: host) == nil)
        press("Continue", host: host)
        press("Continue", host: host)
        precondition(button("Practice movements", host: host) != nil)
        try capture(host, path: CommandLine.arguments[1] + "/step-3.png")
        press("Practice movements", host: host)
        precondition(completed == 1 && closed == 0)
        press("Close introduction", host: host)
        precondition(completed == 1 && closed == 1)
        print("PASS: actual welcome tour next/back/final/close controls, hidden first-page Back, animation-disabled snapshots, and inert callbacks")
    }
}
''')
env = os.environ.copy()
env["DEVELOPER_DIR"] = "/Applications/Xcode-beta.app/Contents/Developer"
subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(ROOT / "ThirdParty/TourKit/TourKit.swift"),
                str(ROOT / "Sources/Setup/GazeWelcomeTour.swift"), str(swift), "-o", str(BIN)], env=env, check=True)
subprocess.run([str(BIN), str(OUT)], env=env, check=True)
