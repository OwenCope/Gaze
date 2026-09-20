import Darwin
import Foundation
import Security

enum BrowserPeerTrust {
	static func signingTeam() throws -> String {
		var ownCode: SecCode?
		var staticCode: SecStaticCode?
		var information: CFDictionary?
		guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
			SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode,
			SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
			let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
			team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
		else { throw BrowserBridgeError.untrustedPeer }
		return team
	}

	static func samePublisher(identifier: String) throws -> String {
		guard identifier.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else {
			throw BrowserBridgeError.untrustedPeer
		}
		return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(try signingTeam())\""
	}

	static func verify(socket: Int32, identifier: String) throws {
		var token = audit_token_t()
		var size = socklen_t(MemoryLayout.size(ofValue: token))
		guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
			size == MemoryLayout.size(ofValue: token), token.val.1 == geteuid() else {
			throw BrowserBridgeError.untrustedPeer
		}
		let data = withUnsafeBytes(of: token) { Data($0) }
		try verify(attributes: [kSecGuestAttributeAudit as String: data], requirement: samePublisher(identifier: identifier))
	}

	static func verifyNativeBrowserParent() throws {
		let parent = getppid()
		guard parent > 1 else { throw BrowserBridgeError.untrustedPeer }
		let browsers = [
			("com.browseros.BrowserClaw", "8YMKWU47S5"),
			("com.google.Chrome", "EQHXZ8M8AV"),
			("com.microsoft.edgemac", "UBF8T346G9"),
			("com.brave.Browser", "KL8N8XSYF4")
		]
		let alternatives = browsers.map { identifier, team in
			"((identifier \"\(identifier)\" or identifier \"\(identifier).helper\") and certificate leaf[subject.OU] = \"\(team)\")"
		}.joined(separator: " or ")
		try verify(attributes: [kSecGuestAttributePid as String: parent], requirement: "anchor apple generic and (\(alternatives))")
		guard getppid() == parent else { throw BrowserBridgeError.untrustedPeer }
	}

	static func verifyApplication(_ url: URL, identifier: String) throws {
		var code: SecStaticCode?
		var requirement: SecRequirement?
		guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
			SecRequirementCreateWithString(try samePublisher(identifier: identifier) as CFString, [], &requirement) == errSecSuccess,
			SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
		else { throw BrowserBridgeError.untrustedPeer }
	}

	private static func verify(attributes: [String: Any], requirement text: String) throws {
		var code: SecCode?
		var requirement: SecRequirement?
		guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess, let code,
			SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
			SecCodeCheckValidity(code, [], requirement) == errSecSuccess
		else { throw BrowserBridgeError.untrustedPeer }
	}
}
