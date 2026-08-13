import AppKit
import SwiftUI

/// Design tokens.
///
/// The palette follows the system appearance. It used to be dark unconditionally, on the
/// reasoning that Face ID is dark on every Apple platform — but that is true of Apple's
/// *sheet*, which appears over whatever you were doing, not of a settings window that sits
/// among your other windows. A window that stays black while everything around it turns
/// white is the one that looks broken.
enum Theme {

	/// A colour that resolves against whichever appearance it is drawn in.
	///
	/// AppKit does the resolving, not a `@Environment(\.colorScheme)` read, because these are
	/// static tokens with no view to read an environment from — and because it then works
	/// inside `NSHostingView`, popovers and menus, which do not always inherit the
	/// environment the way the view tree suggests.
	static func dynamic(light: Color, dark: Color) -> Color {
		Color(
			nsColor: NSColor(name: nil) { appearance in
				appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
					? NSColor(dark) : NSColor(light)
			})
	}

	/// Glass tint, in whichever direction the appearance calls for.
	///
	/// This is the pair that has to flip. Every scrim in the window is black over a dark
	/// appearance, and the *same* black in light mode turns the glass into a grey smear —
	/// light glass is tinted with white.
	static func scrim(_ opacity: Double) -> Color {
		dynamic(light: .white.opacity(opacity), dark: .black.opacity(opacity))
	}

	// MARK: - Colour

	/// Opaque ground, for the windows that are not vibrant — enrolment and the recognition
	/// test, both of which are full of camera preview and want no wallpaper behind them.
	static let background = dynamic(
		light: Color(red: 0.93, green: 0.93, blue: 0.94),
		dark: Color(red: 0.078, green: 0.078, blue: 0.082))

	/// Group fill, over the glass rather than instead of it.
	///
	/// A flat rectangle is what made every group read as a grey slab: it is a *painted*
	/// panel, so it sits at the same depth as everything else and the window flattens into
	/// one sheet of cardboard. Real glass has a blur of its own, which is what separates a
	/// group from the thing behind it.
	///
	/// Light mode takes white rather than a lightened black — Jis G Jacob's point, and the
	/// right one: a group in light mode is a white card, not a pale grey one.
	static let surface = dynamic(light: .white.opacity(0.55), dark: .white.opacity(0.07))
	static let surfaceRaised = dynamic(light: .white.opacity(0.85), dark: .white.opacity(0.12))
	static let separator = dynamic(light: .black.opacity(0.10), dark: .white.opacity(0.09))

	// MARK: - Icon palette

	/// There isn't one. That is the palette.
	///
	/// This used to be six saturated hues — blue, orange, purple, pink, teal, indigo — one
	/// per settings row, on the argument that Apple colour-codes its own icons. Apple does,
	/// in the *top-level* list of System Settings, where the categories are fixed and
	/// learnable. Inside a pane it buys nothing: nobody navigates to a switch by remembering
	/// that it was the pink one, and five hues in a group of five rows is chroma with no
	/// information in it.
	///
	/// Monochrome tiles keep what the icon column is actually for — a shape per row to scan
	/// by — and hand the whole colour budget to state. When something in this window is
	/// coloured, it is because it is telling you something.
	static let grey = Color(red: 0.56, green: 0.56, blue: 0.58)

	/// What a switched-on control's icon turns.
	///
	/// The argument against colour was that hue inside a pane carries no information. A
	/// switch is the exception: on and off is exactly the information an icon can carry, and
	/// carrying it in colour means the state of five switches reads in one glance instead of
	/// five. Grey when off, and this when on.
	static let active = dynamic(
		light: Color(red: 0.00, green: 0.42, blue: 0.90),
		dark: Color(red: 0.16, green: 0.56, blue: 1.00))

	/// Label opacities are set against the *worst* case, not the average one.
	///
	/// The window is translucent, so the ground under a label is whatever wallpaper the user
	/// happens to have. Tuned on a dark desktop, 0.35 looked like a restrained tertiary; on a
	/// light one it was gone. These are the lowest values that still hold up over a bright
	/// wallpaper coming through the glass.
	static let label = dynamic(light: .black, dark: .white)
	static let secondaryLabel = dynamic(light: .black.opacity(0.62), dark: .white.opacity(0.68))
	static let tertiaryLabel = dynamic(light: .black.opacity(0.45), dark: .white.opacity(0.52))

	/// Controls are neutral.
	///
	/// Tinting every switch, slider and icon green made the whole window read as one
	/// undifferentiated colour, so the green stopped meaning anything. Reserving it for
	/// Face ID itself — the glyph, the enrolment ring, the success tick — is what gives it
	/// back its meaning: green here says *recognised*, not *this is a control*.
	/// Black and white, which is exactly what an accent of "no colour" means in each
	/// appearance — and what makes a filled button read as filled in both.
	static let accent = dynamic(light: .black, dark: .white)

	/// What a filled control's label is knocked out in: the opposite of `accent`.
	static let onAccent = dynamic(light: .white.opacity(0.95), dark: .black.opacity(0.88))

	/// Selected and hovered rows.
	///
	/// These have to be a pair, not one colour: a wash of white marks a row on dark glass and
	/// is completely invisible on light. The selected sidebar row disappearing in light mode
	/// was exactly this — a hardcoded `white.opacity(0.14)` with nothing lighter behind it to
	/// stand out from.
	static let selection = dynamic(light: .black.opacity(0.13), dark: .white.opacity(0.16))
	static let hoverFill = dynamic(light: .black.opacity(0.06), dark: .white.opacity(0.07))

	/// Apple's system green. Face ID identity only, never chrome.
	static let faceID = Color(red: 0.20, green: 0.78, blue: 0.35)
	static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
	static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

	// MARK: - Metrics

	/// Generous and continuous. Small radii on a dark panel read as a dialog box; the
	/// system's own glass surfaces — Spotlight, the Siri panel, the notch capsule this app
	/// already draws — are much rounder than a settings group used to be.
	static let cornerRadius: CGFloat = 16
	static let rowInset: CGFloat = 15
	static let sectionSpacing: CGFloat = 22
}

// MARK: - Glass

/// The window's ground: dark glass at the top, fading toward clear at the bottom.
///
/// The window used to be a vibrancy layer under a flat black scrim, and it looked like a
/// grey slab dropped on the desktop — the wallpaper technically came through, but at one
/// unchanging density, so nothing about it read as glass. What makes the system's own
/// panels look like glass is the *gradient*: dense enough at the top to carry a title,
/// thinning as it falls, so the surface admits it is a sheet with light behind it.
///
/// The same shape the notch capsule already uses, which is the point — the panel that drops
/// out of the notch and the window you configure it from should be made of one material.
struct WindowGlass: View {
	var keepsTitle = false
	/// Lets far more of the desktop through, for the theme named after it.
	var extraTranslucent = false

	private func scrim(_ opacity: Double) -> Color {
		Theme.scrim(extraTranslucent ? opacity * 0.5 : opacity)
	}

	var body: some View {
		ZStack {
			VibrantBackground(material: .underWindowBackground, hidesTitle: !keepsTitle)

			LinearGradient(
				stops: [
					.init(color: scrim(0.74), location: 0),
					.init(color: scrim(0.62), location: 0.32),
					.init(color: scrim(0.44), location: 0.68),
					.init(color: scrim(0.26), location: 1),
				],
				startPoint: .top,
				endPoint: .bottom)

			// The specular top edge. A single hairline of light along the upper rim is what
			// tells the eye a surface is glass rather than paint — it is the highlight of a
			// physical sheet catching the light above it.
			VStack(spacing: 0) {
				LinearGradient(
					colors: [.white.opacity(0.22), .clear],
					startPoint: .top, endPoint: .bottom)
					.frame(height: 90)
				Spacer(minLength: 0)
			}
			.blendMode(.plusLighter)
			.opacity(0.5)
		}
		.ignoresSafeArea()
	}
}

/// A group's surface: material, a breath of white, and a rim that catches light at the top.
///
/// Flat, now that the buttons carry the glass.
///
/// This used to be material plus a lit rim, on the argument that depth is what separates a
/// group from its background. The argument was right and applied to the wrong element: with
/// glass on the containers *and* the controls, everything on screen had depth and none of it
/// meant anything. Aviorrok's point — flat containers, glass controls — puts the depth on
/// the thing you can actually touch.
///
/// One fill and one hairline. The group still reads as a surface because the window behind it
/// is glass and this isn't.
struct GlassSurface: ViewModifier {

	var cornerRadius: CGFloat = Theme.cornerRadius
	/// Slightly brighter for things that sit *on* a group rather than being one.
	var fill: Color = Theme.surface

	private var shape: RoundedRectangle {
		RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
	}

	func body(content: Content) -> some View {
		content
			.background { shape.fill(fill) }
			.overlay {
				// A single even hairline, not a lit rim. A gradient edge is how you draw a
				// raised surface, and this one is deliberately not raised any more.
				shape.strokeBorder(Theme.separator, lineWidth: 1)
			}
			.clipShape(shape)
	}
}

extension View {
	func glassSurface(cornerRadius: CGFloat = Theme.cornerRadius, fill: Color = Theme.surface)
		-> some View
	{
		modifier(GlassSurface(cornerRadius: cornerRadius, fill: fill))
	}
}

// MARK: - Type

/// The type scale.
///
/// Every size in the app comes from here. It used to be a dozen loose `.system(size:)`
/// literals scattered across the views — 9, 10, 11, 12, 13, 14, 15, 19, 20 — which is a
/// spread rather than a scale, and it showed: rows and their details differed by a point in
/// one window and three in another.
///
/// These are macOS's own text styles rather than fixed sizes, so they match the metrics
/// AppKit uses for the same job (`.body` *is* 13pt, `.callout` 12, `.subheadline` 11) and
/// they follow the system text size where the user has changed it. Nothing is below
/// `.caption` — 10pt is the floor macOS draws at, and the 9pt labels that were here before
/// were under it.
enum Typography {

	/// The pane heading in the detail column.
	static let paneTitle = Font.system(.title2, weight: .bold)

	/// A group's heading.
	static let groupTitle = Font.headline

	/// A row's label, and body copy generally.
	static let row = Font.body

	/// The explanatory line under a row's label, and a group's footer.
	static let detail = Font.subheadline

	/// Text inside a control — buttons, pop-up menus, value read-outs.
	static let control = Font.callout

	/// The status line in the hero row.
	static let heroTitle = Font.system(.title3, weight: .semibold)

	/// A large figure that changes — a score, a peak. Rounded because it is a *number*
	/// being read as a quantity, which is the one place macOS uses the rounded face.
	static let metric = Font.system(.title2, design: .rounded, weight: .semibold)

	/// The caption over a metric.
	static let metricLabel = Font.system(.caption, weight: .semibold)

	/// Figures that must line up column-wise between frames — a score that updates ten
	/// times a second jitters horribly in a proportional face.
	static let mono = Font.system(.subheadline, design: .monospaced, weight: .medium)

	/// The value pill on a slider.
	static let pill = Font.system(.caption, design: .rounded, weight: .medium)

	/// The smallest thing in the app.
	static let caption = Font.caption

	/// The Face ID mark used as a picture rather than as text — the hero row, the About
	/// panel. Fixed rather than scaled: this is an illustration sized against the layout
	/// around it, and it is never the only statement of what it says.
	static let glyph = Font.system(size: 34, weight: .thin)
	static let glyphLarge = Font.system(size: 40, weight: .thin)
}

// MARK: - Window background

/// The window's vibrancy layer.
///
/// `NSVisualEffectView` rather than a SwiftUI material: materials inside the content view
/// blur whatever the *window* has behind them, which on an opaque window is nothing. Only
/// a view backing the window itself samples the desktop.
struct VibrantBackground: NSViewRepresentable {
	var material: NSVisualEffectView.Material = .sidebar
	/// Settings draws its own heading, so its title would be a second one. A utility window
	/// like the recognition test has no heading of its own and needs to keep AppKit's.
	var hidesTitle = true

	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = TransparentHostView()
		view.hidesTitle = hidesTitle
		view.material = material
		view.blendingMode = .behindWindow
		view.state = .active
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {
		view.material = material
	}

	/// Clears the window behind itself, and takes the title bar out of the way.
	///
	/// `behindWindow` blending samples the desktop *through* the window, which it can only
	/// do while the window is not opaque. SwiftUI's `Window` ships opaque with a solid
	/// background, so the material had nothing to sample and rendered as flat grey — the
	/// window looked painted rather than glazed.
	///
	/// `.hiddenTitleBar` alone was not enough either: it hides the *title*, but AppKit still
	/// draws a title bar behind it, which showed as a pale band across the top right of the
	/// window — the one place the glass stopped and a grey slab started. Making it
	/// transparent and letting content run full-height is what closes that seam.
	private final class TransparentHostView: NSVisualEffectView {
		var hidesTitle = true

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			guard let window else { return }
			window.isOpaque = false
			window.backgroundColor = .clear
			window.titlebarAppearsTransparent = true
			window.styleMask.insert(.fullSizeContentView)
			if hidesTitle { window.titleVisibility = .hidden }
			// Drag anywhere. With no title bar to grab, the window was only movable by a
			// strip the user cannot see.
			window.isMovableByWindowBackground = true
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
			// Secondary, not primary. A group title labels the rows under it; setting it in
			// full-strength white made it compete with the row labels it was introducing.
			if let title {
				Text(title)
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.secondaryLabel)
					.padding(.leading, 4)
			}

			VStack(spacing: 0) {
				content
			}
			.glassSurface()

			if let footer {
				Text(footer)
					.font(Typography.detail)
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

/// A rounded glass square holding an SF Symbol.
///
/// Rows of pure text are hard to scan — the eye has to read every line to find the one it
/// wants. A consistent icon column gives each row a shape you can navigate by.
///
/// The tile is light on the wallpaper rather than a block of colour on it: same frosted
/// surface as the group it sits in, one step brighter, with a hairline to catch the edge.
/// It reads as glass rather than as a sticker.
struct IconTile: View {
	let symbol: String
	/// Only ever passed for something that is reporting *state* — the enrolled face's
	/// warning triangle, a destructive row. Left alone otherwise.
	var tint: Color?
	var isEnabled = true

	var body: some View {
		Image(systemName: symbol)
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(tint ?? Theme.label)
			.frame(width: 26, height: 26)
			.glassSurface(cornerRadius: 8, fill: Theme.surfaceRaised)
			.opacity(isEnabled ? 1 : 0.45)
	}
}

// MARK: - Rows

/// A row with a title, optional explanation, and trailing control.
struct SettingRow<Trailing: View>: View {

	let title: String
	var detail: String?
	/// SF Symbol shown in a tinted tile at the leading edge.
	var symbol: String?
	var symbolTint: Color?
	var isEnabled = true
	@ViewBuilder var trailing: Trailing

	var body: some View {
		HStack(spacing: 12) {
			if let symbol {
				IconTile(symbol: symbol, tint: symbolTint, isEnabled: isEnabled)
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(Typography.row)
					.foregroundStyle(isEnabled ? Theme.label : Theme.tertiaryLabel)
				if let detail {
					Text(detail)
						.font(Typography.detail)
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
	var symbolTint: Color?
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

/// A labelled slider with its value in a pill and a tick scale under the track.
///
/// The pill matters: a bare slider tells you there is a value but not what it is, so any
/// adjustment becomes trial and error.
struct SliderRow: View {

	let title: String
	var symbol: String?
	var symbolTint: Color?
	@Binding var value: Double
	let range: ClosedRange<Double>
	var format: (Double) -> String

	/// Half the small slider's knob. The track is inset by this at both ends, so ticks laid
	/// out across the full width drift away from the values they claim to mark.
	private let knobRadius: CGFloat = 7

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
				if let symbol {
					IconTile(symbol: symbol, tint: symbolTint)
				}
				Text(title)
					.font(Typography.row)
					.foregroundStyle(Theme.label)
				Spacer()
				Text(format(value))
					.font(Typography.pill)
					.foregroundStyle(Theme.secondaryLabel)
					.padding(.horizontal, 9)
					.padding(.vertical, 3)
					.background(Capsule().fill(Theme.surfaceRaised))
					.contentTransition(.numericText())
					.monospacedDigit()
			}

			VStack(spacing: 3) {
				Slider(value: $value, in: range)
					.controlSize(.small)
					.tint(Theme.label.opacity(0.85))
				ticks
			}
			.padding(.leading, symbol == nil ? 0 : 38)
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 11)
	}

	/// The scale under the track.
	///
	/// These used to be nine evenly spaced dots drawn regardless of the range — the same
	/// marks under `0…1`, `-20…20` and `-40…40`. They looked like a scale and measured
	/// nothing, which is worse than having no marks at all: a decoration that reads as
	/// information tells the user something false. Now each tick sits at a round value in
	/// the row's own range, and the ends and zero are drawn taller so the span is readable
	/// without a legend.
	private var ticks: some View {
		GeometryReader { geometry in
			let track = geometry.size.width - knobRadius * 2
			ZStack(alignment: .topLeading) {
				ForEach(tickValues, id: \.self) { tick in
					Capsule()
						.fill(Theme.tertiaryLabel.opacity(isMajor(tick) ? 0.55 : 0.3))
						.frame(width: 1, height: isMajor(tick) ? 5 : 3)
						.offset(x: knobRadius + track * fraction(of: tick) - 0.5)
				}
			}
		}
		.frame(height: 5)
	}

	private func fraction(of tick: Double) -> CGFloat {
		CGFloat((tick - range.lowerBound) / (range.upperBound - range.lowerBound))
	}

	/// Ends and zero.
	private func isMajor(_ tick: Double) -> Bool {
		let epsilon = (range.upperBound - range.lowerBound) / 1000
		return abs(tick - range.lowerBound) < epsilon
			|| abs(tick - range.upperBound) < epsilon
			|| (range.contains(0) && abs(tick) < epsilon)
	}

	/// Round values across the range, aiming for eight or so intervals: 5px steps on
	/// `-20…20`, 10px on `-40…40`, 0.1 on `0…1`.
	private var tickValues: [Double] {
		let span = range.upperBound - range.lowerBound
		guard span > 0 else { return [] }

		let rough = span / 8
		let magnitude = pow(10, (log10(rough)).rounded(.down))
		let normalised = rough / magnitude
		let step = (normalised < 1.5 ? 1 : normalised < 3 ? 2 : normalised < 7 ? 5 : 10) * magnitude

		var values: [Double] = []
		var tick = (range.lowerBound / step).rounded(.up) * step
		while tick <= range.upperBound + step / 1000 {
			values.append(tick)
			tick += step
		}
		return values
	}
}

/// A short status line — readiness, lockout, warnings.
///
/// Plain text with a small coloured symbol, not a tinted banner. Full-width colour bars
/// inside a group shout at a volume the message rarely earns.
///
/// Named for what it is. It was `StatusPill`, and it has never been a pill — the same file
/// held a real capsule-backed pill in the recognition test, so the two names were the wrong
/// way round.
struct StatusLine: View {

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

		/// Colour is the only thing separating these three on screen, which is no separation
		/// at all for a colour-blind user. Spoken, the severity has to be said.
		var accessibilityPrefix: String {
			switch self {
			case .ok: return ""
			case .warning: return "Warning: "
			case .error: return "Problem: "
			}
		}
	}

	let kind: Kind
	let message: String

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 7) {
			Image(systemName: kind.symbol)
				.font(Typography.caption)
				.foregroundStyle(kind.tint)
			Text(message)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 10)
		// The symbol is decoration for a message that already says it; without this,
		// VoiceOver reads "checkmark circle fill" before every status line.
		.accessibilityElement(children: .combine)
		.accessibilityLabel(Text(kind.accessibilityPrefix + message))
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
		.font(Typography.row)
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		// Recessed rather than raised: a field is a well cut into the glass, so it takes a
		// darker fill and an inner rim, the opposite of a group's lit top edge.
		.background {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(Theme.dynamic(light: .white.opacity(0.9), dark: .black.opacity(0.22)))
				.overlay {
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.strokeBorder(
							LinearGradient(
								colors: [Theme.dynamic(light: .black.opacity(0.18), dark: .black.opacity(0.35)), .white.opacity(0.1)],
								startPoint: .top, endPoint: .bottom),
							lineWidth: 1)
				}
		}
	}
}

/// The app's push button — the *only* one.
///
/// There used to be three button languages: this, `.borderedProminent`, and a bare green
/// text button, with no rule for which went where. Enrolment stacked two of them fourteen
/// points apart. One style with three prominences is what makes a button look like a button
/// everywhere in the app.
struct AccentButtonStyle: ButtonStyle {

	enum Prominence {
		/// Filled and tinted. The action the screen exists for — at most one per screen.
		case primary
		/// Tinted background, for anything that isn't.
		case standard
		/// No background until hovered. Sits beside another button without competing.
		case quiet
	}

	var role: ButtonRole?
	var prominence: Prominence = .standard

	func makeBody(configuration: Configuration) -> some View {
		ButtonBody(configuration: configuration, role: role, prominence: prominence)
	}

	/// A view rather than a bare `configuration.label` chain, because focus and hover are
	/// state — and a `ButtonStyle` cannot hold state itself.
	private struct ButtonBody: View {

		let configuration: Configuration
		let role: ButtonRole?
		let prominence: Prominence

		/// Custom button styles lose AppKit's focus ring, so the app was unusable by
		/// keyboard: you could tab onto a button and get no indication you had. This puts
		/// the ring back. It only ever shows when the user has turned on keyboard access —
		/// which is exactly the person it is for.
		@Environment(\.isFocused) private var isFocused
		@State private var isHovering = false

		/// White unless the button is destructive.
		///
		/// A primary action gets its weight from being *filled* — white on the wallpaper,
		/// with the label knocked out in black — rather than from being coloured. Green here
		/// would have made the loudest control on the screen the one place green does not
		/// mean "recognised".
		private var tint: Color {
			role == .destructive ? Theme.danger : Theme.label
		}

		var body: some View {
			configuration.label
				.font(Typography.control)
				.foregroundStyle(prominence == .primary ? Theme.onAccent : tint)
				.padding(.horizontal, 12)
				.padding(.vertical, 5)
				// Glass on the control, flat on the container it sits in.
				//
				// Aviorrok's suggestion, and it inverts what the window was doing: groups
				// were glass and buttons were a wash of white, so the surface you *can't*
				// touch had the depth and the surface you can had none. Glass here reads as
				// a physical control lying on the panel, and it gives the system's own
				// pressed and hover response for free through `.interactive()`.
				//
				// `quiet` stays flat until it is hovered. It exists to sit beside another
				// button without competing, and a second piece of glass beside the first is
				// exactly the competition it is there to avoid.
				.background {
					let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
					if prominence == .quiet && !isHovering && !configuration.isPressed {
						shape.fill(.clear)
					} else {
						shape
							.fill(tint.opacity(fillOpacity))
							.glassEffect(.regular.interactive(), in: shape)
					}
				}
				.overlay {
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.strokeBorder(Theme.label.opacity(isFocused ? 0.9 : 0), lineWidth: 2)
						.padding(-2)
				}
				.contentShape(.rect(cornerRadius: 7, style: .continuous))
				.onHover { isHovering = $0 }
				.animation(.easeOut(duration: 0.12), value: isHovering)
		}

		private var fillOpacity: Double {
			switch prominence {
			case .primary: configuration.isPressed ? 0.78 : (isHovering ? 1 : 0.92)
			case .standard: configuration.isPressed ? 0.26 : (isHovering ? 0.2 : 0.14)
			case .quiet: configuration.isPressed ? 0.18 : (isHovering ? 0.1 : 0)
			}
		}
	}
}

extension ButtonStyle where Self == AccentButtonStyle {
	static var accent: AccentButtonStyle { AccentButtonStyle() }
	static var quiet: AccentButtonStyle { AccentButtonStyle(prominence: .quiet) }
	static var destructive: AccentButtonStyle { AccentButtonStyle(role: .destructive) }
	/// Filled white. At most one per screen — the thing the screen is for.
	static var primaryAction: AccentButtonStyle {
		AccentButtonStyle(prominence: .primary)
	}
}

/// A small ⓘ that opens a popover.
///
/// For the explanation that is too long to sit in a row's subtitle but too important to leave
/// in a file on GitHub. A footer under the group would hold it, but a footer is read by
/// nobody who has already decided — this is read by the person hesitating.
struct InfoButton<Content: View>: View {

	let title: String
	@ViewBuilder var content: Content

	@State private var isShowing = false

	var body: some View {
		Button {
			isShowing.toggle()
		} label: {
			Image(systemName: "info.circle")
				.font(Typography.control)
				.foregroundStyle(Theme.secondaryLabel)
				.contentShape(.circle)
		}
		.buttonStyle(.plain)
		.help(title)
		.accessibilityLabel(title)
		.popover(isPresented: $isShowing, arrowEdge: .bottom) {
			VStack(alignment: .leading, spacing: 10) {
				Text(title)
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.label)
				content
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
			}
			.multilineTextAlignment(.leading)
			.padding(16)
			.frame(width: 300)
		}
	}
}
