import Foundation

// MARK: - Test-only BiometricGate stub
//
// AppLockURLAction's `authorize` parameter is typed as
// `(BiometricGate.Reason) async -> Bool`. The real gate needs
// LocalAuthentication and the running app, so the harness compiles the real
// action against this stub and always injects an explicit closure below; the
// `require` default never runs.
enum BiometricGate {
	enum Reason: String {
		case toggleAppLock = "lock or unlock an app"
	}

	@MainActor
	static func require(_ reason: Reason) async -> Bool { false }
}

// MARK: - Tests
//
// Step-1 foundation for App Lock: the locked bundle-ID store
// (AppLockStore), the locked/unlocked/relock state machine
// (AppLockStateMachine), and the activation watcher (AppLockWatcher). The
// three production files compile unchanged alongside this file. The store is
// pointed at throwaway UserDefaults suites so the test process never touches
// the real defaults, and the watcher is driven through
// appDidActivate(bundleID:now:) directly, so no NSWorkspace observation (and
// no real app fronting) happens.

@main
enum AppLockTests {
	static var checks = 0
	static var made = 0

	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		precondition(condition(), description)
		checks += 1
	}

	static let app = "com.example.locked"
	static let free = "com.example.free"
	static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

	static let neverLockable = [
		"com.gazeunlock.Gaze",
		"com.apple.finder",
		"com.apple.systempreferences",
		"com.apple.loginwindow",
	]

	static func makeStore() -> AppLockStore {
		made += 1
		let name = "com.gazeunlock.Gaze.AppLockTests.\(made)"
		let defaults = UserDefaults(suiteName: name)!
		defaults.removePersistentDomain(forName: name)
		let groupName = name + ".group"
		let group = UserDefaults(suiteName: groupName)!
		group.removePersistentDomain(forName: groupName)
		return AppLockStore(defaults: defaults, groupDefaults: group)
	}

	static func main() async {
		// The picker labels the plan names.
		check(AppLockRelockPolicy.afterQuit.title == "After quitting", "After quitting is a Lock again option")
		check(
			AppLockRelockPolicy.afterFiveMinutesInBackground.title == "After 5 minutes in the background",
			"After 5 minutes in the background is a Lock again option")
		check(AppLockRelockPolicy.everyTime.title == "Every time it opens", "Every time it opens is a Lock again option")
		check(AppLockStateMachine.backgroundLimit == 5 * 60, "Five minutes in the background means 300 seconds")

		// After quitting (the default): backgrounding leaves the app unlocked,
		// quitting locks it again.
		var store = makeStore()
		check(store.relockPolicy == .afterQuit, "Lock again defaults to After quitting")
		store.relockPolicy = .afterQuit
		store.add(app)
		var machine = AppLockStateMachine(store: store)
		check(machine.state(for: app, now: t0) == .locked, "A locked app starts locked")
		check(machine.needsShield(app, now: t0), "A locked app needs the shield")
		machine.unlock(app, now: t0)
		check(machine.state(for: app, now: t0) == .unlocked, "A face check unlocks the app")
		check(!machine.needsShield(app, now: t0), "An unlocked app needs no shield")
		machine.appDidResign(app, now: t0)
		machine.appDidActivate(app, now: t0)
		check(machine.state(for: app, now: t0) == .unlocked, "After quitting stays unlocked across backgrounding")
		machine.appDidQuit(app)
		check(machine.state(for: app, now: t0) == .locked, "Quitting locks the app again")
		check(machine.needsShield(app, now: t0), "A quit app needs the shield again")

		// Opened while locked: macOS can announce the launch after the unlock. That
		// late notice must not relock the process that was just unlocked.
		let launched = t0.addingTimeInterval(10)
		machine.unlock(app, now: launched.addingTimeInterval(1))
		machine.appDidLaunch(app, launchedAt: launched)
		check(machine.state(for: app, now: launched.addingTimeInterval(2)) == .unlocked,
			"A late launch notice keeps the unlock it came after")
		machine.appDidLaunch(app, launchedAt: launched.addingTimeInterval(5))
		check(machine.state(for: app, now: launched.addingTimeInterval(6)) == .locked,
			"A genuinely new launch after the unlock locks again")
		machine.unlock(app, now: launched.addingTimeInterval(20))
		machine.appDidQuit(app)
		check(machine.needsShield(app, now: launched.addingTimeInterval(20.5)),
			"Quitting inside the unlock grace still needs the shield")

		// After 5 minutes in the background: unlocked until the limit, then locked.
		store = makeStore()
		store.relockPolicy = .afterFiveMinutesInBackground
		store.add(app)
		machine = AppLockStateMachine(store: store)
		machine.unlock(app, now: t0)
		machine.appDidResign(app, now: t0)
		check(
			machine.state(for: app, now: t0.addingTimeInterval(4 * 60)) == .unlocked,
			"Four minutes in the background stays unlocked")
		check(
			machine.state(for: app, now: t0.addingTimeInterval(5 * 60)) == .locked,
			"Five minutes in the background locks the app again")
		check(
			machine.needsShield(app, now: t0.addingTimeInterval(5 * 60)),
			"A timed-out app needs the shield")

		// Coming back to the front clears the background clock.
		machine.unlock(app, now: t0)
		machine.appDidResign(app, now: t0)
		machine.appDidActivate(app, now: t0.addingTimeInterval(60))
		check(
			machine.state(for: app, now: t0.addingTimeInterval(6 * 60)) == .unlocked,
			"Returning to the front restarts the background allowance")

		// A later resign must not restart the clock.
		store = makeStore()
		store.relockPolicy = .afterFiveMinutesInBackground
		store.add(app)
		machine = AppLockStateMachine(store: store)
		machine.unlock(app, now: t0)
		machine.appDidResign(app, now: t0)
		machine.appDidResign(app, now: t0.addingTimeInterval(2 * 60))
		check(
			machine.state(for: app, now: t0.addingTimeInterval(5 * 60)) == .locked,
			"A second resign does not restart the background clock")

		// Every time it opens: leaving the front locks again at once.
		store = makeStore()
		store.relockPolicy = .everyTime
		store.add(app)
		machine = AppLockStateMachine(store: store)
		machine.unlock(app, now: t0)
		check(machine.state(for: app, now: t0) == .unlocked, "A face check unlocks the app")
		machine.appDidResign(app, now: t0)
		check(
			machine.state(for: app, now: t0) == .locked,
			"Every time it opens locks the moment the app leaves the front")
		machine.unlock(app, now: t0)
		machine.appDidQuit(app)
		check(machine.state(for: app, now: t0) == .locked, "A fresh launch is never unlocked")

		// Sleep and screen lock relock under every Lock again option.
		for policy in AppLockRelockPolicy.allCases {
			store = makeStore()
			store.relockPolicy = policy
			store.add(app)
			machine = AppLockStateMachine(store: store)
			machine.unlock(app, now: t0)
			machine.systemDidSleep()
			check(machine.state(for: app, now: t0) == .locked, "Sleep relocks under \(policy.title)")
			machine.unlock(app, now: t0)
			machine.screenDidLock()
			check(machine.state(for: app, now: t0) == .locked, "Screen lock relocks under \(policy.title)")
		}

		// The never-lockable list refuses locks.
		store = makeStore()
		check(AppLockStore.neverLockable.count == 4, "The never-lockable list is exactly the four")
		for bundleID in neverLockable {
			check(AppLockStore.isNeverLockable(bundleID), "\(bundleID) is never lockable")
			check(!store.add(bundleID), "Locking \(bundleID) is refused")
			check(!store.isLocked(bundleID), "\(bundleID) reads as unlocked")
		}
		store.add(app)
		store.lockedBundleIDs = Set(neverLockable).union([app])
		check(store.lockedBundleIDs == [app], "Assigning the never-lockable list keeps only the lockable app")
		machine = AppLockStateMachine(store: store)
		for bundleID in neverLockable {
			machine.unlock(bundleID, now: t0)
			check(!machine.needsShield(bundleID, now: t0), "\(bundleID) never needs the shield")
		}

		// The watcher reports shield-needed before a locked app becomes key.
		store = makeStore()
		store.add(app)
		machine = AppLockStateMachine(store: store)
		let watcher = AppLockWatcher(store: store, machine: machine)
		check(watcher.shouldShield(bundleID: app, now: t0), "shouldShield is true before a locked app comes forward")
		check(!watcher.shouldShield(bundleID: free, now: t0), "An unlocked app never needs the shield")
		var shielded: [String] = []
		watcher.onShieldNeeded = { shielded.append($0) }
		check(watcher.appDidActivate(bundleID: app, now: t0), "Activating a locked app reports shield-needed")
		check(shielded == [app], "The shield callback fires synchronously inside activation, before key status")
		machine.unlock(app, now: t0)
		check(!watcher.shouldShield(bundleID: app, now: t0), "shouldShield is false once unlocked")
		check(!watcher.appDidActivate(bundleID: app, now: t0), "Activating an unlocked app reports no shield")
		check(shielded == [app], "An unlocked activation fires no second callback")
		machine.appDidQuit(app)
		check(watcher.appDidActivate(bundleID: app, now: t0), "A relaunched app needs the shield again")
		check(shielded == [app, app], "The relaunch fires the shield callback again")
		for bundleID in neverLockable {
			check(!watcher.shouldShield(bundleID: bundleID, now: t0), "\(bundleID) never reports shield-needed")
			check(!watcher.appDidActivate(bundleID: bundleID, now: t0), "\(bundleID) never fires the shield on activation")
		}
		check(shielded == [app, app], "Never-lockable activations fire no callback")

		// Face misses (the AppLockRecognizer contract): three misses disable
		// the face until an unlock clears the counter.
		store = makeStore()
		store.add(app)
		machine = AppLockStateMachine(store: store)
		check(machine.faceMissCount(for: app) == 0, "No face misses to start")
		check(!machine.isFaceDisabled(app), "Face starts enabled")
		machine.recordFaceMiss(app)
		machine.recordFaceMiss(app)
		check(machine.faceMissCount(for: app) == 2, "Two misses are counted")
		check(!machine.isFaceDisabled(app), "Two misses leave the face enabled")
		machine.recordFaceMiss(app)
		check(
			machine.faceMissCount(for: app) == AppLockStateMachine.maxFaceMisses,
			"Three misses reach the limit")
		check(machine.isFaceDisabled(app), "Three misses disable the face")
		machine.unlock(app, now: t0)
		check(machine.faceMissCount(for: app) == 0, "Unlock clears the miss counter")
		check(!machine.isFaceDisabled(app), "Unlock re-enables the face")

		// Unlock clears a partial count too.
		machine.recordFaceMiss(app)
		machine.unlock(app, now: t0)
		check(machine.faceMissCount(for: app) == 0, "Unlock clears a partial miss count")

		// Finder menu titles: locked vs unlocked vs never-lockable.
		check(
			FinderLockMenu.title(selectedCount: 1, appBundleID: app, isLocked: true) == "Unlock with Gaze",
			"Locked app offers Unlock with Gaze")
		check(
			FinderLockMenu.title(selectedCount: 1, appBundleID: app, isLocked: false) == "Lock with Gaze",
			"Unlocked app offers Lock with Gaze")
		for bundleID in neverLockable {
			check(
				FinderLockMenu.title(selectedCount: 1, appBundleID: bundleID, isLocked: false) == nil,
				"\(bundleID) has no Finder menu")
			check(
				FinderLockMenu.title(selectedCount: 1, appBundleID: bundleID, isLocked: true) == nil,
				"\(bundleID) has no Finder menu when locked")
		}
		check(
			FinderLockMenu.title(selectedCount: 0, appBundleID: app, isLocked: false) == nil,
			"No selection has no menu")
		check(
			FinderLockMenu.title(selectedCount: 2, appBundleID: app, isLocked: false) == nil,
			"Two apps have no menu")
		check(
			FinderLockMenu.title(selectedCount: 1, appBundleID: nil, isLocked: false) == nil,
			"No app has no menu")
		check(
			FinderLockMenu.title(selectedCount: 1, appBundleID: "", isLocked: false) == nil,
			"Empty id has no menu")

		// Toggle URL parsing, both sides of the extension/app mirror.
		let toggle = FinderLockMenu.toggleURL(for: app)!
		check(FinderLockMenu.bundleID(fromToggleURL: toggle) == app, "Toggle URL round-trips through FinderLockMenu")
		check(AppLockURLAction.bundleID(from: toggle) == app, "App side parses the Finder toggle URL")
		for bad in [
			URL(string: "gaze://app-lock/toggle")!,
			URL(string: "gaze://app-lock/toggle?bundle=")!,
			URL(string: "https://example.com/")!,
			URL(string: "gaze://other/toggle?bundle=\(app)")!,
			URL(string: "gaze://app-lock/other?bundle=\(app)")!,
		] {
			check(FinderLockMenu.bundleID(fromToggleURL: bad) == nil, "Finder refuses malformed \(bad)")
			check(AppLockURLAction.bundleID(from: bad) == nil, "App side refuses malformed \(bad)")
			let changed = await AppLockURLAction.perform(url: bad, store: store, authorize: { _ in true })
			check(changed == false, "Malformed URL performs nothing")
		}

		// URL perform(): refused authorisation changes nothing, and
		// never-lockable ids change nothing even when authorised.
		store = makeStore()
		let lockURL = FinderLockMenu.toggleURL(for: app)!
		let didLock = await AppLockURLAction.perform(url: lockURL, store: store, authorize: { _ in true })
		check(didLock == true, "Authorised toggle locks")
		check(store.isLocked(app), "Authorised toggle leaves the app locked")
		let keptLock = await AppLockURLAction.perform(url: lockURL, store: store, authorize: { _ in false })
		check(keptLock == false, "Refused authorisation reports no change")
		check(store.isLocked(app), "Refused authorisation keeps the lock")
		let didUnlock = await AppLockURLAction.perform(url: lockURL, store: store, authorize: { _ in true })
		check(didUnlock == true, "Authorised toggle unlocks")
		check(!store.isLocked(app), "Authorised toggle leaves the app unlocked")
		let keptUnlocked = await AppLockURLAction.perform(url: lockURL, store: store, authorize: { _ in false })
		check(keptUnlocked == false, "Refused authorisation keeps it unlocked")
		check(!store.isLocked(app), "Refused authorisation changes nothing when unlocked")
		for bundleID in neverLockable {
			let neverURL = FinderLockMenu.toggleURL(for: bundleID)!
			let neverChanged = await AppLockURLAction.perform(url: neverURL, store: store, authorize: { _ in true })
			check(neverChanged == false, "Never-lockable toggle performs nothing")
			check(!store.isLocked(bundleID), "\(bundleID) stays unlocked")
		}

		print("PASS: \(checks) app-lock checks; real AppLockStore, AppLockStateMachine and AppLockWatcher, no real defaults, no workspace observation.")
	}
}
