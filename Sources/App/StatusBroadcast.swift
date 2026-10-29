import Foundation

/// Gaze's opt-in public status feed, for apps like DynamicLake that draw their own island.
///
/// Every event is a distributed notification named `com.gazeunlock.Gaze.status.<event>`
/// with `object` nil and a `userInfo` of plain strings and numbers. Distributed
/// notifications are readable by any process on the Mac, so payloads say only what a
/// person looking at the screen could see: never names, faces, scores, paths or passwords,
/// and nothing about who failed. Documented for third parties in docs/status-notifications.md;
/// keys and values are a public contract, so changing them means bumping `version`.
///
/// Off unless `isEnabled` says otherwise. The app points it at `Preferences.broadcastStatus`
/// at launch; until then nothing is posted, not even `hello`.
@MainActor
enum GazeStatusBroadcast {

	static let prefix = "com.gazeunlock.Gaze.status."
	static let version = 1

	enum Event: String, CaseIterable {
		case hello, state
		case screenLocked, screenUnlocked
		case scanStarted, scanStopped
		case challenge, recognised, notRecognised, spoofRejected, unavailable
		case appLockShown, appLockUnlocked
	}

	/// The `phase` value of a `state` reply.
	enum Phase: String, CaseIterable {
		case idle, locked, scanning, challenge, recognised, notRecognised, spoofRejected, unavailable, appLocked
	}

	enum Movement: String, CaseIterable {
		case nod, turnLeft, turnRight, blink, openMouth, followLight
	}

	enum UnlockedBy: String { case gaze, other }

	/// Short codes for `unavailable`, never the user-facing sentence.
	enum Reason: String, CaseIterable {
		case paused, lockedOut, passwordChanged, cameraNotResponding, recognitionUnavailable, passwordEntryFailed, other
	}

	/// Every key a payload may carry. The test suite holds payloads to this list.
	static let allowedKeys: Set<String> = ["version", "timestamp", "by", "movement", "reason", "bundleID", "phase", "appVersion"]

	static var isEnabled: () -> Bool = { false }
	/// Replaced by tests; the app posts on the distributed centre.
	static var send: (_ name: String, _ userInfo: [String: Any]) -> Void = { name, userInfo in
		DistributedNotificationCenter.default().postNotificationName(
			.init(name), object: nil, userInfo: userInfo, deliverImmediately: true)
	}
	static var now: () -> Date = Date.init

	private static var phase: Phase = .idle
	private static var extras: [String: Any] = [:]
	private static var isScreenLocked = false
	private static var scanning = false
	private static var lastSignature: String?
	private static var requestObserver: NSObjectProtocol?

	/// Starts answering `request` and says hello. Called once at launch.
	static func start(isEnabled: @escaping () -> Bool) {
		self.isEnabled = isEnabled
		if requestObserver == nil {
			requestObserver = DistributedNotificationCenter.default().addObserver(
				forName: .init(prefix + "request"), object: nil, queue: .main
			) { _ in
				MainActor.assumeIsolated { postState() }
			}
		}
		hello()
	}

	static func hello() {
		let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
		emit(.hello, ["appVersion": appVersion])
	}

	/// Re-posts the current state so an app launched later can sync.
	static func postState() {
		var info = extras
		info["phase"] = phase.rawValue
		emit(.state, info)
	}

	// MARK: - Events

	static func screenLocked() {
		isScreenLocked = true
		scanning = false
		transition(.screenLocked, to: .locked)
	}

	static func screenUnlocked(by: UnlockedBy?) {
		isScreenLocked = false
		scanning = false
		var info: [String: Any] = [:]
		if let by { info["by"] = by.rawValue }
		transition(.screenUnlocked, info, to: .idle)
	}

	static func scanStarted() {
		guard !scanning else { return }
		scanning = true
		transition(.scanStarted, to: .scanning)
	}

	static func scanStopped() {
		guard scanning else { return }
		scanning = false
		transition(.scanStopped, to: isScreenLocked ? .locked : .idle)
	}

	static func challenge(_ movement: Movement) {
		scanStarted()
		transition(.challenge, ["movement": movement.rawValue], to: .challenge)
	}

	static func recognised() { transition(.recognised, to: .recognised) }
	static func notRecognised() { transition(.notRecognised, to: .notRecognised) }
	static func spoofRejected() { transition(.spoofRejected, to: .spoofRejected) }
	static func unavailable(_ reason: Reason) {
		transition(.unavailable, ["reason": reason.rawValue], to: .unavailable)
	}

	static func appLockShown(bundleID: String) {
		transition(.appLockShown, ["bundleID": bundleID], to: .appLocked)
	}

	static func appLockUnlocked(bundleID: String) {
		transition(.appLockUnlocked, ["bundleID": bundleID], to: isScreenLocked ? .locked : .idle)
	}

	// MARK: - Posting

	/// Records the new phase whether or not the feed is on, so `state` is right the moment
	/// it is switched on. Repeats of the same event and values are dropped: the capsule
	/// re-presents the same phase at frame rate during a scan.
	private static func transition(_ event: Event, _ info: [String: Any] = [:], to next: Phase) {
		phase = next
		extras = next == .idle || next == .locked || next == .scanning ? [:] : info
		let signature = event.rawValue + info.keys.sorted().map { "|\($0)=\(info[$0]!)" }.joined()
		guard signature != lastSignature else { return }
		lastSignature = signature
		emit(event, info)
	}

	private static func emit(_ event: Event, _ info: [String: Any]) {
		guard isEnabled() else { return }
		send(prefix + event.rawValue, payload(info))
	}

	static func payload(_ info: [String: Any]) -> [String: Any] {
		var out = info
		out["version"] = version
		out["timestamp"] = now().timeIntervalSince1970
		return out
	}

	/// Test hook: forgets all state.
	static func resetForTesting() {
		phase = .idle
		extras = [:]
		isScreenLocked = false
		scanning = false
		lastSignature = nil
	}
}
