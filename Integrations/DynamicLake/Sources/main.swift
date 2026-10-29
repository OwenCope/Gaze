// Gaze for DynamicLake: mirrors Gaze's status feed (docs/status-notifications.md)
// into DynamicLake's island over the JSON plugin protocol. No network, no storage.

import AppKit
import Foundation

signal(SIGPIPE, SIG_IGN)

// MARK: Socket

guard let socketPath = ProcessInfo.processInfo.environment["DYNAMICLAKE_JSON_SOCKET"] else {
	FileHandle.standardError.write("DYNAMICLAKE_JSON_SOCKET is not set\n".data(using: .utf8)!)
	exit(1)
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { exit(1) }
withUnsafeMutableBytes(of: &address.sun_path) { raw in
	raw.copyBytes(from: pathBytes)
}
let connected = withUnsafePointer(to: &address) {
	$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
		connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
	}
}
guard connected == 0 else { exit(1) }

func writeAll(_ data: Data) -> Bool {
	data.withUnsafeBytes { raw in
		var offset = 0
		while offset < raw.count {
			let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
			if n <= 0 { return false }
			offset += n
		}
		return true
	}
}

func send(_ message: [String: Any]) {
	var message = message
	message["schemaVersion"] = 1
	guard let json = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
		json.count <= 64 * 1024 else { return }
	var length = UInt32(json.count).bigEndian
	var frame = Data(bytes: &length, count: 4)
	frame.append(json)
	if !writeAll(frame) { exit(0) }
}

func readExactly(_ count: Int) -> Data? {
	var buffer = [UInt8](repeating: 0, count: count)
	var offset = 0
	while offset < count {
		let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress! + offset, count - offset) }
		if n <= 0 { return nil }
		offset += n
	}
	return Data(buffer)
}

// DynamicLake removes our activities when we disconnect, so leaving when it closes the socket is enough.
// Responses, errors and action callbacks need no handling: there are no buttons.
Thread.detachNewThread {
	while let header = readExactly(4) {
		let length = header.reduce(0) { Int($0) << 8 | Int($1) }
		guard length <= 64 * 1024, readExactly(length) != nil else { break }
	}
	exit(0)
}

// MARK: Settings

let environment = ProcessInfo.processInfo.environment
let features = Set((environment["DYNAMICLAKE_PLUGIN_FEATURES"] ?? "").split(separator: ",").map(String.init))
let canPresentSneakPeek = features.contains("presentSneakPeek")

func boolValue(_ value: Any?) -> Bool? {
	switch value {
	case let b as Bool: return b
	case let n as NSNumber: return n.boolValue
	case let s as String: return ["true", "1", "yes", "on"].contains(s.lowercased()) ? true
		: ["false", "0", "no", "off"].contains(s.lowercased()) ? false : nil
	default: return nil
	}
}

/// Reads a switch setting. The settings file is reread every time so changes apply live;
/// it is tiny and only read on Gaze events.
func setting(_ id: String, default fallback: Bool) -> Bool {
	func lookup(_ object: Any?) -> Bool? {
		guard let dict = object as? [String: Any] else { return nil }
		if let value = boolValue(dict[id]) { return value }
		return lookup(dict["settings"]) ?? lookup(dict["values"])
	}
	if let path = environment["DYNAMICLAKE_PLUGIN_SETTINGS_PATH"],
		let data = FileManager.default.contents(atPath: path),
		let value = lookup(try? JSONSerialization.jsonObject(with: data)) {
		return value
	}
	if let json = environment["DYNAMICLAKE_PLUGIN_SETTINGS_JSON"]?.data(using: .utf8),
		let value = lookup(try? JSONSerialization.jsonObject(with: json)) {
		return value
	}
	return boolValue(environment["DYNAMICLAKE_SETTING_\(id)"]) ?? fallback
}

// MARK: Activities

let unlockID = "gaze.unlock"
var shown = Set<String>()
var pendingDismiss: DispatchWorkItem?

func symbol(_ name: String, _ tint: String? = nil) -> [String: Any] {
	var c: [String: Any] = ["type": "image", "source": "sfSymbol", "systemImage": name]
	if let tint { c["tint"] = tint }
	return c
}

func text(_ value: String, _ tint: String? = nil) -> [String: Any] {
	var c: [String: Any] = ["type": "text", "text": value]
	if let tint { c["tint"] = tint }
	return c
}

func status(_ value: String, _ tint: String? = nil) -> [String: Any] {
	var c: [String: Any] = ["type": "status", "status": value]
	if let tint { c["tint"] = tint }
	return c
}

/// Compact slots hold only an icon and a status (DynamicLake asks for no descriptive text there);
/// the words go in the sneak peek.
func show(_ id: String, compactRight: [String: Any], label: String, tint: String?,
          priority: String = "normal", peek: Bool, leftSymbol: String = "faceid") {
	pendingDismiss?.cancel()
	pendingDismiss = nil
	var message: [String: Any] = [
		"activityID": id,
		"surfaces": [
			"compactLiveActivity": ["leftSlot": symbol(leftSymbol, tint), "rightSlot": compactRight],
			"sneakPeek": ["leftSlot": symbol(leftSymbol, tint), "center": text(label), "rightSlot": compactRight],
		],
	]
	if peek && canPresentSneakPeek { message["presentSneakPeek"] = 2 }
	if shown.contains(id) {
		message["type"] = "update"
	} else {
		message["type"] = "create"
		message["title"] = "Gaze"
		message["priority"] = priority
		message["size"] = "normal"
		shown.insert(id)
	}
	send(message)
}

func dismiss(_ id: String) {
	if id == unlockID { pendingDismiss?.cancel(); pendingDismiss = nil }
	guard shown.remove(id) != nil else { return }
	send(["type": "dismiss", "activityID": id])
}

func dismissUnlock(after seconds: Double) {
	pendingDismiss?.cancel()
	let work = DispatchWorkItem { dismiss(unlockID) }
	pendingDismiss = work
	DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
}

func movementWords(_ movement: String?) -> String {
	switch movement {
	case "nod": return "Nod"
	case "turnLeft": return "Turn left"
	case "turnRight": return "Turn right"
	case "blink": return "Blink"
	case "openMouth": return "Open your mouth"
	case "followLight": return "Follow the light"
	default: return "Move your head"
	}
}

func appLockID(_ bundleID: String) -> String {
	let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
	return "gaze.applock." + String(bundleID.filter { allowed.contains($0) }.prefix(100))
}

func appName(_ bundleID: String) -> String {
	if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
		let bundle = Bundle(url: url) {
		let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
		if let name, !name.isEmpty { return name }
		return url.deletingPathExtension().lastPathComponent
	}
	return "This app"
}

// MARK: Gaze feed

func handle(_ event: String, _ info: [AnyHashable: Any]) {
	switch event {
	case "scanStarted":
		show(unlockID, compactRight: ["type": "progress"], label: "Looking…", tint: nil, peek: false)
	case "challenge":
		guard setting("showMovementPrompts", default: true) else { return }
		show(unlockID, compactRight: ["type": "progress"], label: movementWords(info["movement"] as? String),
		     tint: "blue", priority: "high", peek: true)
	case "recognised":
		show(unlockID, compactRight: status("success", "green"), label: "Unlocked", tint: "green", peek: true)
		dismissUnlock(after: 1.5)
	case "notRecognised":
		show(unlockID, compactRight: status("failed", "orange"), label: "Not recognised", tint: "orange", peek: true)
		dismissUnlock(after: 2.5)
	case "spoofRejected":
		show(unlockID, compactRight: status("failed", "red"), label: "Face rejected", tint: "red", peek: true)
		dismissUnlock(after: 2.5)
	case "unavailable":
		show(unlockID, compactRight: status("warning", "yellow"), label: "Gaze can't check right now",
		     tint: "yellow", peek: true)
		dismissUnlock(after: 3)
	case "screenUnlocked":
		if info["by"] as? String == "gaze" {
			// "recognised" usually came first and already shows Unlocked; keep its timer.
			if pendingDismiss == nil {
				show(unlockID, compactRight: status("success", "green"), label: "Unlocked", tint: "green", peek: true)
				dismissUnlock(after: 1.5)
			}
		} else {
			dismiss(unlockID)
		}
	case "scanStopped":
		// Let a result (Unlocked, Not recognised) finish showing.
		if pendingDismiss == nil { dismiss(unlockID) }
	case "appLockShown":
		guard let bundleID = info["bundleID"] as? String, setting("showAppLock", default: true) else { return }
		show(appLockID(bundleID), compactRight: symbol("lock.fill"), label: "\(appName(bundleID)) is locked",
		     tint: nil, priority: "low", peek: false, leftSymbol: "lock.fill")
	case "appLockUnlocked":
		guard let bundleID = info["bundleID"] as? String else { return }
		dismiss(appLockID(bundleID))
	case "state":
		// Sync on start: only an in-progress scan or a locked app is worth showing late.
		switch info["phase"] as? String {
		case "scanning": handle("scanStarted", info)
		case "challenge": handle("challenge", info)
		case "appLocked": handle("appLockShown", info)
		default: break
		}
	default:
		break // hello, screenLocked and future events need nothing.
	}
}

let prefix = "com.gazeunlock.Gaze.status."
let center = DistributedNotificationCenter.default()
for event in ["hello", "state", "screenLocked", "screenUnlocked", "scanStarted", "scanStopped", "challenge",
              "recognised", "notRecognised", "spoofRejected", "unavailable", "appLockShown", "appLockUnlocked"] {
	center.addObserver(forName: .init(prefix + event), object: nil, queue: .main) { note in
		handle(event, note.userInfo ?? [:])
	}
}
// If Gaze isn't running or sharing is off, nothing answers and the island stays empty.
center.postNotificationName(.init(prefix + "request"), object: nil, userInfo: nil, deliverImmediately: true)

RunLoop.main.run()
