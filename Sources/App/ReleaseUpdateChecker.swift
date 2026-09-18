import AppKit
import Foundation
import Observation
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
	private let defaults: UserDefaults
	private let sessionConfiguration: () -> URLSessionConfiguration
	private let startupDelay: Duration

	init(defaults: UserDefaults = .standard,
		sessionConfiguration: @escaping () -> URLSessionConfiguration = ReleaseURLPolicy.sessionConfiguration,
		startupDelay: Duration = .seconds(8)) {
		self.defaults = defaults
		self.sessionConfiguration = sessionConfiguration
		self.startupDelay = startupDelay
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

	/// How often to look, unprompted.
	private static let interval: TimeInterval = 60 * 60 * 24

	private var timer: Timer?

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

		let timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.enqueueTimerCheck()
			}
		}
		// Common modes, so it keeps firing while a menu is open.
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
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
	}

	isolated deinit {
		timer?.invalidate()
		scheduledWork?.cancel()
	}

	/// Queues one hourly-timer check as cancellable scheduled work on this instance.
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
		if let last = lastCheck {
			let elapsed = Date().timeIntervalSince(last)
			if elapsed >= 0, elapsed < Self.interval { return }
		}
		await check()
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
			// for the default sixty seconds on a flaky network.
			request.timeoutInterval = 12
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

			state = .available(
				Release(
					tag: latest.tag,
					name: latest.name,
					notes: latest.notes,
					downloadURL: ReleaseURLPolicy.download(latest.download?.url)))
			Self.logger.notice("Update available: \(latest.tag, privacy: .public)")
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

	/// Opens the download in the browser.
	func openDownload() {
		guard case .available(let release) = state else { return }
		let url = release.downloadURL.flatMap { ReleaseURLPolicy.isTrusted($0) ? $0 : nil }
			?? ReleaseURLPolicy.releases
		NSWorkspace.shared.open(url)
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
			let download: Download?
		}

		struct Download: Decodable {
			let url: String
		}
	}
}
