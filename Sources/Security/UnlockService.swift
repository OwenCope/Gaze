import Foundation
import XPC
import os

@MainActor
final class UnlockService {
	static let serviceName = "com.gazeunlock.Gaze.unlock"

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "UnlockService")
	private var listener: xpc_connection_t?

	init(store _: FaceEnrollmentStore, lockout _: LockoutManager) {}

	func start() {
		guard listener == nil else { return }
		let queue = DispatchQueue(label: "com.gazeunlock.Gaze.unlock.listener")
		let listener = xpc_connection_create_mach_service(
			Self.serviceName, queue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
		xpc_connection_set_event_handler(listener) { peer in
			guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
			xpc_connection_set_event_handler(peer) { message in
				guard xpc_get_type(message) == XPC_TYPE_DICTIONARY,
					let reply = xpc_dictionary_create_reply(message)
				else { return }
				var nonceLength = 0
				if let nonce = xpc_dictionary_get_data(message, "nonce", &nonceLength), nonceLength == 32 {
					xpc_dictionary_set_data(reply, "nonce", nonce, nonceLength)
				}
				xpc_dictionary_set_int64(reply, "verdict", 3)
				xpc_connection_send_message(peer, reply)
			}
			xpc_connection_resume(peer)
		}
		xpc_connection_resume(listener)
		self.listener = listener
		Self.logger.notice("Face-only XPC authorization is disabled; requests return unavailable.")
	}
}
