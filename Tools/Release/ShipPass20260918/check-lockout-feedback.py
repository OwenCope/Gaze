#!/usr/bin/env python3
"""Exercise the actual lockout row and handler with an in-memory password verifier."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/gaze-ship-20260918/lockout-fixture"
OUT.mkdir(parents=True, exist_ok=True)
source = (ROOT / "Sources/App/SettingsView.swift").read_text()


def member(anchor):
    start = source.index("\t" + anchor)
    end = source.index("\n\t}", start) + len("\n\t}")
    return source[start:end]


members = [member("private var lockoutSection:"), member("private func clearLockout()")]
fixture = r'''
import AppKit
import SwiftUI

@MainActor enum PasswordVault {
    static var attempts = 0
    static func verify(_ value: String) -> Bool {
        attempts += 1
        return value == "fixture-correct"
    }
}
@MainActor final class LockoutManager {
    static let maxAttempts = 6
    var cleared = 0
    func clearAfterPasswordAuth() { cleared += 1 }
}
@MainActor final class Driver {
    var enter: ((String) -> Void)?
    var submit: (() -> Void)?
    var read: (() -> (String?, String))?
}
struct LockoutFixture: View {
    let lockout: LockoutManager
    let driver: Driver
    @State private var lockoutPassword = ""
    @State private var lockoutError: String?
    var body: some View {
        lockoutSection.padding(24).frame(width: 620, height: 240)
            .onAppear {
                driver.enter = { lockoutPassword = $0 }
                driver.submit = clearLockout
                driver.read = { (lockoutError, lockoutPassword) }
            }
    }
''' + "\n".join(members) + r'''
}
@main @MainActor struct Check {
    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let driver = Driver()
        let lockout = LockoutManager()
        let host = NSHostingView(rootView: LockoutFixture(lockout: lockout, driver: driver))
        host.frame = CGRect(x: 0, y: 0, width: 620, height: 240)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Gaze validation fixture — fake credentials"
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        settle()
        precondition(driver.enter != nil && driver.submit != nil && driver.read != nil)
        driver.enter!("fixture-wrong")
        settle()
        driver.submit!()
        settle()
        precondition(driver.read!().0 == "That password didn’t match. Try again.", "Failure must survive clearing the field")
        precondition(driver.read!().1.isEmpty)
        precondition(lockout.cleared == 0 && PasswordVault.attempts == 1)
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        driver.enter!("fixture-correct")
        settle()
        precondition(driver.read!().0 == nil, "New typing clears the stale error")
        driver.submit!()
        settle()
        precondition(driver.read!().0 == nil && driver.read!().1.isEmpty)
        precondition(lockout.cleared == 1 && PasswordVault.attempts == 2)
        print("PASS: wrong-password message persists, retry clears it, only verified input clears lockout; all credentials and services are fake")
    }
}
'''
swift = OUT / "LockoutFixture.swift"
swift.write_text(fixture)
(OUT / "source.json").write_text(json.dumps({
    "source": "Sources/App/SettingsView.swift",
    "sha256": hashlib.sha256(source.encode()).hexdigest(),
    "members": ["lockoutSection", "clearLockout"],
    "services": "In-memory verifier and lockout counter only; no Keychain or OS authentication",
}, indent=2) + "\n")
env = os.environ.copy()
env["DEVELOPER_DIR"] = "/Applications/Xcode-beta.app/Contents/Developer"
binary = OUT / "LockoutFixture"
subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(ROOT / "Sources/App/Theme.swift"),
                str(swift), "-o", str(binary)], env=env, check=True)
subprocess.run([str(binary), str(OUT / "failure.png")], env=env, check=True)
