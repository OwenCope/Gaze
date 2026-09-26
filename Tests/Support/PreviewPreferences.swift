import Foundation

enum Preferences {
	enum NotchStyle: String, CaseIterable, Sendable {
		case normal, semiLiquidGlass, liquidGlass
		var title: String {
			switch self {
			case .normal: "Normal"
			case .semiLiquidGlass: "Semi Liquid Glass"
			case .liquidGlass: "Liquid Glass"
			}
		}
	}

	enum PanelShape: String, CaseIterable, Sendable {
		case attached, island, dynamicIsland = "minimal"
		var title: String {
			switch self {
			case .attached: "Connected"
			case .island: "Floating"
			case .dynamicIsland: "Dynamic Island"
			}
		}
	}

	enum GlyphPlacement: String, CaseIterable, Sendable {
		case centred, ear
		var title: String { self == .centred ? "In the panel" : "On the ear" }
	}
}
