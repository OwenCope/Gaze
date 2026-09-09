import AppKit
import Foundation
import Observation
import os

/// Checks gazeunlock.com for a newer release.
///
/// `UpdateChecker` walks up from the bundle looking for a `.git` and reports how far behind
/// the checkout is. That is the right tool for a copy built from source and no tool at all
/// for a copy that was downloaded: an app in `/Applications` has no repository above it, so
/// it finds nothing and correctly says nothing — which leaves everybody who installed Gaze
/// rather than cloning it with no way to hear that a new version exists.
///
/// This is the other half. The site already owns the release list — releases are written on
/// it, not on GitHub — so the site is what an installed copy should ask. It reads
/// `/api/latest`, which serves the newest published release and filters out drafts and
/// tester-only builds server-side.
///
/// It offers, and does not install. The download is opened in the browser rather than
/// fetched, unpacked and swapped in underneath the running app: replacing a bundle while it
/// is executing is how an updater turns a bad release into an app that will not launch, and
/// Gaze is the thing standing between its user and their locked Mac. The same reasoning
/// `UpdateChecker` gives for stopping after a pull applies here with more force.
@Observable
@MainActor
final class ReleaseUpdateChecker {

	static let shared = ReleaseUpdateChecker()

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Releases")

	/// The feed. Path, not query — it is cached at the edge and a query string would defeat
	/// that for no gain.
	///
	/// `--update-feed=<url>` points it somewhere else, which is the only way to exercise this
	/// without publishing a release to the live site. Testing an updater against production
	/// means either believing it works or shipping a fake version to every user to find out;
	/// the same reasoning that gave `--settings` and `--setup-step` their flags applies here.
	private static var feed: URL {
		if
			let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--update-feed=") }),
			let value = argument.split(separator: "=", maxSplits: 1).last,
			let url = URL(string: String(value))
		{
			return url
		}
		return URL(string: "https://gazeunlock.com/api/latest")!
	}

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
		get { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }
		set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
	}

	/// How often to look, unprompted.
	private static let interval: TimeInterval = 60 * 60 * 24

	private var timer: Timer?

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
		guard timer == nil else { return }

		Task {
			try? await Task.sleep(for: .seconds(8))
			await checkIfDue()
		}

		let timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
			Task { @MainActor in await ReleaseUpdateChecker.shared.checkIfDue() }
		}
		// Common modes, so it keeps firing while a menu is open.
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	/// Checks only if enough time has passed, and never while offering an update.
	///
	/// The second guard matters: once `available` is on screen, re-checking can only either
	/// confirm it or — on a flaky connection — replace a real answer with "couldn't reach
	/// gazeunlock.com", turning a working notification into an error nobody asked for.
	func checkIfDue() async {
		if case .available = state { return }
		if let last = lastCheck, Date().timeIntervalSince(last) < Self.interval { return }
		await check()
		if case .failed = state { return }
		lastCheck = Date()
	}

	// MARK: - Checking

	func check() async {
		state = .checking

		do {
			var request = URLRequest(url: Self.feed)
			// Short. This runs on a timer in the background and, when someone presses the
			// button, in front of a spinner — neither is a reason to hold a connection open
			// for the default sixty seconds on a flaky network.
			request.timeoutInterval = 12
			request.cachePolicy = .reloadRevalidatingCacheData

			let (data, response) = try await URLSession.shared.data(for: request)
			guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
				let code = (response as? HTTPURLResponse)?.statusCode ?? 0
				state = .failed("The update server answered \(code).")
				return
			}

			guard let payload = try? JSONDecoder().decode(Feed.self, from: data) else {
				state = .failed("Couldn't read the update list.")
				return
			}

			guard let latest = payload.latest else {
				// A site with no published releases is up to date by definition.
				state = .upToDate
				return
			}

			guard Self.isNewer(latest.tag, than: currentVersion) else {
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
					downloadURL: latest.download.flatMap { URL(string: $0.url) }))
			Self.logger.notice("Update available: \(latest.tag, privacy: .public)")
		} catch {
			// Offline is not an error worth alarming anyone about — it is the normal state of
			// a laptop half the time — so this says what happened and stops.
			state = .failed("Couldn't reach gazeunlock.com.")
		}
	}

	/// Opens the download in the browser.
	func openDownload() {
		guard case .available(let release) = state else { return }
		let url = release.downloadURL ?? URL(string: "https://gazeunlock.com/releases")!
		NSWorkspace.shared.open(url)
	}

	// MARK: - Versions

	/// Whether `candidate` is a later version than `current`.
	///
	/// Compared component by component as numbers. A string compare puts "0.10" before
	/// "0.9", which is the bug where an updater silently stops working the first time a
	/// minor version reaches double digits — and it stops working in the quiet direction,
	/// reporting "up to date" forever rather than failing visibly. A `v` prefix is tolerated
	/// because tags get written both ways, and anything non-numeric counts as 0.
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		func parts(_ tag: String) -> [Int] {
			tag.trimmingCharacters(in: .whitespaces)
				.replacingOccurrences(of: "v", with: "", options: [.caseInsensitive, .anchored])
				.split(whereSeparator: { ".-+".contains($0) })
				.map { Int($0.prefix(while: \.isNumber)) ?? 0 }
		}
		let (a, b) = (parts(candidate), parts(current))
		for i in 0..<max(a.count, b.count) {
			let left = i < a.count ? a[i] : 0
			let right = i < b.count ? b[i] : 0
			if left != right { return left > right }
		}
		return false
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
