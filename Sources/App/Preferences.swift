import Foundation
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

		var title: String {
			switch self {
			case .attached: return "Attached"
			case .island: return "Island"
			}
		}

		var detail: String {
			switch self {
			case .attached:
				return "Grows out of the notch, the way the Dynamic Island expands"
			case .island:
				return "A separate rounded panel that drops below the notch"
			}
		}
	}

	/// Where the Face ID mark sits while the panel is scanning.
	///
	/// Ruken's suggestion: rather than a large mark filling the middle, a small one tucked
	/// into a corner, leaving the panel free for whatever else is there. Both were wanted in
	/// the server, so both exist.
	enum GlyphPlacement: String, CaseIterable, Sendable {
		case centred
		case corner

		var title: String {
			switch self {
			case .centred: return "Centred"
			case .corner: return "Corner"
			}
		}
	}

	private enum Key {
		static let glyphPlacement = "notchGlyphPlacement"
		static let panelShape = "notchPanelShape"
		static let notchStyle = "notchStyle"
		static let notchTransparency = "notchTransparency"
		static let notchHeightAdjust = "notchHeightAdjust"
		static let notchWidthAdjust = "notchWidthAdjust"
		static let liveness = "livenessEnabled"
		static let touchIDFallback = "touchIDFallback"
		static let tamperProtection = "tamperProtection"
		static let requireBuiltInCamera = "requireBuiltInCamera"
		static let unlockBackend = "unlockBackend"
	}

	private let defaults = UserDefaults.standard

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

	/// 0 = fully opaque, 1 = fully clear. Only applies to the semi-glass style.
	var notchTransparency: Double {
		didSet { defaults.set(notchTransparency, forKey: Key.notchTransparency) }
	}

	/// Points added to the measured notch size, so a panel that sits slightly wrong on
	/// unusual hardware can be nudged rather than requiring a rebuild.
	var notchHeightAdjust: Double {
		didSet { defaults.set(notchHeightAdjust, forKey: Key.notchHeightAdjust) }
	}

	var notchWidthAdjust: Double {
		didSet { defaults.set(notchWidthAdjust, forKey: Key.notchWidthAdjust) }
	}

	private init() {
		livenessEnabled = defaults.bool(forKey: Key.liveness)
		touchIDFallback = defaults.object(forKey: Key.touchIDFallback) as? Bool ?? true
		tamperProtection = defaults.bool(forKey: Key.tamperProtection)
		requireBuiltInCamera = defaults.object(forKey: Key.requireBuiltInCamera) as? Bool ?? true
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
		notchTransparency = defaults.object(forKey: Key.notchTransparency) as? Double ?? 0.3
		notchHeightAdjust = defaults.double(forKey: Key.notchHeightAdjust)
		notchWidthAdjust = defaults.double(forKey: Key.notchWidthAdjust)
	}
}
