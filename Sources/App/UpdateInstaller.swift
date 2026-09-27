import AppKit
import CryptoKit
import Foundation
import Security
import os

/// Downloads a release DMG, verifies it and swaps it in over the running app.
///
/// Same bundle id and signing identity, so UserDefaults, keychain and TCC carry
/// over with no migration. The swap and relaunch run in a detached helper after
/// this process exits, so a half-written bundle can never be launched.
@Observable
@MainActor
final class UpdateInstaller {

	enum State: Equatable {
		case idle
		case downloading(fraction: Double)
		case installing
		case failed(String)
	}

	struct Swap: Sendable {
		let scriptPath: String
	}

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "UpdateInstall")

	private(set) var state: State = .idle

	func install(url: URL, sha256: String?, expectedVersion: String) async {
		switch state {
		case .downloading, .installing: return
		case .idle, .failed: break
		}
		guard let sha256, Self.isSHA256(sha256), ReleaseURLPolicy.isTrusted(url) else {
			fail("The download didn't match. Try again.")
			return
		}
		let runningPath = Bundle.main.bundleURL.path
		guard !runningPath.contains("/AppTranslocation/"),
			FileManager.default.isWritableFile(
				atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
		else {
			fail("Move Gaze to Applications to install updates.")
			return
		}
		let current =
			Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
		var expected = expectedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
		if expected.first == "v" || expected.first == "V" { expected.removeFirst() }
		guard !expected.isEmpty, ReleaseUpdateChecker.isNewer(expectedVersion, than: current) else {
			fail("This update couldn't be verified.")
			return
		}
		state = .downloading(fraction: 0)
		let (stream, continuation) = AsyncStream<Double>.makeStream()
		let job = Task.detached {
			await UpdateInstaller.runInstall(
				url: url, sha256: sha256, expectedVersion: expected,
				runningPath: runningPath, progress: continuation)
		}
		for await fraction in stream {
			state = .downloading(fraction: fraction)
		}
		switch await job.value {
		case .success(let swap):
			state = .installing
			Self.launch(swap: swap)
			NSApp.terminate(nil)
		case .failure(let failure):
			fail(failure.message)
		}
	}

	private func fail(_ message: String) {
		state = .failed(message)
	}

	private static func isSHA256(_ value: String) -> Bool {
		value.count == 64
			&& value.utf8.allSatisfy {
				(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
			}
	}

	/// Runs the helper script detached, so it survives this process quitting.
	private static func launch(swap: Swap) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", "nohup /bin/bash \(shQuote(swap.scriptPath)) >/dev/null 2>&1 &"]
		do {
			try process.run()
		} catch {
			logger.error("Could not start the update helper: \(error.localizedDescription)")
		}
	}

	private nonisolated static func shQuote(_ value: String) -> String {
		"'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
	}

	// MARK: - Off-main-actor work

	nonisolated static func runInstall(
		url: URL, sha256: String, expectedVersion: String, runningPath: String,
		progress: AsyncStream<Double>.Continuation
	) async -> Result<Swap, InstallFailure> {
		defer { progress.finish() }
		do {
			let tmp = FileManager.default.temporaryDirectory.appending(
				path: "GazeUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)
			try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
			let dmg = tmp.appending(path: "Gaze.dmg", directoryHint: .notDirectory)
			try await download(url: url, to: dmg, progress: progress)
			let digest = try sha256Hex(of: dmg)
			guard digest.lowercased() == sha256.lowercased() else {
				throw InstallFailure(message: "The download didn't match. Try again.")
			}
			let mount = try mount(dmg: dmg, randomRoot: tmp)
			defer { detach(mount: mount) }
			let candidate = URL(fileURLWithPath: mount).appending(
				path: "Gaze.app", directoryHint: .isDirectory)
			try verify(app: candidate, expectedVersion: expectedVersion)
			let parent = URL(fileURLWithPath: runningPath).deletingLastPathComponent()
			let staged = parent.appending(
				path: ".Gaze-update-\(UUID().uuidString).app", directoryHint: .isDirectory)
			try runProcess(
				"/usr/bin/ditto", [candidate.path, staged.path],
				message: "Couldn't install the update. Try again.")
			try runProcess(
				"/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path],
				message: "Couldn't install the update. Try again.")
			let script = tmp.appending(path: "update.sh", directoryHint: .notDirectory)
			try writeSwapScript(
				at: script, appPath: runningPath, stagedPath: staged.path, tmpPath: tmp.path)
			return .success(Swap(scriptPath: script.path))
		} catch let failure as InstallFailure {
			return .failure(failure)
		} catch {
			return .failure(InstallFailure(message: "Couldn't install the update. Try again."))
		}
	}

	nonisolated static func download(
		url: URL, to destination: URL, progress: AsyncStream<Double>.Continuation
	) async throws {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		configuration.urlCache = nil
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = 600
		let delegate = DownloadDelegate(destination: destination, progress: progress)
		let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
		defer { session.finishTasksAndInvalidate() }
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
			delegate.continuation = continuation
			session.downloadTask(with: url).resume()
		}
	}

	nonisolated static func sha256Hex(of url: URL) throws -> String {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var hasher = SHA256()
		while true {
			guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
			hasher.update(data: chunk)
		}
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	nonisolated static func mount(dmg: URL, randomRoot: URL) throws -> String {
		let output = try runProcess(
			"/usr/bin/hdiutil",
			["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountrandom", randomRoot.path, "-plist", dmg.path],
			message: "Couldn't install the update. Try again.")
		guard let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
			let entities = plist["system-entities"] as? [[String: Any]],
			let mount = entities.compactMap({ $0["mount-point"] as? String }).first
		else { throw InstallFailure(message: "Couldn't install the update. Try again.") }
		return mount
	}

	nonisolated static func detach(mount: String) {
		try? runProcess("/usr/bin/hdiutil", ["detach", "-force", mount], message: "")
	}

	nonisolated static func verify(app: URL, expectedVersion: String) throws {
		guard let data = try? Data(
			contentsOf: app.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)),
			let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
			let identifier = info["CFBundleIdentifier"] as? String,
			identifier == Bundle.main.bundleIdentifier,
			let version = info["CFBundleShortVersionString"] as? String,
			version == expectedVersion
		else { throw InstallFailure(message: "This update couldn't be verified.") }
		// The mounted app must satisfy this app's own designated requirement:
		// same team and identifier, not just any signed bundle named Gaze.
		var ownCode: SecCode?
		var staticOwnCode: SecStaticCode?
		var requirement: SecRequirement?
		var mountedCode: SecStaticCode?
		guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
			SecCodeCopyStaticCode(ownCode, [], &staticOwnCode) == errSecSuccess, let staticOwnCode,
			SecCodeCopyDesignatedRequirement(staticOwnCode, [], &requirement) == errSecSuccess,
			SecStaticCodeCreateWithPath(app as CFURL, [], &mountedCode) == errSecSuccess,
			let mountedCode,
			SecStaticCodeCheckValidity(
				mountedCode,
				SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode),
				requirement) == errSecSuccess
		else { throw InstallFailure(message: "This update couldn't be verified.") }
	}

	nonisolated static func runProcess(_ path: String, _ args: [String], message: String) throws -> Data {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = args
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw InstallFailure(message: message) }
		return output.fileHandleForReading.readDataToEndOfFile()
	}

	/// Waits for this process to exit, swaps the staged app in and reopens it.
	/// The app relaunches plainly with `open`: it is a login item
	/// (`SMAppService.mainApp`), not a launchd agent, so there is nothing to kickstart.
	nonisolated static func writeSwapScript(at script: URL, appPath: String, stagedPath: String, tmpPath: String) throws {
		let pid = ProcessInfo.processInfo.processIdentifier
		let text = """
			#!/bin/bash
			APP=\(shQuote(appPath))
			STAGED=\(shQuote(stagedPath))
			TMP=\(shQuote(tmpPath))
			for _ in $(seq 1 50); do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done
			mv "$APP" "$TMP/Gaze-previous.app"
			if ! mv "$STAGED" "$APP"; then mv "$TMP/Gaze-previous.app" "$APP"; exit 1; fi
			open "$APP"
			rm -rf "$TMP"

			"""
		try text.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
	}
}

struct InstallFailure: Error, Sendable {
	let message: String
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
	static let maximumBytes = 400 * 1024 * 1024

	let destination: URL
	let progress: AsyncStream<Double>.Continuation
	var continuation: CheckedContinuation<URL, any Error>?
	var done = false
	var tooLarge = false

	init(destination: URL, progress: AsyncStream<Double>.Continuation) {
		self.destination = destination
		self.progress = progress
	}

	func urlSession(
		_ session: URLSession, task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
		guard let url = request.url, ReleaseURLPolicy.isTrustedDownloadHop(url) else {
			completionHandler(nil)
			return
		}
		completionHandler(request)
	}

	func urlSession(
		_ session: URLSession, downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
		totalBytesExpectedToWrite: Int64
	) {
		if totalBytesWritten > Int64(Self.maximumBytes)
			|| (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > Int64(Self.maximumBytes))
		{
			tooLarge = true
			downloadTask.cancel()
			return
		}
		if totalBytesExpectedToWrite > 0 {
			progress.yield(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
		}
	}

	func urlSession(
		_ session: URLSession, downloadTask: URLSessionDownloadTask,
		didFinishDownloadingTo location: URL
	) {
		do {
			let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
			guard size <= Self.maximumBytes else {
				tooLarge = true
				downloadTask.cancel()
				return
			}
			try FileManager.default.moveItem(at: location, to: destination)
			finish(.success(destination))
		} catch {
			finish(.failure(error))
		}
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
		if done { return }
		if tooLarge {
			finish(.failure(InstallFailure(message: "The download is too large.")))
			return
		}
		if let error {
			finish(.failure(error))
			return
		}
		finish(.failure(InstallFailure(message: "Couldn't download the update. Try again.")))
	}

	private func finish(_ result: Result<URL, any Error>) {
		guard !done else { return }
		done = true
		switch result {
		case .success(let url): continuation?.resume(returning: url)
		case .failure(let error): continuation?.resume(throwing: error)
		}
		continuation = nil
	}
}
