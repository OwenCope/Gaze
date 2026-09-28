import Foundation

/// One searchable row in Settings.
///
/// Foundation-only on purpose: the matching logic is compiled unchanged into a
/// small regression harness, so it must not import SwiftUI or touch preferences,
/// the keychain, the camera, enrolment or any security state. A result only
/// *navigates* — SettingsView maps `pane` back through `SettingsPane(rawValue:)`
/// and scrolls to `section`. Nothing here reads `PasswordVault.password` or
/// triggers a toggle, permission prompt or enrolment.
struct SettingsSearchItem: Identifiable, Hashable, Sendable {
	/// Stable across launches; used as the result row id and the scroll-task key.
	let id: String
	let title: String
	let subtitle: String
	let keywords: [String]
	/// A `SettingsPane` raw value (`face`, `general`, `notch`, `about`, `credits`).
	let pane: String
	/// The `ScrollViewReader` anchor in the detail scroll view (`hero`,
	/// `unlockSection`, …, `aboutSection`).
	let section: String

	/// Declared display order. `results(for:)` filters but never re-sorts, so
	/// matches always come back in this order.
	static let all: [SettingsSearchItem] = [
		SettingsSearchItem(
			id: "unlock",
			title: "Unlock my Mac",
			subtitle: "Use face recognition on the lock screen",
			keywords: ["unlock", "unlocking", "backend", "recognition", "keystroke"],
			pane: "face",
			section: "unlockSection"
		),
		SettingsSearchItem(
			id: "password",
			title: "Account password",
			subtitle: "Store or revoke the password typed after verification",
			keywords: ["password", "passcode", "store", "stored", "revoke", "change"],
			pane: "face",
			section: "unlockSection"
		),
		SettingsSearchItem(
			id: "screen-glow",
			title: "Light up the screen when it’s dark",
			subtitle: "Turns up the brightness so the camera can see you",
			keywords: ["light", "dark", "glow", "night", "brightness"],
			pane: "face",
			section: "unlockSection"
		),
		SettingsSearchItem(
			id: "mask-unlock",
			title: "Unlock with a mask",
			subtitle: "Unlock while wearing a mask or glasses",
			keywords: ["mask", "glasses", "covering", "face"],
			pane: "face",
			section: "unlockSection"
		),
		SettingsSearchItem(
			id: "camera-permission",
			title: "Camera",
			subtitle: "Permission for Gaze to see you",
			keywords: ["camera", "permission", "permissions", "privacy", "allow"],
			pane: "face",
			section: "permissionsSection"
		),
		SettingsSearchItem(
			id: "accessibility-permission",
			title: "Accessibility",
			subtitle: "Permission for Gaze to type your password",
			keywords: ["accessibility", "permission", "permissions", "typing", "type"],
			pane: "face",
			section: "permissionsSection"
		),
		SettingsSearchItem(
			id: "built-in-camera",
			title: "Only trust the built-in camera",
			subtitle: "Pin recognition to the enrolled camera",
			keywords: ["built-in", "builtin", "camera", "pin", "security", "hardening"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "movements",
			title: "Movements to unlock this Mac",
			subtitle: "How many completed responses unlocking requires",
			keywords: ["movement", "movements", "challenge", "challenges", "liveness"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "sensitivity",
			title: "Recognition sensitivity",
			subtitle: "How strictly a face must match to unlock",
			keywords: ["sensitivity", "sensitive", "threshold", "strict", "relaxed", "matching", "dim"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "usb-cameras",
			title: "Allow USB cameras",
			subtitle: "Use a USB webcam with the lid closed",
			keywords: ["usb", "camera", "external", "webcam", "clamshell", "lid closed", "display"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "walk-away",
			title: "Lock when I walk away",
			subtitle: "Lock after absence is confirmed",
			keywords: ["walk", "away", "walk-away", "walkaway", "absence", "auto-lock", "lock"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "touch-id",
			title: "Ask before removing a face or changing the stored password",
			subtitle: "Ask macOS to confirm sensitive changes",
			keywords: ["touch", "touch id", "touchid", "biometric", "confirm", "authorization"],
			pane: "face",
			section: "securitySection"
		),
		SettingsSearchItem(
			id: "faces",
			title: "Enrolled faces",
			subtitle: "Add, rename or remove the faces that unlock this Mac",
			keywords: ["face", "faces", "enroll", "enrol", "enrollment", "enrolment", "add", "remove", "rename", "portrait"],
			pane: "face",
			section: "hero"
		),
		SettingsSearchItem(
			id: "open-at-login",
			title: "Open at login",
			subtitle: "Start Gaze with this Mac; it watches from the menu bar",
			keywords: ["login", "startup", "launch", "menu", "bar", "background", "behaviour", "behavior"],
			pane: "general",
			section: "behaviourSection"
		),
		SettingsSearchItem(
			id: "quit-password",
			title: "Ask for a password before quitting",
			subtitle: "Tamper protection for the running app",
			keywords: ["quit", "tamper", "password", "protection"],
			pane: "general",
			section: "behaviourSection"
		),
		SettingsSearchItem(
			id: "onboarding",
			title: "Getting Started",
			subtitle: "Review setup and onboarding",
			keywords: ["setup", "onboarding", "welcome", "getting started", "guide"],
			pane: "general",
			section: "onboardingSection"
		),
		SettingsSearchItem(
			id: "updates",
			title: "Updates",
			subtitle: "Installed version and released builds",
			keywords: ["update", "updates", "release", "releases", "version", "download", "check"],
			pane: "general",
			section: "updatesSection"
		),
		SettingsSearchItem(
			id: "appearance",
			title: "Theme",
			subtitle: "Appearance of Settings and onboarding",
			keywords: ["appearance", "theme", "dark", "light", "glass", "system", "color", "colour"],
			pane: "general",
			section: "appearanceSection"
		),
		SettingsSearchItem(
			id: "notch",
			title: "Notch panel",
			subtitle: "How the panel under the notch looks",
			keywords: ["notch", "panel", "style", "dynamic island", "island", "capsule", "caption", "captions", "instructions"],
			pane: "notch",
			section: "NotchSettingsSection"
		),
		SettingsSearchItem(
			id: "about",
			title: "About Gaze",
			subtitle: "What this app is, and what it isn't",
			keywords: ["about", "version", "model", "website", "release notes", "support", "face id", "source", "source folder", "checkout", "rebuild", "repository"],
			pane: "about",
			section: "aboutSection"
		),
		SettingsSearchItem(
			id: "credits",
			title: "Credits",
			subtitle: "The people whose work this is built on",
			keywords: ["credits", "acknowledgements", "thanks", "contributors"],
			pane: "credits",
			section: "creditsSection"
		),
	]

	/// Matches in declared order. The query is trimmed, folded for case and
	/// diacritics, and split on whitespace; every token must appear somewhere
	/// in the item's title, subtitle or keywords. Blank queries match nothing.
	static func results(for query: String) -> [SettingsSearchItem] {
		let tokens = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
		guard !tokens.isEmpty else { return [] }
		return all.filter { item in
			let haystack = normalized(([item.title, item.subtitle] + item.keywords).joined(separator: " "))
			return tokens.allSatisfy { haystack.contains($0) }
		}
	}

	private static func normalized(_ text: String) -> String {
		text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
	}
}
