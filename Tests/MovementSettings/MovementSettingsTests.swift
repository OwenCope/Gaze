import Foundation

private enum TestError: Error { case failed(String) }

/// Contract checks for the Mac-unlock movement count.
///
/// Exercises real Preferences with an isolated defaults suite. `shared` is
/// never touched; no unlock, camera, credentials or enrolment is involved.
@main
enum MovementSettingsTests {
	static var checks = 0
	static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
		guard condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	@MainActor static func main() throws {
		typealias Count = Preferences.UnlockMovementCount

		// Compile-time: the gate contract needs a Sendable, iterable Int enum.
		func requiresSendableIterable<T: Sendable>(_ type: T.Type) where T: CaseIterable, T: RawRepresentable, T.RawValue == Int {}
		requiresSendableIterable(Count.self)

		try expect(Count.one.rawValue == 1, "one movement feeds 1 to the gate")
		try expect(Count.two.rawValue == 2, "two movements feed 2 to the gate")
		try expect(Count.allCases.count == 2, "no zero/off option for Mac unlock")
		try expect(Count.allCases.allSatisfy { $0.rawValue > 0 }, "every offered count is a positive movement requirement")

		// Existing users have no stored value; corrupt values must fail safe.
		try expect(Count.resolve(stored: nil) == .two, "missing stored value keeps two movements")
		try expect(Count.resolve(stored: 0) == .two, "stored zero falls back to two movements")
		try expect(Count.resolve(stored: -1) == .two, "stored negative falls back to two movements")
		try expect(Count.resolve(stored: 3) == .two, "stored out-of-range falls back to two movements")
		try expect(Count.resolve(stored: 1) == .one, "stored one selects one movement")
		try expect(Count.resolve(stored: 2) == .two, "stored two selects two movements")
		for invalid: Any in [true, false, "1", 1.5, Double.nan, Double.infinity] {
			try expect(Count.resolve(stored: invalid) == .two, "invalid stored type/value uses two: \(invalid)")
		}

		try expect(Count.one.title == "One movement", "one-movement row label")
		try expect(Count.two.title == "Two movements (recommended)", "two-movement row label marks the default")

		let suite = "com.gazeunlock.MovementSettingsTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		let preferences = Preferences(defaults: defaults)
		try expect(preferences.unlockMovementCount == .two, "new installation requires two")
		try expect(defaults.object(forKey: "unlockMovementCount") == nil, "loading default does not write a preference")
		for backend in [UnlockBackendKind.none, .keystroke] {
			preferences.unlockBackend = backend
			for count in Count.allCases {
				preferences.unlockMovementCount = count
				try expect(defaults.integer(forKey: "unlockMovementCount") == count.rawValue, "selection persists for \(backend)")
				try expect(Preferences(defaults: defaults).unlockMovementCount == count, "selection survives reloading for \(backend)")
			}
		}
		for invalid: Any in [0, -1, 3, true, "1", 1.5] {
			defaults.set(invalid, forKey: "unlockMovementCount")
			try expect(Preferences(defaults: defaults).unlockMovementCount == .two, "invalid persisted value requires two: \(invalid)")
		}
		try expect(Preferences(defaults: defaults).showNotchCaptions, "captions default to visible")
		try expect(defaults.object(forKey: "showNotchCaptions") == nil, "reading the caption default does not persist it")
		for invalid: Any in [0, 2, "false", ["invalid"]] {
			defaults.set(invalid, forKey: "showNotchCaptions")
			try expect(Preferences(defaults: defaults).showNotchCaptions, "invalid caption preference preserves visible guidance: \(invalid)")
		}
		for enabled in [false, true, false] {
			let loaded = Preferences(defaults: defaults)
			let movementCount = loaded.unlockMovementCount
			loaded.showNotchCaptions = enabled
			let reloaded = Preferences(defaults: defaults)
			try expect(reloaded.showNotchCaptions == enabled, "caption choice survives reload: \(enabled)")
			try expect(reloaded.unlockMovementCount == movementCount, "caption choice leaves movement requirements unchanged")
		}
		print("\(checks) movement/caption preference checks passed; isolated defaults only")
	}
}
