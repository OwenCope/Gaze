import Foundation

enum BrowserBridgeError: LocalizedError {
	case invalidRequest, insecureOrigin, unavailable, cancelled, untrustedPeer, tooLarge
	var errorDescription: String? {
		switch self {
		case .invalidRequest: "The browser request is invalid or expired. Try again from the website."
		case .insecureOrigin: "Gaze fills only exact HTTPS website addresses."
		case .unavailable: "The companion app is not available. Open it and try again."
		case .cancelled: "The request was cancelled. Nothing was filled."
		case .untrustedPeer: "The requesting application could not be verified."
		case .tooLarge: "The request exceeds the supported size."
		}
	}
}

struct BrowserOrigin: Codable, Hashable {
	let value: String

	init(_ input: String) throws {
		guard input.utf8.count <= 2048, !input.contains("\\"),
			let parts = URLComponents(string: input), parts.scheme?.lowercased() == "https",
			parts.user == nil, parts.password == nil,
			parts.query == nil, parts.fragment == nil,
			parts.path.isEmpty || parts.path == "/",
			let host = parts.host?.lowercased(), !host.isEmpty,
			host.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || ".-:[]".unicodeScalars.contains($0)) }),
			!host.hasSuffix("."), parts.port.map({ (1...65535).contains($0) }) ?? true
		else { throw BrowserBridgeError.insecureOrigin }
		let port = parts.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? ""
		value = "https://\(host)\(port)"
	}

	init(from decoder: Decoder) throws {
		try self.init(decoder.singleValueContainer().decode(String.self))
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(value)
	}
}

struct BrowserMessage: Codable {
	var version = 1
	var operation: String
	var requestID: UUID
	var origin: BrowserOrigin
	var username: String?
	var password: String?
	var approved: Bool?
	var error: String?

	func validateRequest(operation expected: String) throws {
		guard version == 1, operation == expected, username == nil, password == nil,
			approved == nil, error == nil else { throw BrowserBridgeError.invalidRequest }
	}

	func validateClientRequest() throws {
		if operation == "status" { try validateRequest(operation: "status"); return }
		if operation == "fill" { try validateRequest(operation: "fill"); return }
		guard version == 1, operation == "save", approved == nil, error == nil,
			let username, username.utf8.count <= 4096,
			let password, !password.isEmpty, password.utf8.count <= 16384 else { throw BrowserBridgeError.invalidRequest }
	}

	func response(operation: String, approved: Bool? = nil, error: String? = nil) -> Self {
		Self(operation: operation, requestID: requestID, origin: origin, approved: approved, error: error)
	}
}

struct BrowserRequestLease {
	private let requestID: UUID
	private let origin: BrowserOrigin
	private let startedAt: ContinuousClock.Instant
	private var consumed = false
	static let lifetime: Duration = .seconds(90)

	init(_ request: BrowserMessage, now: ContinuousClock.Instant = .now) {
		requestID = request.requestID
		origin = request.origin
		startedAt = now
	}

	func permits(_ request: BrowserMessage, now: ContinuousClock.Instant = .now) -> Bool {
		!consumed && request.version == 1 && request.requestID == requestID && request.origin == origin
			&& startedAt <= now && startedAt.duration(to: now) < Self.lifetime
	}

	mutating func consume(_ request: BrowserMessage, now: ContinuousClock.Instant = .now) -> Bool {
		guard permits(request, now: now) else { return false }
		consumed = true
		return true
	}
}
