import Foundation
import CoreFoundation
import SwiftUI
import Observation

/// User-facing feature switches.
///
/// Anything that weakens security is off by default and anything that strengthens it is
/// opt-in only where it costs something — so the defaults are the ones a person would
/// pick if they never opened this screen.
///
/// Every setting is a *stored* property that persists on `didSet`, rather than a computed
/// wrapper around `UserDefaults`. That is not a style choice: `@Observable` only tracks
/// stored properties, so computed accessors change the value without ever telling SwiftUI,
/// and the UI silently stops reflecting reality — radio buttons that refuse to move,
/// toggles that snap back.
@Observable
@MainActor
final class Preferences {

	static let shared = Preferences()

	/// How the notch panel is drawn.
	enum NotchStyle: String, CaseIterable, Sendable {
		case normal
		case semiLiquidGlass
		case liquidGlass

		var title: String {
			switch self {
			case .normal: return "Solid"
			case .semiLiquidGlass: return "Frosted glass"
			case .liquidGlass: return "Liquid Glass"
			}
		}
	}

	/// Whether the panel hangs off the notch or detaches from it.
	///
	/// Nebulark's idea, and Owen's refinement of it: rather than the panel growing out of
	/// the housing, a separate rounded island pops out below it — the shape Apple Pay drops
	/// from the Dynamic Island. Kept as a setting rather than a replacement because the two
	/// read very differently and people wanted different things in the server.
	enum PanelShape: String, CaseIterable, Sendable {
		/// Grows out of the housing, square across the top, rounded below.
		case attached
		/// A separate rounded island, detached from the notch and floating under it.
		case island
		/// A floating capsule under the notch, like iPhone. Stored as "minimal" so
		/// existing saved preferences still decode.
		case dynamicIsland = "minimal"

		/// A matched pair, which "Attached" and "Island" were not: one described a
		/// relationship, the other described an object, so the two never read as two answers
		/// to the same question. Both of these say what the panel *does*.
		var title: String {
			switch self {
			case .attached: return "Connected"
			case .island: return "Floating"
			case .dynamicIsland: return "Dynamic Island"
			}
		}

		var detail: String {
			switch self {
			case .attached:
				return "Grows out of the notch, the way the Dynamic Island expands"
			case .island:
				return "A separate rounded panel that floats below the notch"
			case .dynamicIsland:
				return "A floating capsule under the notch, like iPhone"
			}
		}
	}

	/// Where the Gaze mark appears while Gaze is running.
	///
	/// Ruken's suggestion, and Sapphire's behaviour: rather than a panel dropping out with a
	/// large mark in it, a small mark on the *ear* — the strip of screen beside the camera
	/// housing — so nothing ever covers the lock screen. The panel stays put and the menu bar
	/// band carries the whole thing.
	enum GlyphPlacement: String, CaseIterable, Sendable {
		/// A panel drops out of the notch with the mark in the middle of it.
		case centred
		/// The mark sits beside the cutout, opposite the padlock. Nothing drops.
		case ear = "corner"

		var title: String {
			switch self {
			case .centred: return "In the panel"
			case .ear: return "On the ear"
			}
		}
	}

	/// How the app's own windows are drawn.
	enum AppTheme: String, CaseIterable, Sendable {
		/// Whatever the Mac is set to.
		case system
		case light
		case dark
		/// The notch panel's own material: dark at the top, thinning to clear at the foot.
		case glass

		var title: String {
			switch self {
			case .system: return "Follow system"
			case .light: return "Light"
			case .dark: return "Dark"
			case .glass: return "Semi Liquid Glass"
			}
		}

		/// Nil means "do not force one", which is what following the system means.
		var colorScheme: ColorScheme? {
			switch self {
			case .light: return .light
			// Dark, and not by preference. The glass theme is a *black* gradient thinning
			// downward, so the ground is dark whatever the Mac is set to — light labels on
			// it would be the one combination that cannot be read.
			case .dark, .glass: return .dark
			case .system: return nil
			}
		}
	}

	/// How many completed movement responses Mac unlock asks for.
	///
	/// Two is the default for new and existing users. One is quicker and two asks
	/// for another completed response. None skips the movement prompt and relies
	/// on face match plus the photo and screen checks.
	enum UnlockMovementCount: Int, CaseIterable, Sendable {
		case none = 0
		case one = 1
		case two = 2

		var title: String {
			switch self {
			case .none: return "No movement (less secure)"
			case .one: return "One movement"
			case .two: return "Two movements (recommended)"
			}
		}

		/// The name under each step of the Settings slider.
		var shortTitle: String {
			switch self {
			case .none: return "None"
			case .one: return "One"
			case .two: return "Two"
			}
		}

		/// Missing or invalid stored values fall back to `.two`, so installations
		/// that predate this setting keep their current behaviour.
		static func resolve(stored: Any?) -> UnlockMovementCount {
			guard let number = stored as? NSNumber,
				CFGetTypeID(number) != CFBooleanGetTypeID(),
				let count = Int(exactly: number.doubleValue) else { return .two }
			return UnlockMovementCount(rawValue: count) ?? .two
		}
	}

	/// How strictly a face must match its enrolment to unlock.
	enum RecognitionSensitivity: String, CaseIterable, Sendable {
		case relaxed
		case standard
		case strict

		var title: String {
			switch self {
			case .relaxed: return "Relaxed"
			case .standard: return "Standard (recommended)"
			case .strict: return "Strict"
			}
		}

		/// The name under each step of the Settings slider.
		var shortTitle: String {
			switch self {
			case .relaxed: return "Relaxed"
			case .standard: return "Standard"
			case .strict: return "Strict"
			}
		}

		/// Added to the embedder's match threshold. Relaxed helps in dim rooms;
		/// strict is harder to fool.
		var thresholdOffset: Float {
			switch self {
			case .relaxed: return -0.08
			case .standard: return 0
			case .strict: return 0.05
			}
		}
	}


	private enum Key {
		static let appTheme = "appTheme"
		static let glyphPlacement = "notchGlyphPlacement"
		static let panelShape = "notchPanelShape"
		static let notchStyle = "notchStyle"
		static let notchTransparency = "notchTransparency"
		static let showNotchCaptions = "showNotchCaptions"
		static let notchHeightAdjust = "notchHeightAdjust"
		static let notchWidthAdjust = "notchWidthAdjust"
		static let touchIDFallback = "touchIDFallback"
		static let tamperProtection = "tamperProtection"
		static let requireBuiltInCamera = "requireBuiltInCamera"
		static let allowExternalCamera = "allowExternalCamera"
		static let unlockMovementCount = "unlockMovementCount"
		static let lookMovement = "lookMovement"
		static let disabledMovements = "disabledMovements"
		static let recognitionSensitivity = "recognitionSensitivity"
		static let detectionDistance = "detectionDistance"
		static let showsMenuBarIcon = "showsMenuBarIcon"
		static let unlockBackend = "unlockBackend"
		static let pausedUntil = "pausedUntil"
		static let walkAwayLock = "walkAwayLock"
		static let screenGlowInDark = "screenGlowInDark"
		static let unlockWithMask = "unlockWithMask"
	}

	private let defaults: UserDefaults

	/// How long "pause" can mean.
	///
	/// Deliberately short options and no "until I turn it back on". A pause you can forget
	/// about is a security feature that quietly stopped running, and the whole reason this
	/// exists is the five minutes where you are screen-sharing or handing the Mac to
	/// somebody — not a way to disable Gaze without admitting it. Turning it off properly
	/// is a setting, and it should look like one.
	enum PauseSpan: String, CaseIterable, Identifiable {
		case fifteen
		case thirty
		case hour

		var id: String { rawValue }

		var seconds: TimeInterval {
			switch self {
			case .fifteen: 15 * 60
			case .thirty: 30 * 60
			case .hour: 60 * 60
			}
		}

		var title: String {
			switch self {
			case .fifteen: "For 15 Minutes"
			case .thirty: "For 30 Minutes"
			case .hour: "For 1 Hour"
			}
		}
	}

	/// Lock the Mac when nobody is in front of it.
	///
	/// Off by default. It is the one setting here that can act on its own — everything else
	/// Gaze does happens because the user locked the screen or the Mac woke up, and this
	/// takes an action unprompted. Something like that should be opted into.
	var walkAwayLock: Bool {
		didSet { defaults.set(walkAwayLock, forKey: Key.walkAwayLock) }
	}

	/// When a temporary pause runs out, or nil when Gaze is armed.
	///
	/// Persisted rather than held in memory, so quitting and relaunching does not silently
	/// re-arm something the user deliberately switched off. Storing the *end time* rather
	/// than a countdown is what makes that work: a pause set before a reboot is either
	/// still in the future or it has expired, and both answers are correct without anyone
	/// having to keep a timer alive.
	var pausedUntil: Date? {
		didSet { defaults.set(pausedUntil, forKey: Key.pausedUntil) }
	}

	/// Whether Gaze should stay out of the way right now.
	///
	/// Reads through `pausedUntil` rather than caching, because the answer changes with
	/// the clock and nothing posts a notification when a deadline passes.
	var isPaused: Bool {
		guard let pausedUntil else { return false }
		return pausedUntil > Date()
	}

	/// Ends a pause early.
	func resume() { pausedUntil = nil }

	/// Pauses for a while. Pausing again replaces the deadline rather than extending it,
	/// which is what "pause for 15 minutes" says on the tin.
	func pause(for duration: TimeInterval) {
		pausedUntil = Date().addingTimeInterval(duration)
	}

	/// Anti-spoof checking on captured frames: always on.
	///
	/// It used to be a switch, off by default. Turning off the check that stops a photo
	/// from unlocking the Mac is not a preference anyone should be offered, and the
	/// model now ships with the app. Kept as a property so callers and the unlock
	/// readiness check read one place; setting it does nothing.
	var livenessEnabled: Bool {
		get { true }
		set {}
	}

	/// Use Touch ID to authorise changes inside the app — un-enrolling, storing a
	/// password. Separate from lock-screen Touch ID.
	var touchIDFallback: Bool {
		didSet { defaults.set(touchIDFallback, forKey: Key.touchIDFallback) }
	}

	/// Require administrator authentication to quit the app.
	var tamperProtection: Bool {
		didSet { defaults.set(tamperProtection, forKey: Key.tamperProtection) }
	}

	/// Refuse to authenticate from virtual or external cameras.
	///
	/// On by default, and there is no good reason to turn it off — it exists as a switch
	/// only so the failure is diagnosable when someone's camera reports oddly.
	var requireBuiltInCamera: Bool {
		didSet { defaults.set(requireBuiltInCamera, forKey: Key.requireBuiltInCamera) }
	}

	var allowExternalCamera: Bool {
		didSet { defaults.set(allowExternalCamera, forKey: Key.allowExternalCamera) }
	}

	/// Completed responses required for Mac unlock; existing installations default to two.
	var unlockMovementCount: UnlockMovementCount {
		didSet { defaults.set(unlockMovementCount.rawValue, forKey: Key.unlockMovementCount) }
	}

	/// Whether "Look at the light" is one of the movements Gaze picks from. On by default.
	var lookMovement: Bool {
		didSet { defaults.set(lookMovement, forKey: Key.lookMovement) }
	}

	/// Movements Gaze may not ask for, as LivenessChallenge.Movement raw values
	/// ("turn", "nod", "blink", "openMouth", "followLight"). Empty means all.
	var disabledMovements: Set<String> {
		didSet { defaults.set(Array(disabledMovements).sorted(), forKey: Key.disabledMovements) }
	}

	/// Strictness of the lock-screen face match; existing installations default to standard.
	var recognitionSensitivity: RecognitionSensitivity {
		didSet { defaults.set(recognitionSensitivity.rawValue, forKey: Key.recognitionSensitivity) }
	}

	/// How far away Gaze can recognise a face; existing installations default to standard.
	var detectionDistance: DetectionDistance {
		didSet { defaults.set(detectionDistance.rawValue, forKey: Key.detectionDistance) }
	}

	/// Whether Gaze keeps its icon in the menu bar. On by default.
	var showsMenuBarIcon: Bool {
		didSet {
			defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
			NotificationCenter.default.post(name: .gazeMenuBarVisibilityChanged, object: nil)
		}
	}

	var unlockBackend: UnlockBackendKind {
		didSet { defaults.set(unlockBackend.rawValue, forKey: Key.unlockBackend) }
	}

	/// Whether the lock screen may light its edges in a dark room so the camera
	/// can see a face. On by default.
	var screenGlowInDark: Bool {
		didSet { defaults.set(screenGlowInDark, forKey: Key.screenGlowInDark) }
	}

	/// Whether a face may unlock while wearing a mask, matched on the upper face
	/// only. Off by default, and only offered for faces enrolled with upper-face
	/// prints.
	var unlockWithMask: Bool {
		didSet { defaults.set(unlockWithMask, forKey: Key.unlockWithMask) }
	}

	// MARK: - Notch

	var notchStyle: NotchStyle {
		didSet { defaults.set(notchStyle.rawValue, forKey: Key.notchStyle) }
	}

	var panelShape: PanelShape {
		didSet { defaults.set(panelShape.rawValue, forKey: Key.panelShape) }
	}

	var glyphPlacement: GlyphPlacement {
		didSet { defaults.set(glyphPlacement.rawValue, forKey: Key.glyphPlacement) }
	}

	var appTheme: AppTheme {
		didSet { defaults.set(appTheme.rawValue, forKey: Key.appTheme) }
	}

	/// 0 = fully opaque, 1 = fully clear. Only applies to the semi-glass style.
	var notchTransparency: Double {
		didSet { defaults.set(notchTransparency, forKey: Key.notchTransparency) }
	}

	/// Whether the notch companion shows movement guidance and status text.
	///
	/// Display only: it hides the caption words and their symbols, never the mark
	/// itself, and it changes nothing about what Gaze checks or when it unlocks.
	var showNotchCaptions: Bool {
		didSet { defaults.set(showNotchCaptions, forKey: Key.showNotchCaptions) }
	}

	/// Points added to the measured notch size, so a panel that sits slightly wrong on
	/// unusual hardware can be nudged rather than requiring a rebuild.
	var notchHeightAdjust: Double {
		didSet { defaults.set(notchHeightAdjust, forKey: Key.notchHeightAdjust) }
	}

	var notchWidthAdjust: Double {
		didSet { defaults.set(notchWidthAdjust, forKey: Key.notchWidthAdjust) }
	}

	private convenience init() {
		self.init(defaults: .standard)
	}

	init(defaults: UserDefaults) {
		self.defaults = defaults
		pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
		walkAwayLock = defaults.bool(forKey: Key.walkAwayLock)
		touchIDFallback = defaults.object(forKey: Key.touchIDFallback) as? Bool ?? true
		tamperProtection = defaults.bool(forKey: Key.tamperProtection)
		requireBuiltInCamera = defaults.object(forKey: Key.requireBuiltInCamera) as? Bool ?? true
		allowExternalCamera = defaults.object(forKey: Key.allowExternalCamera) as? Bool ?? false
		unlockMovementCount = UnlockMovementCount.resolve(
			stored: defaults.object(forKey: Key.unlockMovementCount))
		lookMovement = defaults.object(forKey: Key.lookMovement) as? Bool ?? true
		disabledMovements = Set(defaults.stringArray(forKey: Key.disabledMovements)
			?? (defaults.object(forKey: Key.lookMovement) as? Bool == false ? ["followLight"] : []))
		recognitionSensitivity =
			defaults.string(forKey: Key.recognitionSensitivity)
			.flatMap(RecognitionSensitivity.init(rawValue:)) ?? .standard
		detectionDistance =
			defaults.string(forKey: Key.detectionDistance)
			.flatMap(DetectionDistance.init(rawValue:)) ?? .standard
		showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
		unlockBackend =
			defaults.string(forKey: Key.unlockBackend)
			.flatMap(UnlockBackendKind.init(rawValue:)) ?? .none
		screenGlowInDark = defaults.object(forKey: Key.screenGlowInDark) as? Bool ?? true
		unlockWithMask = defaults.object(forKey: Key.unlockWithMask) as? Bool ?? false

		notchStyle =
			defaults.string(forKey: Key.notchStyle)
			.flatMap(NotchStyle.init(rawValue:)) ?? .normal
		panelShape =
			defaults.string(forKey: Key.panelShape)
			.flatMap(PanelShape.init(rawValue:)) ?? .attached
		glyphPlacement =
			defaults.string(forKey: Key.glyphPlacement)
			.flatMap(GlyphPlacement.init(rawValue:)) ?? .centred
		appTheme =
			defaults.string(forKey: Key.appTheme)
			.flatMap(AppTheme.init(rawValue:)) ?? .system
		notchTransparency = defaults.object(forKey: Key.notchTransparency) as? Double ?? 0.3
		if let storedCaptions = defaults.object(forKey: Key.showNotchCaptions) as? NSNumber,
			CFGetTypeID(storedCaptions) == CFBooleanGetTypeID() {
			showNotchCaptions = storedCaptions.boolValue
		} else {
			showNotchCaptions = true
		}
		notchHeightAdjust = defaults.double(forKey: Key.notchHeightAdjust)
		notchWidthAdjust = defaults.double(forKey: Key.notchWidthAdjust)
	}
}

extension Notification.Name {
	/// Posted from `showsMenuBarIcon`'s didSet so the menu bar icon follows the setting.
	static let gazeMenuBarVisibilityChanged = Notification.Name("GazeMenuBarVisibilityChanged")
}
