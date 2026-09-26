import AppKit
import SwiftUI

extension SettingsInteractionTests {
    static func checkCapture(output: URL) throws {
        for addingFace in [false, true] {
            let camera = CameraController()
            camera.state = .failed("Simulated unavailable camera")
            let model = EnrollmentModel()
            var retries = 0
            let step = SetupCaptureStep(position: addingFace ? nil : .init(index: 2, count: 5),
                camera: camera, model: model, onAuthorized: {}, onBack: addingFace ? nil : {},
                onRetry: { retries += 1; camera.state = .running })
            let host = NSHostingView(rootView: step.frame(width: 880, height: 660)
                .background(Theme.setupGround).preferredColorScheme(.dark)
                .transaction { $0.disablesAnimations = true })
            host.frame = CGRect(x: 0, y: 0, width: 880, height: 660)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Gaze Capture Recovery — Camera simulated"
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil; settle() }
            host.layoutSubtreeIfNeeded()
            settle()
            require(find("Try Again", in: host) != nil, "Camera failure must offer a direct retry")
            require((find("Back", in: host) == nil) == addingFace, "Add-face recovery cannot depend on a Back button")
            try snapshot(host, to: output.appendingPathComponent("capture-failed-\(addingFace ? "add-face" : "onboarding").png"))
            if CommandLine.arguments.contains("--inspect-capture") {
                let deadline = Date(timeIntervalSinceNow: 180)
                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        if camera.state == .running || Date() >= deadline {
                            NSApplication.shared.stop(nil)
                            NSApplication.shared.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
                        }
                    }
                }
                print("READY: Try Again in \(addingFace ? "Add a Face" : "onboarding") — camera simulated")
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.run()
                timer.invalidate()
            } else {
                press("Try Again", in: host)
            }
            require(retries == 1, "Retry action must invoke its callback once")
            require(find("Try Again", in: host) == nil, "Resumed capture must remove the failure action")
            camera.state = .failed("Simulated failure during saving")
            model.phase = .complete
            settle()
            require(find("Try Again", in: host) == nil, "Completed enrollment must not expose retry while it is saving")
            try snapshot(host, to: output.appendingPathComponent("capture-complete-\(addingFace ? "add-face" : "onboarding").png"))
        }
        print("PASS: actual capture presentation and retry callback for onboarding/add-face; camera and authorization simulated")
    }
}
