import AppKit
import Foundation
import Observation
import UserNotifications
import os

/// Checks gazeunlock.com for a newer release.
///
/// It offers, and does not install. The download is opened in the browser rather than
/// fetched, unpacked and swapped in underneath the running app: replacing a bundle while it
/// is executing is how an updater turns a bad release into an app that will not launch, and
/// Gaze is the thing standing between its user and their locked Mac.
@Observable
@MainActor
final class ReleaseUpdateChecker {

	static let shared = ReleaseUpdateChecker()

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Releases")

	private static let feed = ReleaseURLPolicy.feed

	struct Release: Equatable {
		let tag: String
		let name: String
		let notes: String
		let downloadURL: URL?
		let downloadSHA256: String?
	}

	enum State: Equatable {
		case idle
		case checking
		case upToDate
		case available(Release)
		/// Reached the site and could not make sense of the answer, or could not reach it.
		case failed(String)
	}

	private(set) var state: State = .idle
	/// Owns the in-app install; the row reads `installer.state` for progress.
	let installer = UpdateInstaller()
	private let defaults: UserDefaults
	private let sessionConfiguration: () -> URLSessionConfiguration
	private let startupDelay: Duration

	init(defaults: UserDefaults = .standard,
		sessionConfiguration: @escaping () -> URLSessionConfiguration = ReleaseURLPolicy.sessionConfiguration,
		startupDelay: Duration = .seconds(8)) {
		self.defaults = defaults
		self.sessionConfiguration = sessionConfiguration
		self.startupDelay = startupDelay
		// The notification delegate cannot reach back through `.shared`: the lifecycle
		// harness forbids that reference file-wide, so each instance registers itself.
		ReleaseNotificationDelegate.shared.checker = self
	}

	/// The version this bundle claims to be.
	var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
	}

	// MARK: - Scheduling

	/// When the last successful check finished, so a relaunch doesn't mean a fresh check.
	///
	/// In `UserDefaults` rather than memory because the common shape of this app's life is
	/// short runs: it is a menu bar agent people quit and reopen. Held in memory, "once a
	/// day" would become "every launch", which for someone who opens it five times a day is
	/// five requests for a document that changes a few times a year.
	private static let lastCheckKey = "lastReleaseCheck"

	private var lastCheck: Date? {
		get { defaults.object(forKey: Self.lastCheckKey) as? Date }
		set { defaults.set(newValue, forKey: Self.lastCheckKey) }
	}

	/// The last version a notification was posted for, so each version notifies once.
	///
	/// Persisted in `UserDefaults` rather than memory: the app is often quit and reopened,
	/// and re-notifying on every launch would train people to dismiss it unread.
	private static let lastNotifiedTagKey = "lastNotifiedReleaseTag"

	private var lastNotifiedTag: String? {
		get { defaults.string(forKey: Self.lastNotifiedTagKey) }
		set { defaults.set(newValue, forKey: Self.lastNotifiedTagKey) }
	}

	/// Posts the per-version notification. A closure so tests can observe without delivering.
	/// Nil means post for real; tests set a closure to observe instead.
	@ObservationIgnored var notificationPoster: (@MainActor (Release) -> Void)?

	/// How often to look, unprompted.
	private static let interval: TimeInterval = 60 * 60 * 24

	/// Never check on a timer more often than this, however often one is triggered.
	private static let minimumInterval: TimeInterval = 60 * 60

	/// Randomised per launch and added to the daily check, so every copy of the app
	/// does not poll the site in the same second.
	private static let maximumJitter: TimeInterval = 30 * 60

	private var timer: Timer?

	/// Retried at unlock when a due check was skipped while locked.
	private var unlockObserver: NSObjectProtocol?

	/// Outstanding scheduled work: the deferred post-launch check or a
	/// timer-triggered one. Tracked so stopping the schedule cancels a check
	/// that is still in flight instead of letting it report into a dead schedule.
	private var scheduledWork: Task<Void, Never>?

	/// Bumped every time scheduled work is (re)started or stopped. A finished
	/// task only clears `scheduledWork` when its generation is still current,
	/// so a slow task from before a stop/restart can never nil out newer work.
	private var scheduleGeneration = 0

    /// Starts the background schedule: one check shortly after launch, then daily.
	///
	/// Without this the feature was a button. Somebody who never opens Settings — which is
	/// most people, since the app's whole point is that it works while they are not looking
	/// at it — would never hear that a new version existed, which makes an update checker
	/// that only checks on demand almost exactly as useful as no update checker.
	///
	/// Deferred a few seconds past launch. Startup is already doing the work that matters
	/// (the lock watcher, the models) and a release check is the least urgent thing the app
	/// will do all day; it should not be competing for the network while the camera warms.
	func startScheduledChecks() {
		guard timer == nil, scheduledWork == nil else { return }

		scheduleGeneration += 1
		let generation = scheduleGeneration
		let delay = startupDelay
		scheduledWork = Task { [weak self] in
			do {
				try await Task.sleep(for: delay)
			} catch {
				// Stopped before the delay elapsed: never check.
				return
			}
			guard let self else { return }
			guard generation == self.scheduleGeneration else { return }
			guard !Task.isCancelled else { return }
			await self.runScheduledCheck(generation: generation)
		}

		let timer = Timer.scheduledTimer(
			withTimeInterval: Self.interval + Double.random(in: 0...Self.maximumJitter), repeats: true
		) { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.enqueueTimerCheck()
			}
		}
		// Common modes, so it keeps firing while a menu is open.
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer

		// A check skipped while locked is picked up at the next unlock.
		unlockObserver = DistributedNotificationCenter.default().addObserver(
			forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil
		) { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				await self.checkIfDue()
			}
		}
	}

	/// Stops the background schedule and cancels any scheduled check in flight.
	///
	/// Stopping twice is harmless, and starting again afterwards schedules fresh.
	func stopScheduledChecks() {
		scheduleGeneration += 1
		timer?.invalidate()
		timer = nil
		scheduledWork?.cancel()
		scheduledWork = nil
		if let unlockObserver {
			DistributedNotificationCenter.default().removeObserver(unlockObserver)
			self.unlockObserver = nil
		}
	}

	isolated deinit {
		timer?.invalidate()
		scheduledWork?.cancel()
		if let unlockObserver {
			DistributedNotificationCenter.default().removeObserver(unlockObserver)
		}
	}

	/// Queues one daily-timer check as cancellable scheduled work on this instance.
	private func enqueueTimerCheck() {
		guard timer != nil else { return }
		scheduleGeneration += 1
		let generation = scheduleGeneration
		scheduledWork = Task { [weak self] in
			guard let self else { return }
			await self.runScheduledCheck(generation: generation)
		}
	}

	/// Runs one scheduled due-check, releasing the tracked work unless a
	/// stop/restart (or a newer timer tick) has superseded it meanwhile.
	private func runScheduledCheck(generation: Int) async {
		await checkIfDue()
		if scheduleGeneration == generation { scheduledWork = nil }
	}

	/// Checks only if enough time has passed, and never while offering an update.
	///
	/// The second guard matters: once `available` is on screen, re-checking can only either
	/// confirm it or — on a flaky connection — replace a real answer with "couldn't reach
	/// gazeunlock.com", turning a working notification into an error nobody asked for.
	func checkIfDue() async {
		if case .available = state { return }
		// Never while locked: there is nobody to tell, and the next unlock or the
		// next scheduled time picks the check up. The timestamp is left alone so
		// the check stays due rather than looking freshly done.
		if Self.isLocked() { return }
		if let last = lastCheck {
			let elapsed = Date().timeIntervalSince(last)
			if elapsed >= 0, elapsed < Self.minimumInterval { return }
		}
		await check()
	}

	/// Asked of the window server rather than remembered.
	private static func isLocked() -> Bool {
		guard
			let session = CGSessionCopyCurrentDictionary() as? [String: Any],
			let locked = session["CGSSessionScreenIsLocked"] as? Bool
		else { return false }
		return locked
	}

	// MARK: - Checking

	func check() async {
		guard state != .checking else { return }
		// A cancelled check restores this rather than reporting an offline
		// failure: stopping the schedule is not the network being down.
		let previous = state
		state = .checking
		var cancelled = false
		defer {
			if cancelled {
				state = previous
			} else {
				switch state {
				case .upToDate, .available: lastCheck = Date()
				case .idle, .checking, .failed: break
				}
			}
		}

		do {
			var request = URLRequest(url: Self.feed)
			// Short. This runs on a timer in the background and, when someone presses the
			// button, in front of a spinner — neither is a reason to hold a connection open
			// on a flaky network.
			request.timeoutInterval = 15
			request.cachePolicy = .reloadRevalidatingCacheData

			let session = URLSession(configuration: sessionConfiguration(),
				delegate: ReleaseFeedRedirectPolicy(), delegateQueue: nil)
			defer { session.invalidateAndCancel() }
			let (bytes, response) = try await session.bytes(for: request)
			// A stop that lands mid-check must surface as a restored prior
			// state, not as an answer from the server.
			try Task.checkCancellation()
			guard let http = response as? HTTPURLResponse, let finalURL = http.url,
				ReleaseURLPolicy.isTrusted(finalURL), (200..<300).contains(http.statusCode) else {
				let code = (response as? HTTPURLResponse)?.statusCode ?? 0
				Self.logger.error("Release check failed: HTTP \(code, privacy: .public)")
				state = .failed("The update server answered \(code).")
				return
			}
			guard response.expectedContentLength <= ReleaseURLPolicy.maximumFeedBytes else {
				state = .failed("The update list is too large.")
				return
			}
			var data = Data()
			for try await byte in bytes {
				try Task.checkCancellation()
				guard data.count < ReleaseURLPolicy.maximumFeedBytes else {
					state = .failed("The update list is too large.")
					return
				}
				data.append(byte)
			}
			try Task.checkCancellation()

			guard let payload = try? JSONDecoder().decode(Feed.self, from: data) else {
				state = .failed("Couldn't read the update list.")
				return
			}

			guard let latest = payload.latest else {
				// A site with no published releases is up to date by definition.
				state = .upToDate
				return
			}

			// The app has no prerelease channel, so a prerelease build is never offered,
			// whatever the tag says. A check, not a failure: the timestamp still advances.
			if latest.prerelease == true {
				Self.logger.notice(
					"Checked \(Self.feed.absoluteString, privacy: .public): latest \(latest.tag, privacy: .public) is prerelease — up to date")
				state = .upToDate
				return
			}

			guard let candidate = Version(latest.tag), let current = Version(currentVersion) else {
				state = .failed("Couldn't read the release version.")
				return
			}
			guard candidate > current else {
				Self.logger.notice(
					"Checked \(Self.feed.absoluteString, privacy: .public): latest \(latest.tag, privacy: .public), running \(self.currentVersion, privacy: .public) — up to date")
				state = .upToDate
				return
			}

		let release = Release(
			tag: latest.tag,
			name: latest.name,
			notes: latest.notes,
			downloadURL: ReleaseURLPolicy.download(latest.download?.url),
			downloadSHA256: latest.download?.sha256)
			state = .available(release)
			Self.logger.notice("Update available: \(latest.tag, privacy: .public)")
			// One notification per version, however often the state is re-entered.
			if lastNotifiedTag != release.tag {
				lastNotifiedTag = release.tag
				if let notificationPoster { notificationPoster(release) } else { ReleaseUpdateChecker.postNotification(for: release) }
			}
		} catch {
			// A stopped schedule is not an offline Mac. Cancellation — the
			// task dying, a CancellationError, or the session reporting a
			// cancelled request — puts the previous state back and leaves
			// lastReleaseCheck alone.
			if error is CancellationError
				|| (error as? URLError)?.code == .cancelled || Task.isCancelled {
				cancelled = true
				return
			}
			// Offline is not an error worth alarming anyone about — it is the normal state of
			// a laptop half the time — so this says what happened and stops.
			state = .failed("Couldn't reach gazeunlock.com.")
		}
	}

	/// Installs the available release in place, relaunching when done.
	func install() {
		guard case .available(let release) = state, let url = release.downloadURL else { return }
		let checker = self
		Task {
			await checker.installer.install(
				url: url, sha256: release.downloadSHA256, expectedVersion: release.tag)
		}
	}

	/// Opens the download in the browser.
	func openDownload() {
		guard case .available(let release) = state else { return }
		let url = release.downloadURL.flatMap { ReleaseURLPolicy.isTrusted($0) ? $0 : nil }
			?? ReleaseURLPolicy.releases
		NSWorkspace.shared.open(url)
	}

	// MARK: - Notifications

	/// Posts one notification per version. The Install action runs the in-app installer;
	/// clicking the notification opens Settings on the Updates section, falling back to
	/// the same URL as Download only when no verified install is offered.
	private static func postNotification(for release: Release) {
		// UNUserNotificationCenter raises outside an app bundle (test harnesses,
		// command-line runs); there is nobody to notify there anyway.
		guard Bundle.main.bundleURL.pathExtension == "app" else { return }
		let center = UNUserNotificationCenter.current()
		center.delegate = ReleaseNotificationDelegate.shared
		let install = UNNotificationAction(
			identifier: ReleaseNotificationDelegate.installActionID, title: "Install", options: .foreground)
		center.setNotificationCategories([
			UNNotificationCategory(
				identifier: ReleaseNotificationDelegate.categoryID, actions: [install],
				intentIdentifiers: [], options: [])
		])
		let content = UNMutableNotificationContent()
		content.title = "Gaze \(Self.displayVersion(for: release.tag)) is ready"
		content.body = "Install it now, or anytime from Settings."
		content.categoryIdentifier = ReleaseNotificationDelegate.categoryID
		let url = release.downloadURL.flatMap { ReleaseURLPolicy.isTrusted($0) ? $0 : nil }
			?? ReleaseURLPolicy.releases
		content.userInfo = ["url": url.absoluteString, "installable": release.downloadSHA256 != nil]
		let request = UNNotificationRequest(
			identifier: "gaze-release-\(release.tag)", content: content, trigger: nil)
		center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
			guard granted else { return }
			center.add(request)
		}
	}

	/// The tag without a leading v, for display.
	static func displayVersion(for tag: String) -> String {
		var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
		if value.first == "v" || value.first == "V" { value.removeFirst() }
		return value
	}

	// MARK: - Versions

	/// Whether `candidate` is a later version than `current`.
	///
	/// Semantic-version precedence, also accepting short numeric versions and a v prefix.
	/// Build metadata never changes precedence; malformed versions never offer an update.
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		guard let candidate = Version(candidate), let current = Version(current) else { return false }
		return candidate > current
	}

	private struct Version: Comparable {
		let core: [String]
		let prerelease: [String]

		init?(_ tag: String) {
			var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
			if value.first == "v" || value.first == "V" { value.removeFirst() }
			let build = value.split(separator: "+", omittingEmptySubsequences: false)
			guard (1...2).contains(build.count) else { return nil }
			if build.count == 2, Self.identifiers(build[1]) == nil { return nil }
			let release = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
			let numbers = release[0].split(separator: ".", omittingEmptySubsequences: false)
			guard (1...3).contains(numbers.count), numbers.allSatisfy({ Self.isNumber($0) && Self.hasNoLeadingZero($0) })
			else { return nil }
			core = numbers.map(String.init) + Array(repeating: "0", count: 3 - numbers.count)
			if release.count == 2 {
				guard let identifiers = Self.identifiers(release[1]),
					identifiers.allSatisfy({ !Self.isNumber($0) || Self.hasNoLeadingZero($0) })
				else { return nil }
				prerelease = identifiers
			} else {
				prerelease = []
			}
		}

		static func < (lhs: Self, rhs: Self) -> Bool {
			for (left, right) in zip(lhs.core, rhs.core) where left != right {
				return numberIsLess(left, than: right)
			}
			if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
				return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
			}
			for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
				switch (isNumber(left), isNumber(right)) {
				case (true, true): return numberIsLess(left, than: right)
				case (true, false): return true
				case (false, true): return false
				case (false, false): return left < right
				}
			}
			return lhs.prerelease.count < rhs.prerelease.count
		}

		private static func identifiers(_ value: Substring) -> [String]? {
			let parts = value.split(separator: ".", omittingEmptySubsequences: false)
			guard parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy {
				(48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
			} }) else { return nil }
			return parts.map(String.init)
		}

		private static func isNumber(_ value: some StringProtocol) -> Bool {
			!value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
		}

		private static func hasNoLeadingZero(_ value: some StringProtocol) -> Bool {
			value.count == 1 || value.first != "0"
		}

		private static func numberIsLess(_ lhs: String, than rhs: String) -> Bool {
			// Compare decimal strings without overflowing Int on a large version component.
			lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
		}
	}

	// MARK: - Wire format

	private struct Feed: Decodable {
		let latest: Item?

		struct Item: Decodable {
			let tag: String
			let name: String
			let notes: String
			let prerelease: Bool?
			let download: Download?
		}

		struct Download: Decodable {
			let url: String
			let name: String?
			let size: Int?
			let sha256: String?
		}
	}
}

/// Routes the update notification: Install runs the in-app installer, clicking opens
/// Settings on Updates, and only a release with no verified download falls back to the
/// browser. The URL was allow-listed when the notification was posted and is checked
/// again here, so only gazeunlock.com opens.
private final class ReleaseNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
	static let shared = ReleaseNotificationDelegate()
	static let categoryID = "gaze-update"
	static let installActionID = "install"

	/// The checker to install with. A plain reference would need `.shared`, which the
	/// lifecycle harness forbids file-wide, so each checker registers itself in `init`.
	/// `nonisolated(unsafe)` because the delegate answers off the main actor; every use
	/// hops to it before touching the checker.
	nonisolated(unsafe) weak var checker: ReleaseUpdateChecker?

	func userNotificationCenter(
		_ center: UNUserNotificationCenter, willPresent notification: UNNotification
	) async -> UNNotificationPresentationOptions {
		[.banner, .sound]
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
	) async {
		if response.actionIdentifier == Self.installActionID {
			let checker = self.checker
			await MainActor.run { checker?.install() }
			return
		}
		guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
		let content = response.notification.request.content
		if content.userInfo["installable"] as? Bool == true {
			await MainActor.run { SettingsNavigator.shared.openUpdates() }
			return
		}
		guard let value = content.userInfo["url"] as? String,
			let url = URL(string: value), ReleaseURLPolicy.isTrusted(url)
		else { return }
		await MainActor.run { NSWorkspace.shared.open(url) }
	}
}
