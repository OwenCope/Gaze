import AppKit
import SwiftUI

/// Design tokens.
///
/// The palette follows the system appearance. It used to be dark unconditionally, on the
/// reasoning that Gaze is dark on every Apple platform — but that is true of Apple's
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

	/// A group's fill — and, since `GlassSurface` lost its outline, the only thing marking
	/// where a group starts and stops.
	///
	/// Light mode takes white rather than a lightened black — Jis G Jacob's point, and the
	/// right one: a group in light mode is a white card, not a pale grey one.
	///
	/// It was 0.07 in dark, which is barely a tint: it could afford to be that faint only
	/// because a hairline was drawn round it to say where the edge was. Tone has to carry
	/// that on its own now, the way System Settings does it, so the step up from the ground
	/// is a step you can actually see.
	static let surface = dynamic(light: .white.opacity(0.62), dark: .white.opacity(0.12))
	static let surfaceRaised = dynamic(light: .white.opacity(0.88), dark: .white.opacity(0.18))
	/// Settings groups only: a calmer, more solid neutral fill so rows stay readable over
	/// wallpaper. White in light, neutral grey in dark, both at 0.86.
	static let settingsGroupFill = dynamic(light: .white.opacity(0.86), dark: Color(white: 0.14).opacity(0.86))
	/// Keep the original group tint over the Semi Liquid Glass backdrop.
	static let settingsGlassGroupFill = surface
	static let separator = dynamic(light: .black.opacity(0.10), dark: .white.opacity(0.09))

	static let setupGround = dynamic(light: Color(white: 0.96), dark: .black)
	/// The muted line under a title — same level as `secondaryLabel` resolves to in dark.
	static let setupSecondary = Color.primary.opacity(0.68)
	/// The quietest text — a "Not now", a caption. Matches `tertiaryLabel` in dark.
	static let setupTertiary = Color.primary.opacity(0.52)
	/// An unfilled enrolment tick, and the placeholder ring before capture starts. Was three
	/// different values (`0.34,0.34,0.36`, `.white.opacity(0.14)`) for the one visual role.
	static let tickEmpty = Color(white: 0.34)

	/// The ground every setup screen sits on.
	///
	/// Black, with one barely-there lift behind the content.
	///
	/// Flat black across a 560×720 panel has nothing in it to say where the front of the
	/// window is, so there is a single soft highlight centred where the figure sits — the
	/// thing the screen is about is also the brightest part of it. No vignette: there is
	/// nothing to darken towards from black, and the earlier one was only there to hold
	/// the window's edge against the desktop, which black does by itself.
	///
	/// 5%, which is under the threshold of reading as a gradient. It should not be visible
	/// as an effect; it should only be visible that the flat version was flat.
	static var setupBackground: some View {
		ZStack {
			setupGround

			RadialGradient(
				colors: [.white.opacity(0.05), .clear],
				center: UnitPoint(x: 0.5, y: 0.32),
				startRadius: 0,
				endRadius: 420
			)
		}
		.ignoresSafeArea()
	}

	// MARK: - Motion

	/// The app's timing, in one place.
	///
	/// These were scattered as literals — `.easeInOut(duration: 0.3)` for a step change,
	/// `.spring(response: 0.5, dampingFraction: 0.72)` for a mark, `.easeOut(0.22)` for a
	/// dim — which is why setup read as a stack of separate screens rather than one flow:
	/// nothing moved on a shared clock.
	///
	/// `standard` is Apple's own curve (0.32, 0.72, 0, 1) — the one UIKit and AppKit use
	/// for view transitions. It leaves immediately and arrives slowly, which is what makes
	/// a transition feel like the screen was already moving before you looked at it.
	enum Motion {
		/// Screen-to-screen, and anything that moves a whole block of content.
		static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)
		/// The same curve, shortened — a control changing state under the pointer.
		static let quick = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.14)
		/// Something arriving that should feel physical: a tick, a mark, a result.
		static let arrive = Animation.spring(response: 0.34, dampingFraction: 0.86)

		/// How far a block travels as it arrives. Small on purpose — a long slide reads
		/// as a page turn, and these are not pages.
		static let rise: CGFloat = 8
		/// The blur an element carries in from. Enough to read as focus resolving; not
		/// enough to look like a mistake in a screenshot.
		static let entryBlur: CGFloat = 3
	}

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
	/// Gaze itself — the glyph, the enrolment ring, the success tick — is what gives it
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

	/// Apple's system green. Gaze identity only, never chrome.
	static let faceID = Color(red: 0.20, green: 0.78, blue: 0.35)
	static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
	static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

	// MARK: - Metrics

	/// Generous and continuous. Small radii on a dark panel read as a dialog box; the
	/// system's own glass surfaces — Spotlight, the Siri panel, the notch capsule this app
	/// already draws — are much rounder than a settings group used to be.
	static let cornerRadius: CGFloat = 16
	static let rowInset: CGFloat = 18
	static let sectionSpacing: CGFloat = 16
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
	/// The Semi Liquid Glass theme: the notch panel's material, on a window.
	var extraTranslucent = false

	/// Black, always, when this is the glass theme.
	///
	/// `Theme.scrim` flips to white in a light appearance, which is right for a window that
	/// is trying to look like the system's own — and wrong here. This gradient *is* the
	/// theme: dark at the top thinning to clear at the foot, the same thing the notch panel
	/// does. Flipped white it came out as a pale slab, which is not the material anyone
	/// picked.
	private func scrim(_ opacity: Double) -> Color {
		extraTranslucent ? .black.opacity(opacity) : Theme.scrim(opacity)
	}

	/// A plain solid ground, in whichever appearance it's drawn: white in light, grey in
	/// dark. This is the default now — a window that shows the desktop through itself reads
	/// as an overlay, not an app, and the translucency was most of what made it feel
	/// "vibe-coded". `VibrantBackground` stays underneath purely for its title-bar handling;
	/// the opaque colour on top of it is what you actually see. Semi Liquid Glass
	/// (`extraTranslucent`) still gets the real material for anyone who wants it.
	private static let solidGround = Theme.dynamic(
		light: Color(white: 0.98),
		dark: Color(white: 0.145))

	var body: some View {
		ZStack {
			// `.behindWindow` on both paths: the material samples the desktop, which is the
			// only way a window is actually glazed rather than painted.
			//
			// This briefly used `.withinWindow` on the glass theme so the material would
			// frost `WallpaperBackdrop`'s copy of the desktop picture. That did make the
			// wallpaper visible, but it was the wrong wallpaper — an image scaled to the
			// window, sitting still while the real one moved. Sampling the desktop means
			// what shows through is what is behind, in the right place, at the right scale,
			// updating as the window moves.
			VibrantBackground(
				material: extraTranslucent ? .hudWindow : .underWindowBackground,
				hidesTitle: !keepsTitle,
				blending: .behindWindow)

			if extraTranslucent {
				// A fall from top to bottom, not a blackout.
				//
				// These stops used to start at 0.94, which is opaque black in all but name.
				// Stacked on `WallpaperBackdrop`'s own 0.62 and the material between them,
				// the window carried three separate scrims and the wallpaper could not
				// survive them — the glass theme rendered as the same flat slab as the solid
				// one, which is what made picking it feel like it did nothing.
				//
				// `WallpaperBackdrop` is the one that owes us legibility and is already
				// sized for it. This one only has to give the sheet its top-to-bottom
				// gradient, so it starts under half and reaches clear.
				LinearGradient(
					stops: [
						.init(color: scrim(0.22), location: 0),
						.init(color: scrim(0.14), location: 0.32),
						.init(color: scrim(0.05), location: 0.68),
						.init(color: scrim(0), location: 1),
					],
					startPoint: .top,
					endPoint: .bottom)

				// The specular top edge — the highlight that tells the eye it's glass. Only
				// on the glass theme; on a solid window it would be an unexplained sheen.
				VStack(spacing: 0) {
					LinearGradient(
						colors: [.white.opacity(0.22), .clear],
						startPoint: .top, endPoint: .bottom)
						.frame(height: 90)
					Spacer(minLength: 0)
				}
				.blendMode(.plusLighter)
				.opacity(0.5)
			} else {
				Self.solidGround
			}
		}
		.ignoresSafeArea()
	}
}

/// A group's surface: a fill, and nothing else.
///
/// No outline. This carried a hairline `strokeBorder` all the way round, and drawing a line
/// around a group is the single loudest non-native thing this window did — System Settings
/// separates a group from its background by *tone alone*, a slightly lighter fill on a
/// darker ground, and never by an edge. An outlined rounded rectangle is a web card, and
/// four of them stacked down a pane read as a web page however native everything inside
/// them is.
///
/// Losing the edge means the fill has to do the work the edge was doing, which is why
/// `Theme.surface` is no longer almost-transparent — see its own note.
///
/// Flat, too, now that the buttons carry the glass.
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

	// The three setup sizes below are larger than any macOS text style, so they are written
	// as a style *scaled* rather than as a fixed point size.
	//
	// `Font.system(size:)` does not move when somebody raises their text size — it is a
	// number of points, forever — and these three carry every word on the setup screens:
	// the title, the one line under it, and the hero. Set as literals, the flow that
	// introduces the app was the part of the app that ignored the accessibility setting
	// most completely.
	//
	// Anchored to the closest style rather than all to `.body`, because the styles do not
	// grow at the same rate at accessibility sizes — a display face is meant to grow more
	// slowly than body copy, and scaling a title from `.body` would have it overtake
	// everything around it. macOS's own metrics are `.body` 13pt and `.largeTitle` 26pt,
	// which is where the ratios come from.

	/// A setup screen's title. One size across welcome / capture / done, where there used to
	/// be three (25 / 26 / 30pt) for the same "screen title" role.
	static let setupTitle = Font.largeTitle.weight(.bold).scaled(by: 34.0 / 26.0)

	/// The one line on the opening screen, and nothing else.
	///
	/// Bigger than `setupTitle` and tracked tighter. A hero line set at body tracking
	/// looks like a heading that happened to be large; the negative tracking is most of
	/// what separates a product's first screen from a dialog's.
	static let setupHero = Font.largeTitle.weight(.bold).scaled(by: 52.0 / 26.0)

	/// Body copy under a setup title.
	static let setupBody = Font.body.scaled(by: 14.0 / 13.0)

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

	/// The Gaze mark used as a picture rather than as text — the hero row, the About
	/// panel. Fixed rather than scaled: this is an illustration sized against the layout
	/// around it, and it is never the only statement of what it says.
	///
	/// This is the rule the rest of the app's remaining `.system(size:)` literals follow.
	/// Text scales; drawings do not. `StoredPasswordRowArt` and `PermissionRowIllustration`
	/// are reconstructions of real rows, composed at the size they are displayed, and the
	/// notch panel is drawn against a physical cutout — grow the type inside any of them and
	/// the picture stops being a picture of the thing. A fixed size in one of those is a
	/// decision, not an oversight.
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
	/// What the material is allowed to sample.
	///
	/// `.behindWindow` frosts the desktop. `.withinWindow` frosts whatever this app drew
	/// underneath it, which is the only one of the two that can see `WallpaperBackdrop`.
	///
	/// This was hardcoded to `.behindWindow`, and that is why the wallpaper every comment
	/// in this file talks about has never once appeared on screen: a `behindWindow` effect
	/// view composites the desktop into its rectangle, so it does not blend with the
	/// SwiftUI view below it in the stack — it replaces it. `WallpaperBackdrop` was being
	/// drawn and then painted over on every frame. What you actually saw was the desktop
	/// behind the window, and over a dark desktop that is a flat grey slab, which is
	/// precisely the "painted rather than glazed" failure this type was written to avoid.
	var blending: NSVisualEffectView.BlendingMode = .behindWindow

	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = TransparentHostView()
		view.hidesTitle = hidesTitle
		view.material = material
		view.blendingMode = blending
		view.state = .active
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {
		view.material = material
		view.blendingMode = blending
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
private struct NativeSettingsFormKey: EnvironmentKey {
	static let defaultValue = false
}

private struct SettingsGroupFillKey: EnvironmentKey {
	static let defaultValue = Theme.settingsGroupFill
}

extension EnvironmentValues {
	var nativeSettingsForm: Bool {
		get { self[NativeSettingsFormKey.self] }
		set { self[NativeSettingsFormKey.self] = newValue }
	}
	var settingsGroupFill: Color {
		get { self[SettingsGroupFillKey.self] }
		set { self[SettingsGroupFillKey.self] = newValue }
	}
}

struct SettingsSection<Content: View>: View {
	@Environment(\.nativeSettingsForm) private var nativeForm
	@Environment(\.settingsGroupFill) private var groupFill

	let title: String?
	var footer: String?
	var info: String?
	@ViewBuilder var content: Content

	init(title: String? = nil, footer: String? = nil, info: String? = nil, @ViewBuilder content: () -> Content) {
		self.title = title
		self.footer = footer
		self.info = info
		self.content = content()
	}

	var body: some View {
		if nativeForm {
			Section {
				content
			} header: {
				sectionHeader
			} footer: {
				if let footer, !footer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(footer) }
			}
		} else {
			legacyBody
		}
	}

	private var legacyBody: some View {
		VStack(alignment: .leading, spacing: 7) {
			// Secondary, not primary. A group title labels the rows under it; setting it in
			// full-strength white made it compete with the row labels it was introducing.
			sectionHeader
				.padding(.horizontal, 4)

			VStack(spacing: 0) {
				content
			}
			.glassSurface(fill: groupFill)

			if let footer, !footer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				Text(footer)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, 4)
			}
		}
	}

	@ViewBuilder private var sectionHeader: some View {
		if let title {
			HStack {
				Text(title)
					.font(Typography.groupTitle)
					.foregroundStyle(Theme.secondaryLabel)
				if let info, !info.isEmpty {
					Spacer()
					InfoButton(title: "About \(title)", opensOnHover: true) {
						Text(info)
					}
				}
			}
		}
	}
}

/// Hairline between rows, inset to line up with the labels rather than the group edge.
struct RowDivider: View {
	@Environment(\.nativeSettingsForm) private var nativeForm
	/// Rows with an icon tile need a deeper inset so the rule starts under the label.
	var inset: CGFloat = 51

	var body: some View {
		if !nativeForm {
		Rectangle()
			.fill(Theme.separator)
			.frame(height: 1)
			.padding(.leading, inset)
			.accessibilityHidden(true)
		}
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
		// A glyph, not a badge.
		//
		// This drew each symbol on its own rounded, filled tile — a lighter square inside
		// an already-light group. System Settings does that in its *sidebar*, where the
		// tile's colour is what tells Wi-Fi from Bluetooth at a glance, and never in a
		// detail pane: there the icon is a bare glyph in the row's leading column. A grey
		// square behind a grey glyph adds a second rounded rectangle inside every row and
		// carries no information, since these tiles were all the same colour anyway.
		//
		// Bigger and secondary-weight to compensate: the tile was doing the work of making
		// a 13pt glyph findable, and size and tone do it instead.
		Image(systemName: symbol)
			.font(.system(size: 17, weight: .regular))
			.foregroundStyle(tint ?? Theme.secondaryLabel)
			.frame(width: 26, height: 26)
			.opacity(isEnabled ? 1 : 0.45)
			.accessibilityHidden(true)
	}
}

// MARK: - Rows

/// A row with a title, optional explanation, and trailing control.
struct SettingRow<Trailing: View>: View {
	@Environment(\.nativeSettingsForm) private var nativeForm

	let title: String
	var detail: String?
	/// SF Symbol shown in a tinted tile at the leading edge.
	var symbol: String?
	var symbolTint: Color?
	/// A picture that stands in for the glyph — a person's portrait, an app's icon.
	///
	/// Only the credits rows pass one. Everywhere else the icon column is a shape to scan
	/// by and a photograph would be noise; on a list of people it is the opposite, because
	/// a face is the fastest way to tell one person from another and a row of identical
	/// grey glyphs is the slowest.
	var portrait: NSImage?
	var isEnabled = true
	@ViewBuilder var trailing: Trailing

	var body: some View {
		if nativeForm {
			LabeledContent {
				trailing
			} label: {
				HStack(spacing: 10) {
					if let portrait {
						Image(nsImage: portrait)
							.resizable()
							.scaledToFit()
							.frame(width: 26, height: 26)
							.accessibilityHidden(true)
					}
					VStack(alignment: .leading, spacing: 3) {
						Text(title)
						if let detail {
							Text(detail).font(.callout).foregroundStyle(.secondary)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
				}
			}
			.disabled(!isEnabled)
		} else {
			legacyBody
		}
	}

	private var legacyBody: some View {
		HStack(spacing: 12) {
			if let portrait {
				// Rounded square, not a circle. Half of these are app icons, and macOS app
				// icons are squircles — circling them crops the artwork its designer chose.
				Image(nsImage: portrait)
					.resizable()
					.interpolation(.high)
					.aspectRatio(contentMode: .fill)
					.frame(width: 26, height: 26)
					.clipShape(.rect(cornerRadius: 6, style: .continuous))
					.opacity(isEnabled ? 1 : 0.45)
					.accessibilityHidden(true)
			} else if let symbol {
				IconTile(symbol: symbol, tint: symbolTint, isEnabled: isEnabled)
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(Typography.row)
					.foregroundStyle(isEnabled ? Theme.label : Theme.tertiaryLabel)
					.fixedSize(horizontal: false, vertical: true)
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
		// System Settings' own row metrics. Its rows sit just under 50pt and are inset
		// further from the group's edge than 15pt — the density here was a touch tighter
		// than the system's everywhere, and being consistently a few points tight is the
		// kind of difference you read as "not quite right" without being able to name it.
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 11)
		.frame(minHeight: 48)
	}
}

/// A switch row.
struct SettingToggle: View {
	@Environment(\.nativeSettingsForm) private var nativeForm

	let title: String
	var detail: String?
	var symbol: String?
	var symbolTint: Color?
	var portrait: NSImage?
	var isEnabled = true
	@Binding var isOn: Bool

	var body: some View {
		if nativeForm {
			Toggle(isOn: $isOn) {
				Text(title)
				if let detail { Text(detail) }
			}
			.disabled(!isEnabled)
		} else {
			legacyBody
		}
	}

	private var legacyBody: some View {
		SettingRow(
			title: title, detail: detail, symbol: symbol, symbolTint: symbolTint,
			portrait: portrait,
			isEnabled: isEnabled
		) {
			Toggle(title, isOn: $isOn)
				.labelsHidden()
				.accessibilityLabel(title)
				.accessibilityHint(detail ?? "")
				.toggleStyle(.switch)
				.controlSize(.small)
				.tint(Theme.accent)
				.disabled(!isEnabled)
		}
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
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 7) {
			Image(systemName: kind.symbol)
				.font(Typography.caption)
				.foregroundStyle(kind.tint)
				// The readiness line flips between warning and error as unlock setup
				// changes underneath it, so the glyph rolls over rather than cutting.
				.contentTransition(.symbolEffect(.replace.downUp))
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
		.symbolEffectsRemoved(reduceMotion)
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
		.padding(.horizontal, 14)
		.padding(.vertical, 7)
		// The system's glass, in a capsule — the same treatment `GlassField` gives the field
		// on the setup screen.
		//
		// This drew its own well: a rounded rectangle at radius 8, filled darker than the
		// group behind it, with a hairline round the edge. Two problems. It was the one
		// control in the window still hand-drawn, so on macOS 26 it sat in a row between a
		// real glass button and a real glass popup looking like neither; and it was the only
		// text field in the app that was not a capsule, so the password field in Settings and
		// the password field in setup — the same field, asking the same question — had
		// different shapes.
		//
		// `.glassEffect` is the real material, with the system's own focus ring, so there is
		// nothing left here to approximate.
		.glassEffect(.regular, in: .capsule)
	}
}

/// The app's push button.
///
/// The system's own button styles — `.bordered` for anything, `.borderedProminent` for the
/// one action a screen exists for — and nothing else. On macOS 26 these render as real
/// Liquid Glass, with the system's press, hover and focus behaviour for free; a hand-rolled
/// glass style could only ever approximate them, and the whole point is that a button here
/// reads as Apple's because it *is* Apple's.
///
/// No custom tint: buttons take the system accent, which keeps green reserved for the one
/// thing it means everywhere else in this app — *recognised*. A destructive button is a plain
/// `Button(role: .destructive)`, which the system already draws in red.
enum GazeButtonProminence {
	/// The action the screen exists for — at most one per screen. Filled (`.borderedProminent`).
	case primary
	/// Everything else. Bordered.
	case standard
}

extension View {
	/// Apply the app's standard push-button styling. `size` defaults to `.regular`; hero and
	/// setup actions take `.large`.
	func gazeButton(_ prominence: GazeButtonProminence = .standard, size: ControlSize = .regular)
		-> some View
	{
		modifier(GazeButtonModifier(prominence: prominence, size: size))
	}
}

struct GazeButtonModifier: ViewModifier {
	@Environment(\.nativeSettingsForm) private var nativeForm
	let prominence: GazeButtonProminence
	let size: ControlSize

	func body(content: Content) -> some View {
		if nativeForm {
			switch prominence {
			case .primary: content.buttonStyle(.borderedProminent).controlSize(size)
			case .standard: content.buttonStyle(.bordered).controlSize(size)
			}
		} else {
			legacyBody(content: content)
		}
	}

	private func legacyBody(content: Content) -> some View {
		Group {
			// `.glass` / `.glassProminent` are the Liquid Glass styles proper: a lensing,
			// refracting control rather than `.bordered`'s flat capsule with a glass-ish
			// fill. Same system press, hover and focus behaviour, same accent, and no
			// hand-rolled material — this is Apple's, which is the whole point.
			if #available(macOS 26.0, *) {
				switch prominence {
				case .primary: content.buttonStyle(.glassProminent)
				case .standard: content.buttonStyle(.glass)
				}
			} else {
				switch prominence {
				case .primary: content.buttonStyle(.borderedProminent)
				case .standard: content.buttonStyle(.bordered)
				}
			}
		}
		.controlSize(size)
		// Capsule, everywhere, stated once.
		//
		// `.glass` picks its own shape from the control's size, so a regular button came out
		// a rounded rectangle and a small one came out nearly a capsule — two shapes for the
		// same control, side by side in the same row on the credits and test panes. macOS 26
		// draws its own glass controls as capsules; matching that also means the app has one
		// button shape rather than a shape per size.
		.buttonBorderShape(.capsule)
	}
}

/// A choice shown as a native pop-up menu: a `Menu` holding an inline `Picker`.
///
/// One type for every "pick one of a few" row, so Face position, Movements and Theme share
/// the same sizing, typography and button treatment. The displayed value is the row's own
/// type scale with intrinsic sizing — no fixed width, so a longer value grows the capsule
/// instead of clipping.
struct SettingsChoiceMenu<Selection: Hashable, Options: View>: View {
	let title: String
	let valueLabel: String
	@Binding var selection: Selection
	@ViewBuilder var options: () -> Options

	var body: some View {
		Menu {
			Picker(title, selection: $selection) { options() }
				.pickerStyle(.inline)
		} label: {
			Text(valueLabel)
				.font(Typography.control)
				.lineLimit(1)
		}
		.menuStyle(.button)
		.buttonStyle(.glass)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.accessibilityLabel(title)
		.accessibilityValue(valueLabel)
		.fixedSize()
	}
}

/// The shared expandable-row treatment for the native `DisclosureGroup`s.
///
/// Label styling lives in `Theme.disclosureLabel(_:)`; this modifier carries the native
/// disclosure tint and the row padding. Inside a native `Form` it applies neither padding:
/// the form owns row insets there, and adding its own would double them.
struct SettingsDisclosureRowStyle: ViewModifier {
	@Environment(\.nativeSettingsForm) private var nativeForm

	func body(content: Content) -> some View {
		content
			.tint(Theme.secondaryLabel)
			.padding(.horizontal, nativeForm ? 0 : Theme.rowInset)
			.padding(.vertical, nativeForm ? 0 : 14)
	}
}

extension Theme {
	/// An expandable row's label: the row type scale in the primary label colour.
	static func disclosureLabel(_ title: String) -> some View {
		Text(title)
			.font(Typography.row)
			.foregroundStyle(Theme.label)
	}
}

extension View {
	func settingsDisclosureRow() -> some View {
		modifier(SettingsDisclosureRowStyle())
	}
}

/// A small ⓘ that opens a popover.
///
/// For the explanation that is too long to sit in a row's subtitle but too important to leave
/// in a file on GitHub. A footer under the group would hold it, but a footer is read by
/// nobody who has already decided — this is read by the person hesitating.
struct InfoButton<Content: View>: View {

	let title: String
	var opensOnHover = false
	@ViewBuilder var content: Content

	@State private var isShowing = false
	@State private var buttonHovered = false
	@State private var popoverHovered = false
	@State private var pinned = false
	@FocusState private var buttonFocused: Bool
	@FocusState private var popoverFocused: Bool
	// Keyboard focus and VoiceOver focus are separate systems; the popover needs both.
	@AccessibilityFocusState private var popoverVoiceOverFocused: Bool

	var body: some View {
		Button {
			if pinned {
				pinned = false
				isShowing = false
			} else {
				pinned = true
				isShowing = true
			}
		} label: {
			Image(systemName: "info.circle")
				.font(Typography.control)
				.foregroundStyle(Theme.secondaryLabel)
				.frame(minWidth: 22, minHeight: 22)
				.contentShape(.circle)
		}
		.buttonStyle(.plain)
		.help(title)
		.accessibilityLabel(title)
		.focused($buttonFocused)
		.onHover { buttonHovered = $0 }
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
			// Focusable so keyboard and VoiceOver users can reach the explanation, but
			// without the ring macOS draws around a focusable container — a blue box
			// around a paragraph of help text reads as an error, not as focus.
			.focusable()
			.focusEffectDisabled()
			.focused($popoverFocused)
			.accessibilityElement(children: .combine)
			.accessibilityFocused($popoverVoiceOverFocused)
			.onHover { popoverHovered = $0 }
		}
		.task(id: buttonHovered || popoverHovered) {
			guard opensOnHover else { return }
			let hovering = buttonHovered || popoverHovered
			do { try await Task.sleep(for: .milliseconds(hovering ? 350 : 250)) }
			catch { return }
			guard !pinned else { return }
			isShowing = hovering
		}
		.onChange(of: isShowing) { _, shown in
			// Escape and outside-clicks dismiss via the binding, so focus is restored here rather than in key handling.
			if shown { popoverFocused = true; popoverVoiceOverFocused = true } else {
				let hadFocus = popoverFocused
				pinned = false; popoverHovered = false
				if hadFocus { buttonFocused = true }
			}
		}
		.onDisappear { isShowing = false; pinned = false }
	}
}
