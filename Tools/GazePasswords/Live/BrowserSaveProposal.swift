import Foundation

struct BrowserSaveProposal {
	let entry: PasswordEntry
	let existingID: UUID?
	let unchanged: Bool

	init(message: BrowserMessage, entries: [PasswordEntry]) throws {
		try message.validateClientRequest()
		guard message.operation == "save", let username = message.username, let password = message.password else {
			throw BrowserBridgeError.invalidRequest
		}
		let matching = entries.filter { $0.origin == message.origin && $0.username == username }
		guard matching.count <= 1 else { throw SaveError.ambiguous }
		if var existing = matching.first {
			existingID = existing.id
			unchanged = existing.password == password
			existing.password = password
			existing.modifiedAt = .now
			entry = existing
		} else {
			existingID = nil
			unchanged = false
			entry = PasswordEntry(title: URLComponents(string: message.origin.value)?.host ?? message.origin.value,
				origin: message.origin, username: username, password: password)
		}
		try entry.validate()
	}

	enum SaveError: LocalizedError {
		case ambiguous
		var errorDescription: String? { "More than one saved login matches this website and username. Choose the entry to edit in Gaze Passwords; none was overwritten." }
	}
}
