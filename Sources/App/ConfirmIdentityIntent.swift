import AppIntents
import Foundation

/// Set by the app at launch so the Shortcuts action can reach the live check.
@MainActor
enum FaceApprovalCenter {
	static var check: FaceApprovalCheck?
}

/// Proves presence only: the person in front of the Mac showed an enrolled face
/// and nodded. The shortcut chooses the reason text, so this action must not gate
/// privileged steps such as admin access, payments, or keychain reveals.
struct ConfirmIdentityIntent: AppIntent {
	static var title: LocalizedStringResource = "Confirm It’s You"
	static var description = IntentDescription("Asks for your face and a nod, then continues the shortcut only if it’s you.")
	static var openAppWhenRun = false

	@Parameter(title: "Reason", default: "Continue this shortcut")
	var reason: String

	@MainActor static var callTimes: [Date] = []

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
		let now = Date()
		Self.callTimes = Self.callTimes.filter { now.timeIntervalSince($0) < 60 }
		guard Self.callTimes.count < 3 else { return Self.finished(.unavailable) }
		Self.callTimes.append(now)
		guard let check = FaceApprovalCenter.check else { return Self.finished(.unavailable) }
		let subject = "A shortcut asks: \(Self.truncated(reason))"
		let outcome = await check.run(subject: subject, isStillWanted: { true }, onApproved: { true })
		return Self.finished(outcome)
	}

	/// Always ends with words. With a bare value, a run from an automation or the
	/// widget leaves the system card on its spinner with nothing to say.
	@MainActor
	private static func finished(_ outcome: FaceApprovalCheck.Outcome) -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
		let text: String
		switch outcome {
		case .approved: text = "Confirmed it’s you."
		case .failed: text = "Couldn’t confirm it’s you."
		case .cancelled: text = "Stopped before Gaze could check."
		case .unavailable: text = "Gaze can’t check right now."
		}
		return .result(value: outcome == .approved, dialog: IntentDialog(stringLiteral: text))
	}

	private static func truncated(_ reason: String) -> String {
		let maxReason = 30
		guard reason.count > maxReason else { return reason }
		return String(reason.prefix(15)) + "…" + String(reason.suffix(14))
	}
}

struct GazeShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: ConfirmIdentityIntent(),
			phrases: ["Confirm it’s me with \(.applicationName)"],
			shortTitle: "Confirm It’s You",
			systemImageName: "faceid"
		)
	}
}
