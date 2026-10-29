import Foundation

@main
struct StatusBroadcastTests {
	@MainActor static func main() {
		var posts: [(String, [String: Any])] = []
		var enabled = false
		GazeStatusBroadcast.send = { posts.append(($0, $1)) }
		GazeStatusBroadcast.isEnabled = { enabled }

		func runAll() {
			GazeStatusBroadcast.resetForTesting()
			GazeStatusBroadcast.hello()
			GazeStatusBroadcast.screenLocked()
			GazeStatusBroadcast.scanStarted()
			for movement in GazeStatusBroadcast.Movement.allCases { GazeStatusBroadcast.challenge(movement) }
			GazeStatusBroadcast.notRecognised()
			GazeStatusBroadcast.spoofRejected()
			for reason in GazeStatusBroadcast.Reason.allCases { GazeStatusBroadcast.unavailable(reason) }
			GazeStatusBroadcast.recognised()
			GazeStatusBroadcast.postState()
			GazeStatusBroadcast.scanStopped()
			GazeStatusBroadcast.screenUnlocked(by: .gaze)
			GazeStatusBroadcast.appLockShown(bundleID: "com.example.App")
			GazeStatusBroadcast.appLockUnlocked(bundleID: "com.example.App")
			GazeStatusBroadcast.postState()
		}

		var failures = 0
		func expect(_ ok: Bool, _ what: String) {
			if !ok { failures += 1; print("FAIL: \(what)") }
		}

		runAll()
		expect(posts.isEmpty, "nothing posts while disabled")

		enabled = true
		runAll()
		let names = Set(posts.map(\.0))
		for event in GazeStatusBroadcast.Event.allCases {
			expect(names.contains(GazeStatusBroadcast.prefix + event.rawValue), "\(event) posted")
		}
		for (name, info) in posts {
			expect(name.hasPrefix("com.gazeunlock.Gaze.status."), "\(name) prefix")
			expect(Set(info.keys).isSubset(of: GazeStatusBroadcast.allowedKeys), "\(name) keys \(info.keys.sorted())")
			expect(info["version"] as? Int == 1, "\(name) version")
			expect(info["timestamp"] is Double, "\(name) timestamp")
			for (key, value) in info where key != "version" && key != "timestamp" {
				expect(value is String, "\(name).\(key) is a string")
			}
		}

		posts.removeAll()
		GazeStatusBroadcast.notRecognised()
		GazeStatusBroadcast.notRecognised()
		expect(posts.count == 1, "repeats are dropped")

		if failures > 0 { print("\(failures) failure(s)"); exit(1) }
		print("StatusBroadcast: all checks passed (\(GazeStatusBroadcast.Event.allCases.count) events)")
	}
}
