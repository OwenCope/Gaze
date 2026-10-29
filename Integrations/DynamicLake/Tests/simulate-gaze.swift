// Posts Gaze's status notifications the way Gaze does, for testing the plugin without Gaze.
// Usage: swift simulate-gaze.swift [bundleID]
import Foundation

let center = DistributedNotificationCenter.default()
func post(_ event: String, _ extra: [String: Any] = [:], wait: Double = 1) {
	var info: [String: Any] = ["version": 1, "timestamp": Date().timeIntervalSince1970]
	info.merge(extra) { $1 }
	center.postNotificationName(.init("com.gazeunlock.Gaze.status." + event), object: nil,
	                            userInfo: info, deliverImmediately: true)
	print("posted", event, extra)
	Thread.sleep(forTimeInterval: wait)
}

let app = CommandLine.arguments.dropFirst().first ?? "com.apple.Notes"
post("screenLocked")
post("scanStarted")
post("challenge", ["movement": "nod"])
post("challenge", ["movement": "followLight"])
post("recognised", wait: 0.3)
post("screenUnlocked", ["by": "gaze"])
post("scanStopped", wait: 2)
post("scanStarted")
post("notRecognised", wait: 3)
post("appLockShown", ["bundleID": app], wait: 2)
post("appLockUnlocked", ["bundleID": app])
