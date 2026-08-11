import Foundation
import XPC
import os

/// Answers the authorization plugin's "is this them?" question.
///
/// Runs in the logged-in user's session, which is the only place with camera access while
/// the screen is locked. The plugin cannot look at a face; this can. Everything it returns
/// is treated as untrusted by the plugin until the peer check and nonce both pass, so the
/// job here is simply to answer honestly and quickly.
@MainActor
final class UnlockService {

	static let serviceName = "app.faceid.unlock"

	/// Must match `kFaceIDVerdict*` in Plugin/FaceIDUnlockProtocol.h.
	enum Verdict: Int64 {
		case noMatch = 0
		case match = 1
		case lockedOut = 2
		case unavailable = 3
	}

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "UnlockService")

	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager
	private var listener: xpc_connection_t?

	/// How long to keep looking before giving up. Must stay under the plugin's timeout,
	/// or the plugin gives up first and the user sees a stall for no reason.
	private let searchTimeout: TimeInterval = 9

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
	}

	func start() {
		guard listener == nil else { return }

		let queue = DispatchQueue(label: "app.faceid.unlock.listener")
		let listener = xpc_connection_create_mach_service(
			Self.serviceName, queue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))

		xpc_connection_set_event_handler(listener) { [weak self] peer in
			guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
			self?.accept(peer)
		}
		xpc_connection_resume(listener)
		self.listener = listener
		Self.logger.notice("Listening on \(Self.serviceName).")
	}

	private nonisolated func accept(_ peer: xpc_connection_t) {
		xpc_connection_set_event_handler(peer) { [weak self] message in
			guard xpc_get_type(message) == XPC_TYPE_DICTIONARY else { return }
			self?.handle(message, from: peer)
		}
		xpc_connection_resume(peer)
	}

	private nonisolated func handle(_ message: xpc_object_t, from peer: xpc_connection_t) {
		guard let reply = xpc_dictionary_create_reply(message) else { return }

		// Echo the nonce back untouched. It is the plugin's proof that this reply belongs
		// to the request it just made, so altering or omitting it correctly invalidates us.
		var nonceLength = 0
		if let nonce = xpc_dictionary_get_data(message, "nonce", &nonceLength) {
			xpc_dictionary_set_data(reply, "nonce", nonce, nonceLength)
		}

		let command = xpc_dictionary_get_string(message, "command").map { String(cString: $0) }
		guard command == "authenticate" else {
			xpc_dictionary_set_int64(reply, "verdict", Verdict.unavailable.rawValue)
			xpc_connection_send_message(peer, reply)
			return
		}

		Task { @MainActor in
			let verdict = await self.authenticate()
			xpc_dictionary_set_int64(reply, "verdict", verdict.rawValue)
			xpc_connection_send_message(peer, reply)
		}
	}

	/// Looks for the enrolled face, up to the timeout.
	private func authenticate() async -> Verdict {
		guard lockout.mayAttempt() else {
			Self.logger.notice("Refusing: locked out.")
			return .lockedOut
		}
		guard let enrollment = store.enrollment else { return .unavailable }

		let camera = CameraController()
		// Pinned to the camera enrolled against, so a swapped or virtual device fails
		// rather than silently authenticating from a different sensor.
		await camera.start(pinnedDeviceID: Preferences.shared.requireBuiltInCamera
			? enrollment.cameraID : nil)
		defer { camera.stop() }

		guard camera.state == .running else {
			Self.logger.error("Camera unavailable: \(String(describing: camera.state))")
			return .unavailable
		}

		let deadline = Date().addingTimeInterval(searchTimeout)
		let liveness = Preferences.shared.livenessEnabled ? Liveness.detector() : nil

		while Date() < deadline {
			try? await Task.sleep(for: .milliseconds(80))
			guard !camera.faceMissing, let sample = camera.sample else { continue }

			let result = store.matches(sample)
			guard result.matched else { continue }

			// Only check liveness once the face already matches — it is the expensive
			// step, and running it on every passing stranger buys nothing.
			if let liveness {
				guard let score = liveness.score(sample), score >= liveness.threshold else {
					Self.logger.notice("Match rejected by liveness.")
					continue
				}
			}

			lockout.recordSuccess()
			Self.logger.notice("Recognised (score \(result.score)).")
			return .match
		}

		// A timeout is a failed attempt. Not counting it would let an attacker retry
		// forever simply by walking away before the deadline.
		lockout.recordFailure()
		return .noMatch
	}
}
