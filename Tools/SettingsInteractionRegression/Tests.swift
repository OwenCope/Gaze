import AppKit
import SwiftUI

@main @MainActor
struct SettingsInteractionTests {
    static var checks = 0
    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        checks += 1
    }

    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }

    static func attribute(_ node: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard node.responds(to: selector) else { return nil }
        return node.perform(selector)?.takeUnretainedValue()
    }

    // SwiftUI accessibility nodes implement the Objective-C selectors without adopting
    // the full NSAccessibilityProtocol. Use their documented selector signatures.
    static func boolean(_ node: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard node.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let call = unsafeBitCast(node.method(for: selector), to: Getter.self)
        return call(node, selector)
    }

    static func nodes(_ root: Any) -> [NSObject] {
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, depth: Int) {
            guard depth < 60, let element = object as? NSObject else { return }
            guard seen.insert(ObjectIdentifier(element)).inserted else { return }
            result.append(element)
            for child in attribute(element, "accessibilityChildren") as? [Any] ?? [] {
                visit(child, depth: depth + 1)
            }
            if let view = element as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return result
    }

    static func label(_ node: NSObject) -> String {
        for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let value = attribute(node, key) as? String, !value.isEmpty { return value }
        }
        if let title = attribute(node, "accessibilityTitleUIElement") as? NSObject, title !== node {
            return attribute(title, "accessibilityValue") as? String
                ?? attribute(title, "accessibilityLabel") as? String ?? ""
        }
        return ""
    }

    static func find(_ text: String, in host: NSView) -> NSObject? {
        nodes(host).first { label($0) == text }
    }

    static func press(_ text: String, in host: NSView) {
        let roles = ["AXButton", "AXCheckBox", "AXSwitch", "AXDisclosureTriangle", "AXRadioButton"]
        guard let control = nodes(host).first(where: {
            label($0) == text && roles.contains(attribute($0, "accessibilityRole") as? String ?? "")
        }) else {
            print(nodes(host).map { [String(describing: attribute($0, "accessibilityRole")), label($0)] })
            fputs("FAIL: Missing control: \(text)\n", stderr)
            exit(1)
        }
        let actions = control.accessibilityActionNames()
        if actions.contains(.press) {
            control.accessibilityPerformAction(.press)
            checks += 1
        } else {
            let accepted = boolean(control, "accessibilityPerformPress")
            if !accepted {
                print("Unavailable press", text, type(of: control), actions, control.accessibilityAttributeNames())
            }
            require(accepted, "Control must accept an accessibility press: \(text)")
        }
        settle()
    }

    static func expandNotes(in host: NSView) -> Bool {
        guard CommandLine.arguments.contains("--inspect-notes") else {
            print("SKIP: release-note expansion requires --inspect-notes and a click on the disclosure arrow")
            return false
        }
        let deadline = Date(timeIntervalSinceNow: 180)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if nodes(host).map(label).joined().contains("Literal <script> text stays text.") || Date() >= deadline {
                    NSApplication.shared.stop(nil)
                    NSApplication.shared.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
                }
            }
        }
        print("READY: expand Release Notes in the simulated Settings fixture")
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
        timer.invalidate()
        return true
    }

    static func snapshot(_ host: NSView, to url: URL) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    static func withPanel(_ section: SettingsFixture.Section, scheme: ColorScheme = .dark,
                          body: (NSView, FixtureDriver) throws -> Void) rethrows {
        let driver = FixtureDriver()
        let host = NSHostingView(rootView: SettingsFixture(section: section, driver: driver).preferredColorScheme(scheme))
        host.frame = CGRect(x: 0, y: 0, width: 668, height: 660)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Gaze Settings Fixture — Simulated services"
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; settle() }
        host.layoutSubtreeIfNeeded()
        settle()
        try body(host, driver)
    }

    static func main() throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try withPanel(.behaviour) { host, driver in
            require(LoginItem.requests.isEmpty, "Opening Settings must never register Gaze")
            require(find("Open Login Items", in: host) == nil, "No approval button before a failure or pending state")
            LoginItem.failNext = true
            press("Open at login", in: host)
            require(LoginItem.requests == [true], "One click must request one registration")
            require(LoginItem.status == .disabled, "A failed request must leave service state unchanged")
            require(find("Open at login couldn’t be changed", in: host) != nil, "Failure must remain visible")
            try snapshot(host, to: output.appendingPathComponent("login-failed-dark.png"))
            press("Open Login Items", in: host)
            require(SMAppService.openCount == 1, "System Settings opens only when requested")
            LoginItem.approvalNext = true
            press("Open at login", in: host)
            require(LoginItem.requests == [true, true], "Failed registration must remain retryable")
            require(find("Approval needed", in: host) != nil, "Pending registration needs approval feedback")
            require(find("Open at login couldn’t be changed", in: host) == nil, "Successful retry clears the error")
            try snapshot(host, to: output.appendingPathComponent("login-pending-dark.png"))
            press("Open at login", in: host)
            require(LoginItem.requests.last == false, "The pending switch must turn off on the next click")
            require(LoginItem.status == .disabled, "Pending registration can be cancelled")
            LoginItem.status = .enabled
            driver.refresh?()
            settle()
            require(find("Open Login Items", in: host) == nil, "An externally approved service needs no repair button")
            press("Open at login", in: host)
            require(LoginItem.requests.last == false, "Refreshing external state must update the switch")
        }
        for requested in [true, false] {
            LoginItem.status = requested ? .disabled : .enabled
            LoginItem.failNext = true
            try withPanel(.behaviour) { host, driver in
                press("Open at login", in: host)
                require(find("Open at login couldn’t be changed", in: host) != nil, "Failed changes must show feedback")
                driver.refresh?()
                settle()
                require(find("Open at login couldn’t be changed", in: host) != nil, "An unresolved failure must survive a refresh")
                LoginItem.status = requested ? .enabled : .disabled
                driver.refresh?()
                settle()
                try snapshot(host, to: output.appendingPathComponent("login-external-repair-\(requested ? "enable" : "disable").png"))
                require(find("Open at login couldn’t be changed", in: host) == nil,
                    "A matching external repair must clear the old failure message")
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            UpdateChecker.shared.repositoryURL = nil
            ReleaseUpdateChecker.shared.state = .idle
            try withPanel(.updates, scheme: scheme) { host, _ in
                require(find("Open Source Folder", in: host) == nil, "Installed apps must not show a disabled source-folder button")
                press("Check", in: host)
                require(ReleaseUpdateChecker.shared.state == .upToDate, "The Check button reaches the existing checker action")
                ReleaseUpdateChecker.shared.state = .checking
                settle()
                require(find("Checking…", in: host).map { !boolean($0, "isAccessibilityEnabled") } == true, "Checking disables the action")
                ReleaseUpdateChecker.shared.state = .available(.init(tag: "1.3.0", name: "A useful update", notes: " \n\t"))
                settle()
                require(find("Release Notes", in: host) == nil, "Whitespace-only notes must not create an empty disclosure")
                ReleaseUpdateChecker.shared.state = .available(.init(tag: "1.3.0", name: "A useful update", notes: "Improved setup recovery.\n\nLiteral <script> text stays text."))
                settle()
                let expanded = expandNotes(in: host)
                if expanded {
                    let values = nodes(host).map(label).joined(separator: "\n")
                    require(values.contains("Literal <script> text stays text."), "Release notes must display literal plain text")
                }
                let count = ReleaseUpdateChecker.shared.downloadCount
                press("Download", in: host)
                require(ReleaseUpdateChecker.shared.downloadCount == count + 1, "Download delegates once to the existing action")
                try snapshot(host, to: output.appendingPathComponent("updates-\(expanded ? "notes" : "collapsed")-\(scheme == .dark ? "dark" : "light").png"))
                UpdateChecker.shared.repositoryURL = URL(fileURLWithPath: "/fixture/Gaze")
                settle()
                press("Open Source Folder", in: host)
                require(UpdateChecker.shared.revealCount > 0, "Source builds retain their folder action")
            }
        }
        try checkCapture(output: output)
        let results: [String: Any] = ["checks": checks, "passed": true,
            "releaseDisclosureDriven": CommandLine.arguments.contains("--inspect-notes"),
            "captureRetryDriven": CommandLine.arguments.contains("--inspect-capture"),
            "services": "simulated", "recordedUTC": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("results.json"))
        print("PASS: \(checks) Settings/capture interaction checks using actual panels and handlers; all services simulated")
    }
}
