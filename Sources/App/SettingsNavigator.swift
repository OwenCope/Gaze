import Foundation
import Observation

/// Opens Settings on a requested pane and section from outside a view.
///
/// A notification click cannot reach `@Environment(\.openWindow)` or SettingsView's pane
/// state, so it leaves a request here and presents Settings through the closure a live view
/// stored. SettingsView observes `pending`, selects the pane and reveals the section, then
/// clears it. Deliberately free of app types (pane and section travel as strings, and the
/// presentation closure is injected by a view) so the update tests can compile this
/// alongside ReleaseUpdateChecker without the app scene.
@MainActor
@Observable
final class SettingsNavigator {
	static let shared = SettingsNavigator()

	struct Request: Equatable {
		/// A `SettingsPane` raw value.
		let pane: String
		/// The `ScrollViewReader` anchor, e.g. "updatesSection".
		let section: String
		/// Bumps on every request so repeating the same destination still observes a change.
		let token: UInt64
	}

	var pending: Request?
	/// Presents Settings, bringing the app forward first. Stored by an always-alive view.
	var presentSettings: (() -> Void)?

	private var nextToken: UInt64 = 0

	func openUpdates() {
		nextToken &+= 1
		pending = Request(pane: "general", section: "updatesSection", token: nextToken)
		presentSettings?()
	}
}
