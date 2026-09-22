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
			case .normal: return "Normal"
			case .semiLiquidGlass: return "Semi Liquid Glass"
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

		/// A matched pair, which "Attached" and "Island" were not: one described a
		/// relationship, the other described an object, so the two never read as two answers
		/// to the same question. Both of these say what the panel *does*.
		var title: String {
			switch self {
			case .attached: return "Connected"
			case .island: return "Floating"
			}
		}

		var detail: String {
			switch self {
			case .attached:
				return "Grows out of the notch, the way the Dynamic Island expands"
			case .island:
				return "A separate rounded panel that floats below the notch"
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
	/// for another completed response. There is deliberately no zero/off option
	/// for Mac unlock: the count only feeds the movement gate, never whether
	/// recognition itself runs.
	enum UnlockMovementCount: Int, CaseIterable, Sendable {
		case one = 1
		case two = 2

		var title: String {
			switch self {
			case .one: return "One movement"
			case .two: return "Two movements (recommended)"
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

	private enum Key {
		static let appTheme = "appTheme"
		static let glyphPlacement = "notchGlyphPlacement"
		static let panelShape = "notchPanelShape"
		static let notchStyle = "notchStyle"
		static let notchTransparency = "notchTransparency"
		static let showNotchCaptions = "showNotchCaptions"
		static let notchHeightAdjust = "notchHeightAdjust"
		static let notchWidthAdjust = "notchWidthAdjust"
		static let liveness = "livenessEnabled"
		static let touchIDFallback = "touchIDFallback"
		static let tamperProtection = "tamperProtection"
		static let requireBuiltInCamera = "requireBuiltInCamera"
		static let unlockMovementCount = "unlockMovementCount"
		static let unlockBackend = "unlockBackend"
		static let pausedUntil = "pausedUntil"
		static let walkAwayLock = "walkAwayLock"
		static let autofillOnActivation = "autofillOnActivation"
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

	/// Fill automatically when a saved app comes forward showing a password box.
	///
	/// Off by default. Filling types into another app unprompted, so it stays opt-in.
	var autofillOnActivation: Bool {
		didSet { defaults.set(autofillOnActivation, forKey: Key.autofillOnActivation) }
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

	/// Anti-spoof checking on captured frames.
	///
	/// Off by default: it costs latency on every unlock, it needs a model that isn't
	/// bundled, and it does not defend against the attack that actually matters here
	/// (frame injection — see `CameraDevice`).
	var livenessEnabled: Bool {
		didSet { defaults.set(livenessEnabled, forKey: Key.liveness) }
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

	/// Completed responses required for Mac unlock; existing installations default to two.
	var unlockMovementCount: UnlockMovementCount {
		didSet { defaults.set(unlockMovementCount.rawValue, forKey: Key.unlockMovementCount) }
	}

	var unlockBackend: UnlockBackendKind {
		didSet { defaults.set(unlockBackend.rawValue, forKey: Key.unlockBackend) }
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
		autofillOnActivation = defaults.bool(forKey: Key.autofillOnActivation)
		livenessEnabled = defaults.bool(forKey: Key.liveness)
		touchIDFallback = defaults.object(forKey: Key.touchIDFallback) as? Bool ?? true
		tamperProtection = defaults.bool(forKey: Key.tamperProtection)
		requireBuiltInCamera = defaults.object(forKey: Key.requireBuiltInCamera) as? Bool ?? true
		unlockMovementCount = UnlockMovementCount.resolve(
			stored: defaults.object(forKey: Key.unlockMovementCount))
		unlockBackend =
			defaults.string(forKey: Key.unlockBackend)
			.flatMap(UnlockBackendKind.init(rawValue:)) ?? .none

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
