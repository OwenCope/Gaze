import AppKit
import ApplicationServices
import os

/// Fills a saved password into whatever field is in front of you, once your face agrees.
///
/// Two things call this. `AutofillWatcher` calls it when a saved app comes forward showing
/// a focused secure field — the case that matters, because the moment worth automating is
/// the app appearing, not a keystroke afterwards. The ⌥⌘G shortcut calls it directly, and
/// is the manual path: it also accepts a plain text field, and it works in an app that was
/// already frontmost.
///
/// The original design was shortcut-only, on the reasoning that watching for password
/// fields would mean an Accessibility observer over every app on the Mac. That reasoning
/// was sound and the conclusion was wrong — `didActivateApplication` is a single
/// notification the system already posts, so the watching costs nothing and the shortcut
/// stops being the only way in.
///
/// The field is never submitted. `KeystrokeUnlockBackend` presses Return because the login
/// window has exactly one thing you can do with a password; an app might be a sign-up form,
/// a re-auth sheet, or a field whose Return key means something else entirely. Filling and
/// letting the user commit is what every password manager does, and for the same reason.
@MainActor
enum AutofillService {

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Autofill")

	enum Outcome {
		case filled(SavedApp)
		case noPlaceForApp(String)
		case noFocusedField
		case notAuthorised
		case faceRejected
		case noPassword

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

		guard AXIsProcessTrusted() else {
			logger.error("Autofill needs Accessibility access.")
			return .notAuthorised
		}

		// The frontmost app, captured before anything else happens. Gaze itself never
		// becomes frontmost here — the shortcut is global and this process stays in the
		// background — so this is the app the user is actually looking at.
		guard let app = NSWorkspace.shared.frontmostApplication,
			let bundleID = app.bundleIdentifier
		else {
			return .noFocusedField
		}

		guard let savedApp = savedApps.savedApp(forBundleID: bundleID) else {
			logger.notice("No saved savedApp for \(bundleID, privacy: .public).")
			return .noPlaceForApp(app.localizedName ?? bundleID)
		}

		guard let field = focusedField() else {
			logger.notice("Nothing focused that text can be typed into.")
			return .noFocusedField
		}

		let password: String?
		do {
			password = try savedApps.password(for: savedApp)
		} catch {
			logger.error("Could not read the stored password for \(savedApp.name, privacy: .public).")
			return .noPassword
		}
		guard let password, !password.isEmpty else { return .noPassword }

		// The face check goes last, after everything that could fail cheaply. Opening the
		// camera and asking someone to look at it, only to then discover there was no
		// password saved, would be the wrong order to find that out in.
		capsule?.show(phase: .scanning)
		let recognised = await FaceCheck.authenticate(using: store, warm: warmCamera)
		guard recognised else {
			capsule?.update(phase: .notRecognised)
			capsule?.hide(after: 1.2)
			return .faceRejected
		}
		capsule?.update(phase: .success)
		capsule?.hide(after: 1.0)

		// Re-read the frontmost app. The camera check takes a second or two, and typing a
		// password into whatever happened to come forward in the meantime — a notification,
		// a colleague's Slack — is the one mistake this must never make.
		guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
			logger.error("The frontmost app changed during the face check; not typing.")
			return .noFocusedField
		}

		switch field {
		case .secure:
			// Focus is already in the password box. Typing the username here would put it
			// in the password field in plain intent and then tab away from the thing the
			// user actually wanted filled.
			Keystrokes.type(password)
		case .plain:
			// A plain field with a username saved reads as "the login form, at the top".
			// Fill both. With no username there is nothing to distinguish this from a
			// password field that simply is not marked secure, so treat it as one.
			if savedApp.username.isEmpty {
				Keystrokes.type(password)
			} else {
				Keystrokes.type(savedApp.username)
				Keystrokes.press(.tab)
				Keystrokes.type(password)
			}
		}

		logger.notice("Filled \(savedApp.name, privacy: .public).")
		return .filled(savedApp)
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
			let focused
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
