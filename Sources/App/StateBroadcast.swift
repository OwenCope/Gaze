import Foundation
import os

/// What Gaze is doing right now, published for other applications.
///
/// This exists so notch apps — Dynamic Lake, Atoll, anything else that owns that strip of
/// screen — can show Gaze's state in their own interface instead of ours drawing a second
/// panel over theirs. Aviorrok asked for exactly this: "I need to know the Gaze state,
/// detecting, failed, or succeeded, so I can integrate it easily in DynamicLake."
///
/// It is a one-way broadcast. Nothing here can start an unlock, read a faceprint, or reach
/// the password — a subscriber learns only what a person standing behind the Mac could see
/// by looking at the screen. That is deliberate: an integration point that can *cause* an
/// unlock would be a way to attack the app from another process.
public enum GazeState: String, Sendable {
	/// Nothing is happening. The Mac is unlocked, or Gaze is switched off.
	case idle
	/// The screen is locked and Gaze is available, but no face has been seen yet.
	case locked
	/// A face is in frame and being matched.
	case detecting
	/// Recognised. The unlock, if one was configured, is happening now.
	case succeeded
	/// Not recognised within the search window, or rejected by the anti-spoof check or the movement prompt.
	case failed
	/// Too many failures. Gaze is disabled until an account password is entered.
	case lockedOut
}

/// Posts `GazeState` changes on the distributed notification centre.
///
/// ## Subscribing
///
/// ```swift
/// DistributedNotificationCenter.default().addObserver(
///     forName: .init("com.gazeunlock.Gaze.state"), object: nil, queue: .main
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
	static let name = "com.gazeunlock.Gaze.state"

	/// The name this used to post under, still posted alongside the new one.
	///
	/// The app was called Face ID and published `app.faceid.FaceID.state`; anyone already
	/// subscribed would have gone quiet with no error and no way to tell a rename from the
	/// app simply not running. Both names go out until v0.2, by which point every
	/// integration has had a release to move.
	///
	/// 2026-09-22: keep posting both names for now so existing subscribers don't break
	/// silently. Decide keep vs. removal in the v0.2 release notes, not here; the
	/// `com.gazeunlock.Gaze.state` post below stays post-only with no observer.
	private static let legacyName = "app.faceid.FaceID.state"

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "StateBroadcast")

	private static var last: GazeState?

	/// Publishes a state, if it is different from the last one.
	///
	/// Deduplicated because the recognition loop runs at frame rate: posting `detecting` on
	/// every frame would put sixteen notifications a second through the distributed centre,
	/// which is a system-wide bus shared with every other application on the Mac.
	static func post(_ state: GazeState, score: Double? = nil) {
		guard state != last else { return }
		last = state

		var info: [AnyHashable: Any] = ["state": state.rawValue]
		if let score { info["score"] = score }

		for published in [name, legacyName] {
			DistributedNotificationCenter.default().postNotificationName(
				.init(published),
				object: state.rawValue,
				userInfo: info,
				deliverImmediately: true)
		}

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
