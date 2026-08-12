import AppKit
import SwiftUI

/// Design tokens.
///
/// Face ID is dark on every Apple platform and accents in the system green, so the whole
/// palette is derived from those two facts rather than following the system appearance.
enum Theme {

	// MARK: - Colour

	/// Opaque ground, for the windows that are not vibrant — enrolment and the recognition
	/// test, both of which are full of camera preview and want no wallpaper behind them.
	static let background = Color(red: 0.078, green: 0.078, blue: 0.082)

	/// Sits *over* the window's vibrancy rather than replacing it, so the wallpaper still
	/// comes through. An opaque fill here is what made the window read as a flat web page
	/// dropped on the desktop instead of a Mac window.
	static let contentScrim = Color.black.opacity(0.16)
	static let sidebarScrim = Color.clear

	/// Group fill. Frosted rather than dark: the window is translucent now, so a group has
	/// to lift *off* the wallpaper with light instead of sinking into it with black.
	static let surface = Color.white.opacity(0.13)
	static let surfaceRaised = Color.white.opacity(0.18)
	static let separator = Color.white.opacity(0.13)

	// MARK: - Icon palette

	/// Apple's own settings icons are colour-coded, and colour is what makes an icon column
	/// worth having: a row of identical grey tiles adds a shape to every line without
	/// telling you anything, which is why they read as filler.
	static let blue = Color(red: 0.04, green: 0.52, blue: 1.00)
	static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
	static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
	static let pink = Color(red: 1.00, green: 0.18, blue: 0.33)
	static let teal = Color(red: 0.19, green: 0.69, blue: 0.78)
	static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
	static let grey = Color(red: 0.56, green: 0.56, blue: 0.58)

	static let label = Color.white
	static let secondaryLabel = Color.white.opacity(0.55)
	static let tertiaryLabel = Color.white.opacity(0.35)

	/// Controls are neutral.
	///
	/// Tinting every switch, slider and icon green made the whole window read as one
	/// undifferentiated colour, so the green stopped meaning anything. Reserving it for
	/// Face ID itself — the glyph, the enrolment ring, the success tick — is what gives it
	/// back its meaning: green here says *recognised*, not *this is a control*.
	static let accent = Color.white

	/// Apple's system green. Face ID identity only, never chrome.
	static let faceID = Color(red: 0.20, green: 0.78, blue: 0.35)
	static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
	static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

	// MARK: - Metrics

	static let cornerRadius: CGFloat = 12
	static let rowInset: CGFloat = 13
	static let sectionSpacing: CGFloat = 20
}

// MARK: - Window background

/// The window's vibrancy layer.
///
/// `NSVisualEffectView` rather than a SwiftUI material: materials inside the content view
/// blur whatever the *window* has behind them, which on an opaque window is nothing. Only
/// a view backing the window itself samples the desktop.
struct VibrantBackground: NSViewRepresentable {
	var material: NSVisualEffectView.Material = .sidebar

	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = TransparentHostView()
		view.material = material
		view.blendingMode = .behindWindow
		view.state = .active
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {
		view.material = material
	}

	/// Clears the window behind itself.
	///
	/// `behindWindow` blending samples the desktop *through* the window, which it can only
	/// do while the window is not opaque. SwiftUI's `Window` ships opaque with a solid
	/// background, so the material had nothing to sample and rendered as flat grey — the
	/// window looked painted rather than glazed.
	private final class TransparentHostView: NSVisualEffectView {
		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			window?.isOpaque = false
			window?.backgroundColor = .clear
		}
	}
}

// MARK: - Section

/// A titled group of rows.
///
/// Sentence case, not caps. Uppercased letterspaced headers are an iOS convention that
/// macOS dropped in Ventura.
struct SettingsSection<Content: View>: View {

	let title: String?
	var footer: String?
	@ViewBuilder var content: Content

	init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
		self.title = title
		self.footer = footer
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 7) {
			if let title {
				Text(title)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(Theme.label)
					.padding(.leading, 4)
			}

			VStack(spacing: 0) {
				content
			}
			.background(
				Theme.surface,
				in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous)
			)
			.clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))

			if let footer {
				Text(footer)
					.font(.system(size: 11))
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, 4)
			}
		}
	}
}

/// Hairline between rows, inset to line up with the labels rather than the group edge.
struct RowDivider: View {
	/// Rows with an icon tile need a deeper inset so the rule starts under the label.
	var inset: CGFloat = 51

	var body: some View {
		Rectangle()
			.fill(Theme.separator)
			.frame(height: 1)
			.padding(.leading, inset)
	}
}

/// A rounded, tinted square holding an SF Symbol.
///
/// Rows of pure text are hard to scan — the eye has to read every line to find the one it
/// wants. A consistent icon column gives each row a shape you can navigate by.
struct IconTile: View {
	let symbol: String
	var tint: Color = Theme.grey
	var isEnabled = true

	var body: some View {
		RoundedRectangle(cornerRadius: 6.5, style: .continuous)
			.fill(isEnabled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Theme.grey.opacity(0.35)))
			.frame(width: 24, height: 24)
			.overlay {
				Image(systemName: symbol)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white)
					.opacity(isEnabled ? 1 : 0.6)
			}
	}
}

// MARK: - Rows

/// A row with a title, optional explanation, and trailing control.
struct SettingRow<Trailing: View>: View {

	let title: String
	var detail: String?
	/// SF Symbol shown in a tinted tile at the leading edge.
	var symbol: String?
	var symbolTint: Color = Theme.grey
	var isEnabled = true
	@ViewBuilder var trailing: Trailing

	var body: some View {
		HStack(spacing: 12) {
			if let symbol {
				IconTile(symbol: symbol, tint: symbolTint, isEnabled: isEnabled)
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(size: 13))
					.foregroundStyle(isEnabled ? Theme.label : Theme.tertiaryLabel)
				if let detail {
					Text(detail)
						.font(.system(size: 11))
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			Spacer(minLength: 8)
			trailing
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 9)
		.frame(minHeight: 42)
	}
}

/// A switch row.
struct SettingToggle: View {

	let title: String
	var detail: String?
	var symbol: String?
	var symbolTint: Color = Theme.grey
	var isEnabled = true
	@Binding var isOn: Bool

	var body: some View {
		SettingRow(
			title: title, detail: detail, symbol: symbol, symbolTint: symbolTint,
			isEnabled: isEnabled
		) {
			Toggle("", isOn: $isOn)
				.labelsHidden()
				.toggleStyle(.switch)
				.controlSize(.small)
				.tint(Theme.accent)
				.disabled(!isEnabled)
		}
	}
}

/// A labelled slider with its value in a pill.
///
/// The pill matters: a bare slider tells you there is a value but not what it is, so any
/// adjustment becomes trial and error.
struct SliderRow: View {

	let title: String
	var symbol: String?
	var symbolTint: Color = Theme.grey
	@Binding var value: Double
	let range: ClosedRange<Double>
	var format: (Double) -> String

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
				if let symbol {
					IconTile(symbol: symbol, tint: symbolTint)
				}
				Text(title)
					.font(.system(size: 13))
					.foregroundStyle(Theme.label)
				Spacer()
				Text(format(value))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(Theme.secondaryLabel)
					.padding(.horizontal, 9)
					.padding(.vertical, 3)
					.background(Capsule().fill(Theme.surfaceRaised))
					.contentTransition(.numericText())
			}

			VStack(spacing: 4) {
				Slider(value: $value, in: range)
					.controlSize(.small)
					.tint(Theme.label.opacity(0.85))

				// Tick marks give the track a sense of scale, so a slider reads as a
				// measured range rather than a smear between two ends.
				HStack(spacing: 0) {
					ForEach(0..<9, id: \.self) { index in
						Circle()
							.fill(Theme.tertiaryLabel.opacity(0.5))
							.frame(width: 2, height: 2)
						if index < 8 { Spacer(minLength: 0) }
					}
				}
				.padding(.horizontal, 5)
			}
			.padding(.leading, symbol == nil ? 0 : 38)
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 11)
	}
}

/// A short status line — readiness, lockout, warnings.
///
/// Plain text with a small coloured symbol, not a tinted banner. Full-width colour bars
/// inside a group shout at a volume the message rarely earns.
struct StatusPill: View {

	enum Kind {
		case ok, warning, error

		var tint: Color {
			switch self {
			case .ok: return Theme.faceID
			case .warning: return Theme.warning
			case .error: return Theme.danger
			}
		}

		var symbol: String {
			switch self {
			case .ok: return "checkmark.circle.fill"
			case .warning: return "exclamationmark.triangle.fill"
			case .error: return "xmark.circle.fill"
			}
		}
	}

	let kind: Kind
	let message: String

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 7) {
			Image(systemName: kind.symbol)
				.font(.system(size: 10))
				.foregroundStyle(kind.tint)
			Text(message)
				.font(.system(size: 11))
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 10)
	}
}

/// A text field matching the group's surface.
struct SettingsField: View {
	let placeholder: String
	@Binding var text: String
	var isSecure = true

	var body: some View {
		Group {
			if isSecure {
				SecureField(placeholder, text: $text)
			} else {
				TextField(placeholder, text: $text)
			}
		}
		.textFieldStyle(.plain)
		.font(.system(size: 13))
		.padding(.horizontal, 9)
		.padding(.vertical, 5)
		.background {
			// A shallow rounded rectangle, not a capsule. Capsule fields are a web form
			// convention; every text field on macOS is 6pt-ish.
			RoundedRectangle(cornerRadius: 6, style: .continuous)
				.fill(Color.black.opacity(0.25))
				.overlay {
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
				}
		}
	}
}

/// The app's push button.
struct AccentButtonStyle: ButtonStyle {
	var role: ButtonRole?

	/// Neutral rather than accented, for actions that sit beside a primary one.
	static let secondary = ButtonRole.cancel

	func makeBody(configuration: Configuration) -> some View {
		let tint: Color =
			switch role {
			case .some(.destructive): Theme.danger
			default: Theme.label
			}
		return configuration.label
			.font(.system(size: 12))
			.foregroundStyle(tint)
			.padding(.horizontal, 12)
			.padding(.vertical, 5)
			.background {
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.fill(tint.opacity(configuration.isPressed ? 0.26 : 0.14))
			}
	}
}
