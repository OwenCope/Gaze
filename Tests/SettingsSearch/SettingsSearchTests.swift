import Foundation

private enum TestError: Error { case failed(String) }

/// Contract checks for the Settings search index.
///
/// Compiles the real `Sources/App/SettingsSearch.swift` with no SwiftUI and no
/// app state: no preferences, keychain, camera, enrolment or security code is
/// involved. Matching is plain substring work — no regex anywhere.
@main
enum SettingsSearchTests {
	static var checks = 0
	static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
		guard condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	static func ids(_ items: [SettingsSearchItem]) -> [String] { items.map(\.id) }

	static func main() throws {
		let all = SettingsSearchItem.all

		// Index shape.
		try expect(!all.isEmpty, "index is nonempty")
		try expect(Set(ids(all)).count == all.count, "ids are unique")
		let panes: Set<String> = ["face", "security", "apps", "general", "notch", "about", "credits"]
		try expect(all.allSatisfy { panes.contains($0.pane) }, "every destination is a real SettingsPane raw value")
		try expect(Set(all.map(\.pane)) == panes, "every pane is reachable from search")
		let sections: Set<String> = [
			"hero", "unlockSection", "movementsSection", "permissionsSection", "securitySection",
			"behaviourSection", "onboardingSection", "updatesSection",
			"appearanceSection", "NotchSettingsSection", "creditsSection", "aboutSection",
			"appLockSection", "appLockListSection", "appLockOptionsSection", "unlockAttemptsSection",
		]
		try expect(all.allSatisfy { sections.contains($0.section) }, "every section is a real detail anchor")
		try expect(all.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty }, "every item has a title and subtitle")

		// Blank and unknown queries match nothing.
		try expect(SettingsSearchItem.results(for: "").isEmpty, "blank query returns no results")
		try expect(SettingsSearchItem.results(for: "   \n\t  ").isEmpty, "whitespace-only query returns no results")
		try expect(SettingsSearchItem.results(for: "zxqvkj").isEmpty, "unknown query returns no results")

		// Required topic matches.
		try expect(ids(SettingsSearchItem.results(for: "password")).contains("password"), "password finds the account-password row")
		try expect(ids(SettingsSearchItem.results(for: "camera")).contains("camera-permission"), "camera finds the camera permission row")
		try expect(ids(SettingsSearchItem.results(for: "walk away")).contains("walk-away"), "walk away finds walk-away lock")
		try expect(ids(SettingsSearchItem.results(for: "theme")).contains("appearance"), "theme finds the appearance row")
		try expect(ids(SettingsSearchItem.results(for: "dark")).contains("appearance"), "dark finds the appearance row")
		try expect(ids(SettingsSearchItem.results(for: "backend")).contains("unlock"), "backend finds the unlocking row")
		try expect(ids(SettingsSearchItem.results(for: "touch id")).contains("touch-id"), "touch id finds the Touch ID row")
		try expect(ids(SettingsSearchItem.results(for: "movement")).contains("movements"), "movement finds the movement count")
		try expect(ids(SettingsSearchItem.results(for: "release")).contains("updates"), "release finds updates")
		try expect(ids(SettingsSearchItem.results(for: "onboarding")).contains("onboarding"), "onboarding finds Getting Started")
		try expect(ids(SettingsSearchItem.results(for: "notch")).contains("notch"), "notch finds the notch panel")
		try expect(ids(SettingsSearchItem.results(for: "credits")).contains("credits"), "credits finds the credits pane")

		// Enrolment stays usable before faces exist: it lands on the hero.
		let faces = SettingsSearchItem.results(for: "enroll")
		try expect(ids(faces).contains("faces"), "enroll finds enrolled faces")
		if let facesItem = faces.first(where: { $0.id == "faces" }) {
			try expect(facesItem.pane == "face", "enrolled faces navigate to the face pane")
			try expect(facesItem.section == "hero", "enrolled faces scroll to the hero")
		} else {
			throw TestError.failed("enrolled faces item missing")
		}

		// Case, diacritics and whitespace.
		try expect(
			ids(SettingsSearchItem.results(for: "PASSWORD")) == ids(SettingsSearchItem.results(for: "password")),
			"search folds case")
		try expect(
			ids(SettingsSearchItem.results(for: "pässword")).contains("password"),
			"search folds diacritics in the query")
		try expect(
			ids(SettingsSearchItem.results(for: "PÄSSWORD")).contains("password"),
			"search folds case and diacritics together")
		try expect(
			ids(SettingsSearchItem.results(for: "  walk   away  ")).contains("walk-away"),
			"search trims whitespace and collapses gaps")

		// Every token must match (AND, not OR).
		let touchStored = SettingsSearchItem.results(for: "touch stored password")
		try expect(ids(touchStored).contains("touch-id"), "multi-token query keeps the item matching all tokens")
		try expect(!ids(touchStored).contains("password"), "multi-token query drops the item missing one token")
		try expect(!ids(SettingsSearchItem.results(for: "walk away")).contains("unlock"), "walk away does not match the unlocking row")

		// Stable ordering: results always follow declared order.
		for query in ["a", "e", "password", "camera", "the", "lock", "face"] {
			let order = SettingsSearchItem.results(for: query).compactMap { item in
				all.firstIndex(where: { candidate in candidate.id == item.id })
			}
			try expect(order == order.sorted(), "results for \(query) keep declared order")
		}
		try expect(
			ids(SettingsSearchItem.results(for: "password")).first == "password",
			"Return picks the declared-first match for password")

		print("\(checks) settings-search checks passed; index only, no app state")
	}
}
