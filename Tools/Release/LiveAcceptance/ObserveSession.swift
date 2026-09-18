import AppKit
import CoreGraphics

@main
@MainActor
struct ObserveSession {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let seconds = TimeInterval(CommandLine.arguments[2]), seconds > 0 else {
            throw NSError(domain: "GazeAcceptance", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Usage: ObserveSession OUTPUT.jsonl SECONDS"])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw NSError(domain: "GazeAcceptance", code: 2)
        }
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func record(_ event: String) {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
            let data: [String: Any] = [
                "time": formatter.string(from: Date()), "event": event,
                "screenLocked": session["CGSSessionScreenIsLocked"] as? Bool as Any? ?? NSNull(),
                "onConsole": session[kCGSessionOnConsoleKey as String] as? Bool as Any? ?? NSNull(),
                "loginDone": session[kCGSessionLoginDoneKey as String] as? Bool as Any? ?? NSNull(),
                "ownerMatches": (session[kCGSessionUserIDKey as String] as? UInt32) == geteuid()
            ]
            do {
                var line = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
                line.append(0x0A)
                try file.write(contentsOf: line)
                try file.synchronize()
                print(String(decoding: line, as: UTF8.self), terminator: "")
                fflush(stdout)
            } catch {
                fputs("Could not record session observation: \(error)\n", stderr)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification
        ]
        var tokens = notifications.map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { record(note.name.rawValue) }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        let lockTokens = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map { name in
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { note in
                MainActor.assumeIsolated { record(note.name.rawValue) }
            }
        }
        record("observerStarted")
        let deadline = Date().addingTimeInterval(seconds)
        RunLoop.main.run(until: deadline)
        record("observerFinished")
        for token in tokens { workspace.removeObserver(token) }
        tokens.removeAll()
        for token in lockTokens { distributed.removeObserver(token) }
    }
}
