import Foundation
import os

/// What Face ID is doing right now, published for other applications.
///
/// This exists so notch apps — Dynamic Lake, Atoll, anything else that owns that strip of
/// screen — can show Face ID's state in their own interface instead of ours drawing a second
/// panel over theirs. Aviorrok asked for exactly this: "I need to know the Face ID state,
/// detecting, failed, or succeeded, so I can integrate it easily in DynamicLake."
///
/// It is a one-way broadcast. Nothing here can start an unlock, read a faceprint, or reach
/// the password — a subscriber learns only what a person standing behind the Mac could see
/// by looking at the screen. That is deliberate: an integration point that can *cause* an
/// unlock would be a way to attack the app from another process.
public enum FaceIDState: String, Sendable {
	/// Nothing is happening. The Mac is unlocked, or Face ID is switched off.
	case idle
	/// The screen is locked and Face ID is available, but no face has been seen yet.
	case locked
	/// A face is in frame and being matched.
	case detecting
	/// Recognised. The unlock, if one was configured, is happening now.
	case succeeded
	/// Not recognised within the search window, or rejected by the liveness check.
	case failed
	/// Too many failures. Face ID is disabled until an account password is entered.
	case lockedOut
}

/// Posts `FaceIDState` changes on the distributed notification centre.
///
/// ## Subscribing
///
/// ```swift
/// DistributedNotificationCenter.default().addObserver(
///     forName: .init("app.faceid.FaceID.state"), object: nil, queue: .main
/// ) { note in
///     let state = note.object as? String          // "detecting", "succeeded", …
///     let score = note.userInfo?["score"] as? Double   // present on succeeded/failed
/// }
/// ```
///
/// The state also travels in `object` rather than only in `userInfo`, because `userInfo` is
/// the part of a distributed notification that gets dropped first — it is discarded outright
/// for sandboxed observers on some paths. A subscriber that reads `object` always gets the
/// state; `userInfo` carries the extras for anyone who can see it.
@MainActor
enum StateBroadcast {

	/// The notification name. Stable, and part of the public surface of this app — renaming
	/// it silently breaks every integration, so it changes only with a version bump.
	static let name = "app.faceid.FaceID.state"

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "StateBroadcast")

	private static var last: FaceIDState?

	/// Publishes a state, if it is different from the last one.
	///
	/// Deduplicated because the recognition loop runs at frame rate: posting `detecting` on
	/// every frame would put sixteen notifications a second through the distributed centre,
	/// which is a system-wide bus shared with every other application on the Mac.
	static func post(_ state: FaceIDState, score: Double? = nil) {
		guard state != last else { return }
		last = state

		var info: [AnyHashable: Any] = ["state": state.rawValue]
		if let score { info["score"] = score }

		DistributedNotificationCenter.default().postNotificationName(
			.init(name),
			object: state.rawValue,
			userInfo: info,
			deliverImmediately: true)

		logger.debug("State → \(state.rawValue, privacy: .public)")
	}

	/// Clears the deduplication so the next post always goes out.
	///
	/// Called when an attempt begins. Without it, two consecutive failed unlocks would
	/// publish `failed` once and a subscriber would show a stale result for the second.
	static func reset() {
		last = nil
	}
}
