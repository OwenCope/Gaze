import AppKit
import Darwin
import Foundation
import Security
import os

/// Answers Gaze's PAM module when `sudo` asks whether a face check may replace
/// the password, over ~/Library/Application Support/Gaze/sudo.sock.
///
/// The safety rules, matching the PAM module: only interactive sudo in a real
/// terminal gets asked about (the module refuses anything else before ever
/// connecting), the command sudo is about to run is shown in the notch panel
/// so a nod means "I read this" (shortened with a middle ellipsis when long),
/// one request runs at a time, and anything doubtful — a peer that isn't
/// root's /usr/bin/sudo, a malformed message, a truncated command, a vanished
/// or changed sudo process, a failed or cancelled check — answers NO, which
/// drops sudo back to its normal password prompt. The module treats every
/// answer other than OK as "ask for the password", so NO is always safe.
///
/// The peer checks matter because any process of the user could otherwise
/// connect and fish for approvals: the socket accepts only a peer whose uid is
/// 0 (sudo runs setuid root) and whose executable is /usr/bin/sudo, the same
/// peer is re-verified after approval and before answering OK so a reused pid
/// can't inherit a nod, and the panel's isStillWanted polls that the same pid
/// still exists, so approval can't outlive the sudo that asked for it.
@MainActor
final class SudoApproval {
	private let check: FaceApprovalCheck
	private var source: DispatchSourceRead?
	private var listenerFD: Int32 = -1
	private var socketPath: String = ""
	nonisolated private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Sudo")
	private static let socketName = "sudo.sock"
	private static let folderName = "Library/Application Support/Gaze"
	private static let expectedPeerPath = "/usr/bin/sudo"
	private static let truncatedMarker = " [+more]"

	init(check: FaceApprovalCheck) {
		self.check = check
	}

	/// Binds the socket and starts answering requests. Safe to call twice.
	func start() {
		guard source == nil else { return }
		let folder = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
			.appendingPathComponent(Self.folderName, isDirectory: true)
		do {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700])
		} catch {
			Self.logger.error("Could not create the sudo socket folder: \(error.localizedDescription, privacy: .public)")
			return
		}
		let path = folder.appendingPathComponent(Self.socketName).path
		var existing = stat()
		if lstat(path, &existing) == 0 {
			// A live server keeps its socket: only clear a stale one, same as
			// the browser socket listener, so two Gaze copies never fight.
			guard existing.st_uid == geteuid(), (existing.st_mode & S_IFMT) == S_IFSOCK else {
				Self.logger.error("The sudo socket path is not Gaze's own socket; not listening.")
				return
			}
			let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
			defer { if probe >= 0 { Darwin.close(probe) } }
			let active: Bool
			do {
				var address = try Self.address(path)
				active = withUnsafePointer(to: &address) { pointer in
					pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
						Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
					}
				}
			} catch {
				Self.logger.error("Could not check the existing sudo socket; not listening.")
				return
			}
			guard !active, errno == ECONNREFUSED else { return }
			guard unlink(path) == 0 else {
				Self.logger.error("Could not remove the stale sudo socket; not listening.")
				return
			}
		}
		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else { return }
		var initialized = false
		defer { if !initialized { Darwin.close(fd) } }
		let address: sockaddr_un
		do {
			address = try Self.address(path)
		} catch {
			Self.logger.error("The sudo socket path is too long; not listening.")
			return
		}
		var mutable = address
		let bound = withUnsafePointer(to: &mutable) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
			}
		}
		guard bound else {
			Self.logger.error("Could not bind the sudo socket; not listening.")
			return
		}
		guard chmod(path, 0o600) == 0, Darwin.listen(fd, 4) == 0,
			fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
			Self.logger.error("Could not prepare the sudo socket; not listening.")
			unlink(path)
			return
		}
		let queue = DispatchQueue.global(qos: .userInitiated)
		let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
		reader.setEventHandler { [weak self] in
			while true {
				let incoming = Darwin.accept(fd, nil, nil)
				if incoming < 0 {
					if errno == EINTR { continue }
					return
				}
				// Peer verification and the one-line read block briefly, so they
				// stay on this background queue; only the face check itself
				// needs the main actor.
				guard let request = Self.readRequest(from: incoming) else {
					Darwin.close(incoming)
					continue
				}
				Task { [weak self] in await self?.decide(request) }
			}
		}
		reader.setCancelHandler { Darwin.close(fd); unlink(path) }
		listenerFD = fd
		socketPath = path
		source = reader
		initialized = true
		reader.resume()
		Self.logger.notice("Listening for sudo approval requests.")
	}

	/// Stops answering; in-flight requests keep their connections but a closed
	/// sudo reads them as NO and falls back to the password prompt.
	func stop() {
		source?.cancel()
		source = nil
		listenerFD = -1
		socketPath = ""
	}

	// MARK: - Requests

	private struct Request: Sendable {
		let fd: Int32
		let pid: pid_t
		let command: String
	}

	/// Verifies the peer and reads its one request line. Returns nil for
	/// anything untrusted or malformed; the caller just hangs up, which the
	/// PAM module reads as "ask for the password".
	private nonisolated static func readRequest(from fd: Int32) -> Request? {
		var peerPid: pid_t = 0
		var pidLength = socklen_t(MemoryLayout<pid_t>.size)
		guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPid, &pidLength) == 0, peerPid > 1 else {
			logger.notice("Rejected a sudo request from an unknown peer.")
			return nil
		}
		var credentials = xucred()
		var credentialsLength = socklen_t(MemoryLayout<xucred>.size)
		guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &credentialsLength) == 0 else {
			logger.notice("Rejected a sudo request whose credentials could not be read.")
			return nil
		}
		// sudo runs setuid root, so a uid-0 peer is the first proof this really
		// is sudo and not the user's own malware connecting directly.
		guard credentials.cr_uid == 0 else {
			logger.notice("Rejected a sudo request from pid \(peerPid, privacy: .public): not running as root.")
			return nil
		}
		// The second proof: the executable behind that pid is sudo itself.
		var executable = [CChar](repeating: 0, count: Int((4 * Int(MAXPATHLEN))))
		let length = executable.withUnsafeMutableBufferPointer { buffer in
			proc_pidpath(peerPid, buffer.baseAddress, UInt32(buffer.count))
		}
		guard length > 0, String(cString: executable) == expectedPeerPath else {
			logger.notice("Rejected a sudo request from pid \(peerPid, privacy: .public): not /usr/bin/sudo.")
			return nil
		}
		var timeout = timeval(tv_sec: 2, tv_usec: 0)
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		var bytes: [UInt8] = []
		bytes.reserveCapacity(128)
		while bytes.count < 512 {
			var byte: UInt8 = 0
			let received = Darwin.read(fd, &byte, 1)
			if received < 0 {
				if errno == EINTR { continue }
				return nil
			}
			if received == 0 { return nil }
			if byte == 10 { break }
			bytes.append(byte)
		}
		guard !bytes.isEmpty, let line = String(bytes: bytes, encoding: .utf8),
			line.hasPrefix("SUDO ") else { return nil }
		let rest = line.dropFirst("SUDO ".count)
		guard let tab = rest.firstIndex(of: "\t") else { return nil }
		let tty = String(rest[..<tab])
		let command = String(rest[rest.index(after: tab)...])
		// An empty tty or command means the module's guards were bypassed, so
		// this did not come from the real module.
		guard !tty.isEmpty, !command.isEmpty else { return nil }
		return Request(fd: fd, pid: peerPid, command: command)
	}

	/// Re-checks, after approval and before answering OK, that the peer is
	/// still root's /usr/bin/sudo for the same pid, so a nod can't leak onto
	/// a reused pid. Anything doubtful returns false.
	private nonisolated static func peerStillValid(fd: Int32, pid: pid_t) -> Bool {
		var credentials = xucred()
		var credentialsLength = socklen_t(MemoryLayout<xucred>.size)
		guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &credentialsLength) == 0,
			credentials.cr_uid == 0 else { return false }
		var executable = [CChar](repeating: 0, count: Int((4 * Int(MAXPATHLEN))))
		let length = executable.withUnsafeMutableBufferPointer { buffer in
			proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
		}
		guard length > 0, String(cString: executable) == expectedPeerPath else { return false }
		return true
	}

	private func decide(_ request: Request) async {
		defer { Darwin.close(request.fd) }
		func reply(_ text: String) {
			text.withCString { pointer in
				var sent = 0
				let count = Int(strlen(pointer))
				while sent < count {
					let written = Darwin.write(request.fd, pointer.advanced(by: sent), count - sent)
					if written < 0 {
						if errno == EINTR { continue }
						return
					}
					if written <= 0 { return }
					sent += written
				}
			}
		}
		// One request at a time: a second sudo while the panel is busy waits
		// for the password instead of queueing a nod behind the first.
		guard !check.isBusy else {
			Self.logger.notice("Denied a sudo request: another approval is already running.")
			reply("NO\n")
			return
		}
		// A truncated command hides what sudo would run, so it is never
		// approved: the user cannot consent to what they cannot see.
		guard !request.command.hasSuffix(Self.truncatedMarker) else {
			Self.logger.notice("Denied a sudo request: the command was truncated.")
			reply("NO\n")
			return
		}
		// The panel shows the exact command, middle-shortened to fit: reading
		// it is the consent, so it must be there and must be sudo's own words.
		let shown = request.command.count > 44
			? String(request.command.prefix(22)) + "…" + String(request.command.suffix(21))
			: request.command
		let pid = request.pid
		let outcome = await check.run(subject: "sudo \(shown)",
			// kill with signal 0 only tests existence; EPERM still means the
			// root-owned sudo is alive, so only a missing process ends this.
			isStillWanted: { kill(pid, 0) == 0 || errno == EPERM },
			onApproved: { true })
		switch outcome {
		case .approved:
			// The pid may have been reused while the panel was up, so the
			// peer is verified again before the OK leaves.
			guard Self.peerStillValid(fd: request.fd, pid: pid) else {
				Self.logger.notice("Denied a sudo request: the sudo process changed during approval.")
				reply("NO\n")
				return
			}
			// The command text is the user's own shell input; still logged
			// private so shell contents never reach the public log.
			Self.logger.notice("Approved a sudo request for: \(request.command, privacy: .private)")
			reply("OK\n")
		default:
			Self.logger.notice("Denied a sudo request: \(String(describing: outcome), privacy: .public)")
			reply("NO\n")
		}
	}

	private nonisolated static func address(_ path: String) throws -> sockaddr_un {
		var address = sockaddr_un()
		let bytes = Array(path.utf8) + [0]
		guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
			throw SudoApprovalError.socketPathTooLong
		}
		address.sun_family = sa_family_t(AF_UNIX)
		address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
		withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
		return address
	}

	// MARK: - Installer

	/// Whether /etc/pam.d/sudo_local currently routes sudo through Gaze.
	static var isInstalled: Bool {
		// Spacing-insensitive: an earlier Gaze wrote the same line with tab-like padding,
		// and an exact match left the switch off while sudo was already routed to Gaze.
		guard let text = try? String(contentsOfFile: SudoInstallScript.Paths().sudoLocalPath, encoding: .utf8),
			SudoInstallScript.routesThroughGaze(text) else { return false }
		// Without the requirement file the module trusts no listener, so a
		// missing file means the setup is not complete.
		return FileManager.default.fileExists(atPath: SudoInstallScript.Paths().requirementPath)
	}

	/// Reads this app's own designated requirement, which the installer writes
	/// out for the PAM module so it can recognize Gaze's listener.
	private static func designatedRequirement() throws -> String {
		let flags = SecCSFlags()
		var selfCode: SecCode?
		guard SecCodeCopySelf(flags, &selfCode) == errSecSuccess, let running = selfCode else {
			throw SudoApprovalError.requirementUnavailable
		}
		var staticCode: SecStaticCode?
		guard SecCodeCopyStaticCode(running, flags, &staticCode) == errSecSuccess, let code = staticCode else {
			throw SudoApprovalError.requirementUnavailable
		}
		var requirement: SecRequirement?
		guard SecCodeCopyDesignatedRequirement(code, flags, &requirement) == errSecSuccess,
			let value = requirement else {
			throw SudoApprovalError.requirementUnavailable
		}
		var text: CFString?
		guard SecRequirementCopyString(value, flags, &text) == errSecSuccess,
			let string = text as String?, !string.isEmpty else {
			throw SudoApprovalError.requirementUnavailable
		}
		return string
	}

	/// Copies pam_gaze.so into place, writes the listener requirement Gaze's
	/// module checks, and adds the sudo_local line, all inside one privileged
	/// shell script so the user authenticates only once. Throws when anything
	/// fails, including a script that ran but left sudo not routed to Gaze.
	static func install(moduleIn bundle: Bundle = .main) async throws {
		guard let source = bundle.resourceURL?.appendingPathComponent("pam_gaze.so").path,
			FileManager.default.fileExists(atPath: source) else {
			throw SudoApprovalError.moduleMissing
		}
		let requirement = try designatedRequirement()
		try await runPrivileged(SudoInstallScript.install(source: source, requirement: requirement))
		guard isInstalled else { throw SudoApprovalError.notInstalledAfterScript }
	}

	/// Removes the sudo_local line, the module, and the listener requirement,
	/// again as one privileged script. Other sudo_local lines are kept.
	static func uninstall() async throws {
		try await runPrivileged(SudoInstallScript.uninstall())
	}

	/// Runs the script with administrator privileges on a background thread:
	/// NSAppleScript blocks while the system prompts, and that must never
	/// freeze the app's main thread.
	private static func runPrivileged(_ shellScript: String) async throws {
		let scriptSource = SudoInstallScript.appleScript(shellScript)
		try await Task.detached(priority: .userInitiated) {
			var failure: NSDictionary?
			let script = NSAppleScript(source: scriptSource)
			guard script?.executeAndReturnError(&failure) != nil, failure == nil else {
				// -128 is the user cancelling the administrator prompt.
				if failure?[NSAppleScript.errorNumber] as? Int == -128 { throw SudoApprovalError.cancelled }
				let message = failure?[NSAppleScript.errorMessage] as? String ?? "the privileged script failed"
				logger.error("The sudo setup script failed: \(message, privacy: .public)")
				throw SudoApprovalError.scriptFailed(message)
			}
		}.value
	}
}

enum SudoApprovalError: LocalizedError {
	case moduleMissing
	case requirementUnavailable
	case socketPathTooLong
	case cancelled
	case notInstalledAfterScript
	case scriptFailed(String)

	var errorDescription: String? {
		switch self {
		case .moduleMissing:
			return "Gaze's sudo module (pam_gaze.so) is missing from the app bundle; reinstall Gaze to restore it."
		case .requirementUnavailable:
			return "Gaze could not read its own code signature; reinstall Gaze to restore it."
		case .socketPathTooLong:
			return "The sudo socket path is too long to bind."
		case .cancelled:
			return "The administrator prompt was cancelled."
		case .notInstalledAfterScript:
			return "The setup ran, but sudo still isn't set up to use Gaze."
		case .scriptFailed(let message):
			return "macOS reported: \(message)"
		}
	}
}
