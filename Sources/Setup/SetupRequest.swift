import Foundation

/// Decides whether the setup window should close itself as soon as it appears.
///
/// The window opens by itself at launch and has to close again when a face is
/// already enrolled, or every launch would put setup in front of somebody who
/// finished with it weeks ago. That rule cannot see the difference between the
/// window appearing on its own and somebody pressing "Add a Face", so it closed
/// both — and with more than one face allowed, pressing it is a thing people do.
///
/// Two facts settle it, and neither is "was a flag set recently":
///
///   - a deliberate open announces itself with `begin()`
///   - the automatic presentation happens exactly once, at launch
///
/// Keying off the second is what makes this robust. An earlier version only had
/// the flag, read from the window's `task`, which runs when the scene is created
/// and not when an existing one is merely brought forward — so a `begin()` could
/// sit unconsumed and later suppress the dismissal at the *next* launch, leaving
/// setup on screen for an enrolled user.
@MainActor
enum SetupRequest {
	private static var isPending = false
	private static var didPresentAtLaunch = false

	/// Call immediately before `openWindow(id: "enrollment")`.
	static func begin() {
		isPending = true
	}

	/// Whether the window that just appeared should show itself out.
	static func shouldDismissImmediately(isEnrolled: Bool) -> Bool {
		if isPending {
			isPending = false
			return false
		}
		// Anything after the launch presentation was opened by somebody, even if
		// the call site forgot to say so.
		guard !didPresentAtLaunch else { return false }
		didPresentAtLaunch = true

		// A launchd-started agent must not put a window on screen whatever the
		// enrolment state.
		return isEnrolled || AppActivation.isBackgroundLaunch
	}
}
