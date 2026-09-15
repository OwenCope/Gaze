import AppKit
import Combine

@MainActor
final class PasswordBrowserService: ObservableObject {
	@Published private(set) var request: BrowserMessage?
	@Published private(set) var verifying = false
	@Published private(set) var status = "Browser connection is starting…"
	@Published private(set) var gazeStatus = "Gaze connection has not been checked."
	@Published private(set) var checkingGaze = false
	@Published private(set) var saveUsername: String?
	@Published private(set) var saveAction = "Save password"
	@Published private(set) var lastBrowserContact: Date?
	private var saveApproved = false
	@Published private(set) var gazeSummary = "Not checked"
	var serviceSummary: String {
		PasswordsBuild.isUIReview ? "Disabled" : listener == nil ? "Unavailable" : "Listening"
	}
	private var listener: BrowserSocketListener?
	private var chosenID: UUID?
	private var cancelled = false
	private var gazeConnection: BrowserSocket?
	private let store: LocalPasswordStore
	private let makeSession: @MainActor () -> AutofillSessionLease
	private let activateVault: @MainActor () -> Void
	private let applicationIsActive: @MainActor () -> Bool
	private let connectGaze: @MainActor () throws -> BrowserSocket
	private let launchGaze: @MainActor () async throws -> Void

	init(store: LocalPasswordStore,
		makeSession: @escaping @MainActor () -> AutofillSessionLease = { AutofillSessionLease() },
		activateVault: @escaping @MainActor () -> Void = {
			NSApp.activate(ignoringOtherApps: true)
			for window in NSApp.windows where window.identifier?.rawValue == "vault" || window.title == PasswordsBuild.title {
				window.makeKeyAndOrderFront(nil)
			}
		}, applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
		connectGaze: @escaping @MainActor () throws -> BrowserSocket = {
			try BrowserSocket.connect(path: BrowserAppLocator.socketPath("gaze.sock"), peer: "com.gazeunlock.Gaze")
		}, launchGaze: @escaping @MainActor () async throws -> Void = {
			try await BrowserAppLocator.open(identifier: "com.gazeunlock.Gaze", name: "Gaze", arguments: ["--agent", "--browser-only"])
		}) {
		self.store = store
		self.makeSession = makeSession
		self.activateVault = activateVault
		self.applicationIsActive = applicationIsActive
		self.connectGaze = connectGaze
		self.launchGaze = launchGaze
	}

	func start() {
		guard !PasswordsBuild.isUIReview else { status = "UI review · Vault and browser connections are disabled"; return }
		guard listener == nil else { return }
		do {
			listener = try BrowserSocketListener(name: "passwords.sock", peer: "com.gazeunlock.Passwords.BrowserBridge") { [weak self] message in
				guard let self else { throw BrowserBridgeError.unavailable }
				return try await self.handle(message)
			}
			status = "Ready for the Gaze browser extension"
		} catch { status = "Browser connection unavailable. Close other Gaze Passwords copies, then reopen this app." }
	}

	func approve(_ identifier: UUID) { chosenID = identifier }
	func cancel() { cancelled = true; gazeConnection?.close() }
	func approveSave() { if request?.operation == "save", !store.isLocked, saveUsername != nil { saveApproved = true } }

	func checkGazeConnection() async {
		guard !PasswordsBuild.isUIReview, !checkingGaze, request == nil else { return }
		checkingGaze = true
		defer { checkingGaze = false }
		do {
			let connection = try connectGaze()
			let deadline = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { connection.close() } }
			defer { deadline.cancel(); connection.close() }
			let message = BrowserMessage(operation: "status", requestID: UUID(), origin: try BrowserOrigin("https://gaze.invalid"))
			let exchange = Task.detached { try connection.write(message); return try connection.read() }
			let reply = try await withTaskCancellationHandler { try await exchange.value } onCancel: { connection.close(); exchange.cancel() }
			var lease = BrowserRequestLease(message)
			guard lease.consume(reply), reply.operation == "status", reply.approved == nil, reply.username == nil, reply.password == nil else { throw BrowserBridgeError.invalidRequest }
			gazeStatus = reply.error ?? "Connected to Gaze. Camera verification runs only when you approve a browser request."
			gazeSummary = reply.error == nil ? "Connected" : "Needs attention"
		} catch {
			gazeSummary = "Unavailable"
			gazeStatus = "Gaze’s approval service is unavailable. Relaunch the updated Gaze app, then check again. No camera or password was accessed."
		}
	}

	func handle(_ message: BrowserMessage) async throws -> BrowserMessage {
		try message.validateClientRequest()
		if message.operation == "status" {
			do {
				let session = makeSession()
				defer { session.invalidate() }
				guard session.isValid else { throw BrowserBridgeError.unavailable }
				lastBrowserContact = .now
				return message.response(operation: "status")
			}
		}
		// A second fill/save while one is pending is rejected quietly: the owning
		// request is still in flight, so there is no failure to report. Publishing
		// here would pop a failure alert over the live approval and leave it stale
		// after the owner completes that approval.
		guard request == nil else { throw BrowserBridgeError.unavailable }
		do {
			lastBrowserContact = .now
			if message.operation == "save" { return try await handleSave(message) }
			return try await handleRequest(message)
		}
		catch {
			if !cancelled, !Task.isCancelled, store.errorMessage == nil {
				store.errorMessage = message.operation == "save"
					? "The browser save request did not complete. Check your saved login before trying again."
					: "Browser approval did not complete. Keep Passwords open, confirm Gaze is ready, and try again. Nothing was filled."
			}
			throw error
		}
	}

	private func handleSave(_ message: BrowserMessage) async throws -> BrowserMessage {
		guard request == nil else { throw BrowserBridgeError.unavailable }
		let consoleSession = makeSession()
		guard consoleSession.isValid else { throw BrowserBridgeError.cancelled }
		request = message.response(operation: "save")
		cancelled = false
		saveApproved = false
		saveUsername = nil
		// A new approval supersedes any earlier failure text; without this the
		// outer catch in handle(_:) would keep the stale message and suppress fresh ones.
		store.errorMessage = nil
		consoleSession.onInvalidation = { [weak self] in self?.cancel(); self?.store.lock() }
		defer {
			consoleSession.onInvalidation = nil
			consoleSession.invalidate()
			request = nil; saveUsername = nil; saveApproved = false; saveAction = "Save password"
		}
		var lease = BrowserRequestLease(message)
		activateVault()
		while store.isLocked {
			try Task.checkCancellation()
			guard !cancelled, consoleSession.isValid, lease.permits(message) else { throw BrowserBridgeError.cancelled }
			try await Task.sleep(for: .milliseconds(100))
		}
		let session = store.sessionID
		let revision = store.archive?.revision
		let proposal: BrowserSaveProposal
		do { proposal = try BrowserSaveProposal(message: message, entries: store.archive?.entries ?? []) }
		catch { store.errorMessage = error.localizedDescription; throw error }
		saveUsername = proposal.entry.username
		saveAction = proposal.unchanged ? "Keep saved password" : proposal.existingID == nil ? "Save password" : "Update password"
		while !saveApproved {
			try Task.checkCancellation()
			guard !cancelled, consoleSession.isValid, lease.permits(message), !store.isLocked,
				store.sessionID == session, store.archive?.revision == revision else { throw BrowserBridgeError.cancelled }
			try await Task.sleep(for: .milliseconds(100))
		}
		try Task.checkCancellation()
		guard !cancelled, consoleSession.isValid, applicationIsActive(), !store.isLocked,
			store.sessionID == session, store.archive?.revision == revision, lease.consume(message) else { throw BrowserBridgeError.cancelled }
		if !proposal.unchanged {
			do { try store.save(proposal.entry) }
			catch { store.errorMessage = error.localizedDescription; throw error }
		}
		store.showEntry(proposal.entry.id)
		return message.response(operation: "saved", approved: true)
	}

	private func handleRequest(_ message: BrowserMessage) async throws -> BrowserMessage {
		try message.validateRequest(operation: "fill")
		guard request == nil else { throw BrowserBridgeError.unavailable }
		let consoleSession = makeSession()
		guard consoleSession.isValid else { throw BrowserBridgeError.cancelled }
		request = message
		chosenID = nil
		cancelled = false
		// A new approval supersedes any earlier failure text; without this the
		// outer catch in handle(_:) would keep the stale message and suppress fresh ones.
		store.errorMessage = nil
		consoleSession.onInvalidation = { [weak self] in self?.cancel(); self?.store.lock() }
		defer {
			consoleSession.onInvalidation = nil
			consoleSession.invalidate()
			request = nil; chosenID = nil; verifying = false; gazeConnection = nil
		}
		var lease = BrowserRequestLease(message)
		activateVault()
		while chosenID == nil {
			try Task.checkCancellation()
			guard !cancelled, consoleSession.isValid, lease.permits(message) else { throw BrowserBridgeError.cancelled }
			try await Task.sleep(for: .milliseconds(100))
		}
		guard let identifier = chosenID, consoleSession.isValid, !store.isLocked, applicationIsActive(),
			store.archive?.entries.contains(where: { $0.id == identifier && $0.origin == message.origin }) == true else {
			throw BrowserBridgeError.cancelled
		}
		let session = store.sessionID
		let revision = store.archive?.revision
		verifying = true
		var connected: BrowserSocket?
		do { connected = try connectGaze() }
		catch BrowserBridgeError.unavailable { }
		if connected == nil {
			try Task.checkCancellation()
			guard !cancelled, consoleSession.isValid, !store.isLocked, store.sessionID == session,
				store.archive?.revision == revision, applicationIsActive(), lease.permits(message) else { throw BrowserBridgeError.cancelled }
			try await launchGaze()
		}
		let startupDeadline = ContinuousClock.now.advanced(by: .seconds(15))
		while connected == nil && ContinuousClock.now < startupDeadline {
			try Task.checkCancellation()
			guard !cancelled, consoleSession.isValid, !store.isLocked, store.sessionID == session,
				store.archive?.revision == revision, applicationIsActive(), lease.permits(message) else { throw BrowserBridgeError.cancelled }
			do { connected = try connectGaze() }
			catch BrowserBridgeError.unavailable { }
			if connected != nil { break }
			try await Task.sleep(for: .milliseconds(150))
		}
		guard let connection = connected else {
			store.errorMessage = "Gaze’s approval service is unavailable. Relaunch the updated Gaze app, then try again. No password was filled."
			throw BrowserBridgeError.unavailable
		}
		gazeConnection = connection
		defer { connection.close() }
		try Task.checkCancellation()
		guard !cancelled, consoleSession.isValid, !store.isLocked, store.sessionID == session,
			store.archive?.revision == revision, applicationIsActive(), lease.permits(message) else { throw BrowserBridgeError.cancelled }
		let exchange = Task.detached {
			try connection.write(message.response(operation: "verify"))
			return try connection.read()
		}
		let reply = try await withTaskCancellationHandler {
			try await exchange.value
		} onCancel: { connection.close(); exchange.cancel() }
		try Task.checkCancellation()
		guard !cancelled, consoleSession.isValid, !store.isLocked, store.sessionID == session, store.archive?.revision == revision,
			applicationIsActive(), reply.operation == "verified", reply.approved == true,
			reply.username == nil, reply.password == nil, reply.error == nil,
			lease.consume(reply), let entry = store.archive?.entries.first(where: { $0.id == identifier && $0.origin == message.origin }) else {
			throw BrowserBridgeError.cancelled
		}
		var response = message.response(operation: "filled", approved: true)
		response.username = entry.username
		response.password = entry.password
		return response
	}
}
