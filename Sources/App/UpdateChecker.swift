import AppKit
import Foundation
import Observation
import os

/// Checks the git repository for updates, and pulls them.
///
/// Prefers tags, falls back to commits.
///
/// If any release tag exists, only tags count as updates — a tag is the maintainer saying
/// "this point is safe to pull", and without that every work-in-progress commit shows up
/// as an update the user is invited to take. With no tags in the repository there is
/// nothing to mark stability with, so commits are all there is and the checkout reports
/// how far behind the branch it is.
///
/// The upshot: this behaves as a per-release updater the moment the project starts tagging,
/// and as a development one until then, with no setting to get wrong.
///
/// **What survives an update, and what does not.** Settings survive — they live in
/// `UserDefaults` keyed to the bundle identifier, untouched by rebuilding. The enrolled
/// face survives only if the rebuild is signed with the same certificate: faceprints are
/// sealed under a Secure Enclave key whose Keychain ACL is bound to the app's code
/// identity, so a build signed by a different certificate is a different application as
/// far as macOS is concerned and simply finds nothing.
///
/// It deliberately stops after pulling. Rebuilding replaces the running bundle underneath
/// itself, and a bad commit would take the app with it — so the rebuild stays a step the
/// user takes knowingly.
@Observable
@MainActor
final class UpdateChecker {

	static let shared = UpdateChecker()

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "Updates")

	enum State: Equatable {
		case idle
		case checking
		case upToDate
		/// `behind` commits available, with the newest subject line.
		case available(behind: Int, latest: String)
		case pulling
		/// Pulled successfully; the app needs rebuilding to actually change.
		case pulled(count: Int)
		case failed(String)
	}

	private(set) var state: State = .idle

	/// The checkout this app was built from.
	///
	/// Resolved from the bundle's own location when it is running out of `build/`, and
	/// otherwise from the conventional path — an installed copy in `/Applications` has no
	/// way to know where its source lives.
	private var repositoryPath: String? {
		let bundle = Bundle.main.bundleURL
		let fromBuild = bundle.deletingLastPathComponent().deletingLastPathComponent()
		if FileManager.default.fileExists(atPath: fromBuild.appending(path: ".git").path) {
			return fromBuild.path
		}

		let conventional = FileManager.default.homeDirectoryForCurrentUser
			.appending(path: "Developer/FaceID")
		if FileManager.default.fileExists(atPath: conventional.appending(path: ".git").path) {
			return conventional.path
		}
		return nil
	}

	var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
			?? "0"
	}

	// MARK: - Checking

	func check() async {
		guard let repository = repositoryPath else {
			state = .failed("No git checkout found. Updates need the source repository.")
			return
		}

		state = .checking

		// Fetch first: without it the local ref is however stale the last fetch left it,
		// and the app would confidently report "up to date" having asked nobody.
		guard case .success = await run(["fetch", "origin", "--quiet"], in: repository) else {
			state = .failed("Couldn't reach the repository. Check your network or credentials.")
			return
		}

		// Tags first. Their presence is what decides which mode this is in.
		if case .success(let tags) = await run(["tag", "--list"], in: repository),
			!tags.isEmpty
		{
			await checkTags(in: repository)
			return
		}

		guard case .success(let counts) = await run(
			["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: repository)
		else {
			state = .failed("No upstream branch is configured.")
			return
		}

		// "<ahead>\t<behind>"
		let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " })
		let behind = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

		guard behind > 0 else {
			state = .upToDate
			return
		}

		let subject = await run(["log", "-1", "--format=%s", "@{upstream}"], in: repository)
		let latest = if case .success(let line) = subject { line } else { "" }

		Self.logger.notice("\(behind) new commit(s) available.")
		state = .available(behind: behind, latest: latest)
	}

	/// Compares the checked-out commit against the newest release tag.
	private func checkTags(in repository: String) async {
		guard case .success(let latest) = await run(
			["describe", "--tags", "--abbrev=0", "origin/main"], in: repository),
			!latest.isEmpty
		else {
			state = .upToDate
			return
		}

		// Already on it? `--contains` lists the tags reachable from HEAD.
		if case .success(let containing) = await run(
			["tag", "--contains", "HEAD"], in: repository),
			containing.split(separator: "\n").contains(where: { $0 == latest })
		{
			state = .upToDate
			return
		}

		Self.logger.notice("Release \(latest) available.")
		state = .available(behind: 1, latest: latest)
	}

	// MARK: - Pulling

	func pull() async {
		guard let repository = repositoryPath else { return }
		guard case .available(let behind, _) = state else { return }

		state = .pulling

		// Fast-forward only. A merge or rebase here could conflict with local edits and
		// leave the checkout half-resolved, which is not something an app should do to a
		// user's working tree without asking.
		switch await run(["merge", "--ff-only", "@{upstream}"], in: repository) {
		case .success:
			Self.logger.notice("Pulled \(behind) commit(s).")
			state = .pulled(count: behind)
		case .failure(let message):
			state = .failed(
				message.contains("Not possible to fast-forward")
					|| message.contains("local changes")
					? "You have local changes. Commit or stash them, then pull with git."
					: "Pull failed: \(message)")
		}
	}

	/// Opens the checkout so the user can rebuild.
	func revealRepository() {
		guard let repository = repositoryPath else { return }
		NSWorkspace.shared.open(URL(fileURLWithPath: repository))
	}

	// MARK: - git

	private enum RunResult {
		case success(String)
		case failure(String)
	}

	private func run(_ arguments: [String], in repository: String) async -> RunResult {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
				process.arguments = ["-C", repository] + arguments

				// Never prompt. A credential prompt from a background process would hang
				// invisibly, and the check is not worth blocking on.
				var environment = ProcessInfo.processInfo.environment
				environment["GIT_TERMINAL_PROMPT"] = "0"
				environment["GIT_ASKPASS"] = "/usr/bin/true"
				process.environment = environment

				let output = Pipe()
				let errors = Pipe()
				process.standardOutput = output
				process.standardError = errors

				do {
					try process.run()
				} catch {
					continuation.resume(returning: .failure(error.localizedDescription))
					return
				}

				let stdout = output.fileHandleForReading.readDataToEndOfFile()
				let stderr = errors.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()

				let text = String(decoding: stdout, as: UTF8.self)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				let errorText = String(decoding: stderr, as: UTF8.self)
					.trimmingCharacters(in: .whitespacesAndNewlines)

				continuation.resume(
					returning: process.terminationStatus == 0
						? .success(text)
						: .failure(errorText.isEmpty ? "git exited \(process.terminationStatus)" : errorText))
			}
		}
	}
}
