import AppKit
import ApplicationServices
import os

@MainActor
enum AutofillService {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Autofill")
	private static var isFilling = false
	static var isBusy: Bool { isFilling }
	private static let attemptBudget = AutofillAttemptBudget(
		load: { try SecureVault.load(AutofillAttemptBudget.State.self, from: "autofill-attempt-budget-v1") },
		save: { try SecureVault.store($0, as: "autofill-attempt-budget-v1") })

	enum Outcome {
		case filled(SavedApp)
		case noPlaceForApp(String)
		case noFocusedField
		case notAuthorised
		case faceRejected
		case noPassword
		case unverifiedApp(String)
		case identityMismatch(String)
		case browserBlocked
		case fieldNotWritable
		case disabled
		case busy
		case ownerRejected
		case retryBudgetReset
		case retryBudgetUnavailable

		/// Written for somebody looking at Settings wondering why nothing happened, so
		/// each case says what to do about it rather than naming the branch it took.
		var isSuccess: Bool {
			if case .filled = self { return true }
			return false
		}

		var summary: String {
			switch self {
			case .filled(let savedApp): "Filled \(savedApp.name)"
			case .noPlaceForApp(let app): "\(app) isn't saved here yet"
			case .noFocusedField: "No password box was focused"
			case .notAuthorised: "Accessibility access is needed"
			case .faceRejected: "Didn't recognise you"
			case .noPassword: "No password stored for that app"
			case .unverifiedApp(let app): "\(app) has no saved signature — save it again"
			case .identityMismatch(let app): "\(app) isn't the app this password was saved for"
			case .browserBlocked: "Browser autofill needs a trusted website integration"
			case .fieldNotWritable: "This password box doesn't support secure targeted filling"
			case .disabled: "Autofill is paused or canceled"
			case .busy: "An autofill check is already in progress"
			case .ownerRejected: "Autofill requires fresh Touch ID or macOS password approval"
			case .retryBudgetReset: "Autofill attempts reset. Focus the password box and try again"
			case .retryBudgetUnavailable: "Autofill retry protection is unavailable. No password was released"
			}
		}
	}

	/// The last thing that happened, and when.
	///
	/// Kept so Settings can show it. A feature that silently does nothing is impossible to
	/// debug from the outside — this is the difference between "it's broken" and "it says
	/// no password box was focused".
	private(set) static var lastOutcome: (outcome: Outcome, at: Date)?

	/// What the shortcut does.
	@discardableResult
	static func fillFrontmost(
		savedApps: SavedAppStore,
		store: FaceEnrollmentStore,
		capsule: NotchCapsuleController?,
		warmCamera: CameraController? = nil
	) async -> Outcome {
		guard !isFilling else { return .busy }
		isFilling = true
		defer { isFilling = false }
		let outcome = await attemptFill(
			savedApps: savedApps, store: store, capsule: capsule, warmCamera: warmCamera)
		lastOutcome = (outcome, Date())
		if case .filled = outcome {} else {
			logger.notice("Autofill did nothing: \(outcome.summary, privacy: .public)")
		}
		return outcome
	}

	private static func attemptFill(
		savedApps: SavedAppStore,
		store: FaceEnrollmentStore,
		capsule: NotchCapsuleController?,
		warmCamera: CameraController?
	) async -> Outcome {
		guard !Task.isCancelled, !Preferences.shared.isPaused else { return .disabled }
		let session = AutofillSessionLease()
		guard session.isValid else { return .disabled }

		guard AXIsProcessTrusted() else {
			logger.error("Autofill needs Accessibility access.")
			return .notAuthorised
		}

		// The frontmost app, captured before anything else happens. Gaze itself never
		// becomes frontmost here — the shortcut is global and this process stays in the
		// background — so this is the app the user is actually looking at.
		guard let app = NSWorkspace.shared.frontmostApplication,
			let bundleID = app.bundleIdentifier, app.launchDate != nil, !app.isTerminated
		else {
			return .noFocusedField
		}
		guard !AppIdentity.isBrowser(bundleID: bundleID) else { return .browserBlocked }

		guard let savedApp = savedApps.savedApp(forBundleID: bundleID) else {
			logger.notice("No saved savedApp for \(bundleID, privacy: .public).")
			return .noPlaceForApp(app.localizedName ?? bundleID)
		}

		// Checked before the password is read, not after.
		//
		// A record saved before requirements existed has nothing to check against, and the
		// safe reading of that is "unknown", not "fine". Filling it would preserve exactly
		// the weakness this closes for precisely the people who set the app up earliest.
		guard let requirement = savedApp.requirement, !requirement.isEmpty else {
			logger.error(
				"\(savedApp.name, privacy: .public) has no saved signing requirement.")
			return .unverifiedApp(savedApp.name)
		}
		guard appIsPinned(app, savedApp: savedApp),
			AppIdentity.process(app.processIdentifier, matches: requirement) else {
			logger.error(
				"\(bundleID, privacy: .public) does not satisfy its saved requirement.")
			return .identityMismatch(app.localizedName ?? bundleID)
		}

		guard let target = secureTarget(for: app.processIdentifier) else {
			logger.notice("No secure field belongs to the verified app.")
			return .noFocusedField
		}
		var isSettable: DarwinBoolean = false
		guard AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &isSettable)
			== .success, isSettable.boolValue
		else { return .fieldNotWritable }
		guard attemptBudget.reserve() else {
			guard await AutofillOwnerApproval.authorize(session: session,
				reason: "Gaze needs owner approval to reset its autofill retry limit.") else { return .ownerRejected }
			guard session.isValid, !Preferences.shared.isPaused else { return .disabled }
			return attemptBudget.resetAfterOwnerApproval() ? .retryBudgetReset : .retryBudgetUnavailable
		}
		capsule?.show(phase: .scanning)
		defer { capsule?.hide(after: 1.0) }
		let recognised = await FaceCheck.authenticate(using: store, warm: warmCamera) {
			session.isValid && savedApps.savedApp(forBundleID: bundleID) == savedApp
				&& targetIsCurrent(target, app: app, requirement: requirement)
				&& appIsPinned(app, savedApp: savedApp)
		}
		guard recognised else {
			capsule?.update(phase: .notRecognised)
			return .faceRejected
		}
		guard session.isValid, !Preferences.shared.isPaused else { return .disabled }
		let release = await AutofillReleaseGate.release(isCurrent: {
			session.isValid && !Preferences.shared.isPaused
				&& savedApps.savedApp(forBundleID: bundleID) == savedApp
				&& appIsPinned(app, savedApp: savedApp)
				&& targetIsCurrent(target, app: app, requirement: requirement)
				&& !AppIdentity.isBrowser(bundleID: bundleID)
		}, approve: {
			await AutofillOwnerApproval.authorize(session: session,
				reason: "Approve filling the focused password field in \(savedApp.name).")
		}, resetBudget: { attemptBudget.resetAfterOwnerApproval() }, read: {
			try savedApps.password(for: savedApp)
		}, write: { password in
			AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, password as CFString) == .success
		})
		switch release {
		case .filled: break
		case .ownerRejected: return .ownerRejected
		case .stale: return .disabled
		case .budgetUnavailable: return .retryBudgetUnavailable
		case .noPassword: return .noPassword
		case .fieldNotWritable: return .fieldNotWritable
		}

		capsule?.update(phase: .success)
		logger.notice("Filled \(savedApp.name, privacy: .public).")
		return .filled(savedApp)
	}

	private static func appIsPinned(_ app: NSRunningApplication, savedApp: SavedApp) -> Bool {
		guard let selected = savedApp.applicationURL, let running = app.bundleURL,
			selected.isFileURL, running.isFileURL else { return false }
		return selected.standardizedFileURL.resolvingSymlinksInPath()
			== running.standardizedFileURL.resolvingSymlinksInPath()
	}

	private static func targetIsCurrent(
		_ target: AXUIElement, app: NSRunningApplication, requirement: String
	) -> Bool {
		guard !app.isTerminated, let launchDate = app.launchDate,
			let current = NSWorkspace.shared.frontmostApplication,
			current.processIdentifier == app.processIdentifier,
			current.launchDate == launchDate,
			current.bundleIdentifier == app.bundleIdentifier,
			AppIdentity.process(current.processIdentifier, matches: requirement),
			let focused = secureTarget(for: current.processIdentifier)
		else { return false }
		return CFEqual(target, focused)
	}

	private static func secureTarget(for processID: pid_t) -> AXUIElement? {
		let element = focusedElement(of: AXUIElementCreateSystemWide())
			?? focusedElement(of: AXUIElementCreateApplication(processID))
		guard let element else { return nil }
		var owner: pid_t = 0
		guard AXUIElementGetPid(element, &owner) == .success, owner == processID,
			classify(role: string(of: element, kAXRoleAttribute),
				subrole: string(of: element, kAXSubroleAttribute)) == .secure
		else { return nil }
		return element
	}

	// MARK: - Accessibility

	enum Field {
		case secure
		case plain
	}

	/// What was seen the last time focus was inspected, for the diagnostic row in Settings.
	///
	/// The single most useful thing this feature can report. When a fill does not happen
	/// the question is always "which step gave up", and without this the answer is
	/// invisible — the app simply does nothing, which is indistinguishable from the
	/// shortcut not being registered, the face not matching, or the field not being found.
	struct FocusReport {
		let app: String
		let role: String?
		let subrole: String?
		let field: Field?

		var summary: String {
			guard let field else {
				let seen = role ?? "nothing"
				return "\(app): focus is \(seen) — not a text field"
			}
			return field == .secure
				? "\(app): password box focused"
				: "\(app): text field focused (not marked secure)"
		}
	}

	private(set) static var lastFocusReport: FocusReport?

	/// What has keyboard focus, if it is somewhere text can go.
	static func focusedField() -> Field? {
		inspectFocus().field
	}

	/// Looks in two places, because one is not enough.
	///
	/// The system-wide focused element is the right first question and the only one the
	/// original version asked. It is regularly nil: an app that draws its own controls —
	/// Electron, Catalyst, anything with a custom text view — often does not publish focus
	/// to the system-wide element even though its own application element knows perfectly
	/// well what is focused. Password managers are disproportionately those apps, which is
	/// the worst possible overlap for this feature.
	///
	/// So: system-wide first, then ask the frontmost application directly.
	@discardableResult
	static func inspectFocus() -> FocusReport {
		let app = NSWorkspace.shared.frontmostApplication
		let name = app?.localizedName ?? "Unknown app"

		var element = focusedElement(of: AXUIElementCreateSystemWide())
		if element == nil, let pid = app?.processIdentifier {
			element = focusedElement(of: AXUIElementCreateApplication(pid))
		}

		guard let element else {
			let report = FocusReport(app: name, role: nil, subrole: nil, field: nil)
			lastFocusReport = report
			return report
		}

		let role = string(of: element, kAXRoleAttribute)
		let subrole = string(of: element, kAXSubroleAttribute)
		let report = FocusReport(
			app: name, role: role, subrole: subrole, field: classify(role: role, subrole: subrole))
		lastFocusReport = report
		return report
	}

	/// Two spellings of the same thing. AppKit reports a secure field as a text field with
	/// a secure subrole; Catalyst, Electron and anything drawing its own controls often
	/// report the role directly instead.
	private static func classify(role: String?, subrole: String?) -> Field? {
		if role == "AXSecureTextField" || subrole == "AXSecureTextField" { return .secure }
		if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String {
			return .plain
		}
		return nil
	}

	private static func focusedElement(of element: AXUIElement) -> AXUIElement? {
		var focused: AnyObject?
		guard
			AXUIElementCopyAttributeValue(
				element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
			let focused,
			CFGetTypeID(focused) == AXUIElementGetTypeID()
		else { return nil }
		return (focused as! AXUIElement)
	}

	private static func string(of element: AXUIElement, _ attribute: String) -> String? {
		var value: AnyObject?
		guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
		else { return nil }
		return value as? String
	}
}
