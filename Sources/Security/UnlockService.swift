import Darwin
import Foundation
import Security
import XPC
import os

/// SPI: libxpc exports this but the SDK publishes no header. The audit token is filled
/// in by the kernel and identifies the peer unambiguously, unlike a PID which can be
/// recycled between check and use.
@_silgen_name("xpc_connection_get_audit_token")
private func GazeXPCConnectionGetAuditToken(_ connection: xpc_connection_t, _ token: UnsafeMutablePointer<audit_token_t>)

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
				// Identity first, mirroring Plugin PeerTrust: an unverified peer only ever
				// gets unavailable, and any future verdict besides unavailable must stay
				// behind this same check. Fails closed — every error refuses.
				guard Self.peerIsTrusted(peer) else {
					xpc_dictionary_set_int64(reply, "verdict", 3)
					xpc_connection_send_message(peer, reply)
					Self.logger.error("Unlock request from an untrusted peer; refusing.")
					return
				}
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

	/// Confirms the peer is our SecurityAgent plugin, via its kernel-supplied audit token
	/// checked against a code-signing requirement. Mirrors `GazePeerSatisfiesRequirement`
	/// in Plugin/PeerTrust.c. Returns false on every error, including an ad-hoc-signed
	/// agent whose team identifier cannot be pinned.
	private static func peerIsTrusted(_ peer: xpc_connection_t) -> Bool {
		var token = audit_token_t()
		withUnsafeMutablePointer(to: &token) { GazeXPCConnectionGetAuditToken(peer, $0) }
		let auditData = withUnsafeBytes(of: token) { Data($0) }
		var guest: SecCode?
		guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit as String: auditData] as CFDictionary, [], &guest) == errSecSuccess, let guest else { return false }
		var ownCode: SecCode?
		var staticCode: SecStaticCode?
		var information: CFDictionary?
		guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
			SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode,
			SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
			let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
			team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
		else { return false }
		let requirementText = "anchor apple generic and identifier \"com.gazeunlock.Gaze.plugin\" and certificate leaf[subject.OU] = \"\(team)\""
		var requirement: SecRequirement?
		guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
		return SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
	}
}
