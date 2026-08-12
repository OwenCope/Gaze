import SwiftUI

/// Notch appearance controls.
///
/// Built around previews rather than descriptions. A paragraph explaining what "Semi
/// Liquid Glass" means is both longer and less useful than a thumbnail of it — the eye
/// settles the question before the sentence is finished.
///
/// Laid out like System Settings' Appearance row: label at the leading edge, thumbnails at
/// the trailing edge, names underneath them.
struct NotchSettingsSection: View {

	@Bindable var settings: Preferences

	/// Read once — decoding the desktop picture on every redraw would be wasteful.
	@State private var wallpaper: NSImage? = WallpaperBrightness.notchStripThumbnail()

	/// The same measurement the real panel adapts to, so the preview shows the panel the
	/// user will actually get rather than the un-boosted one.
	@State private var wallpaperIsLight: Bool =
		NSScreen.main.map(WallpaperBrightness.isLight(on:)) ?? false

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection(title: "Notch", footer: styleFooter) {
				// Shape before style: it decides what the style is even applied to.
				//
				// Shown as thumbnails rather than a pop-up menu. "Attached" and "Island" are
				// words for shapes, and a word for a shape is a worse description of it than
				// the shape is — the same reason Style has never been a menu.
				choiceRow(
					title: "Shape",
					values: Preferences.PanelShape.allCases,
					titleFor: \.title,
					isSelected: { settings.panelShape == $0 },
					select: { settings.panelShape = $0 }
				) { shape in
					ShapeSketch(shape: shape, placement: settings.glyphPlacement)
				}

				RowDivider()
				styleRow

				// Ruken's suggestion, as a choice rather than a change.
				RowDivider()
				choiceRow(
					title: "Face ID mark",
					values: Preferences.GlyphPlacement.allCases,
					titleFor: \.title,
					isSelected: { settings.glyphPlacement == $0 },
					select: { settings.glyphPlacement = $0 }
				) { placement in
					ShapeSketch(shape: settings.panelShape, placement: placement)
				}
				if settings.notchStyle == .semiLiquidGlass {
					RowDivider()
					SliderRow(
						title: "Transparency",
						symbol: "circle.righthalf.filled",
						value: $settings.notchTransparency,
						range: 0...1,
						format: { String(format: "%.2f", $0) })
				}
			}

			SettingsSection(
				title: "Notch size",
				footer: "Nudge these if the panel doesn't line up with your notch."
			) {
				SliderRow(
					title: "Height",
					symbol: "arrow.up.and.down",
					value: $settings.notchHeightAdjust,
					range: -20...20,
					format: { "\(Int($0)) px" })
				RowDivider()
				SliderRow(
					title: "Width",
					symbol: "arrow.left.and.right",
					value: $settings.notchWidthAdjust,
					range: -40...40,
					format: { "\(Int($0)) px" })
			}
		}
	}

	/// Says what the selected style actually is, so the thumbnail is not the only evidence.
	private var styleFooter: String {
		if settings.panelShape == .island {
			return Preferences.PanelShape.island.detail
				+ ". Nebulark's idea, built from his concept."
		}
		switch settings.notchStyle {
		case .normal:
			return "Solid black. On a dark wallpaper it's indistinguishable from the cutout."
		case .semiLiquidGlass:
			return "Dark, with the wallpaper coming through a blur."
		case .liquidGlass:
			return "The system's glass material, which refracts what's behind it."
		}
	}

	/// A row of thumbnails, the way the Style row works.
	///
	/// Generic because there are three of these now and they differ only in what they draw.
	/// A settings pane that shows you the thing and a settings pane that names the thing are
	/// different products; this one shows you.
	private func choiceRow<Value: Hashable, Sketch: View>(
		title: String,
		values: [Value],
		titleFor: KeyPath<Value, String>,
		isSelected: @escaping (Value) -> Bool,
		select: @escaping (Value) -> Void,
		@ViewBuilder sketch: @escaping (Value) -> Sketch
	) -> some View {
		// No icon tile before the label.
		//
		// An icon column earns its place on a list of switches, where it gives each row a
		// shape to scan by. Above a row of thumbnails it is a second picture competing with
		// three real ones, and the thumbnails already say what the setting is.
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(Typography.row)
				.foregroundStyle(Theme.label)

			HStack(spacing: 10) {
				ForEach(values, id: \.self) { value in
					PreviewTile(
						title: value[keyPath: titleFor],
						isSelected: isSelected(value),
						select: { select(value) },
						wallpaper: wallpaper
					) {
						sketch(value)
					}
				}
			}
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 11)
	}

	private var styleRow: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Style")
				.font(Typography.row)
				.foregroundStyle(Theme.label)

			HStack(spacing: 10) {
				ForEach(Preferences.NotchStyle.allCases, id: \.self) { style in
					StylePreview(
						style: style,
						isSelected: settings.notchStyle == style,
						select: { settings.notchStyle = style },
						transparency: settings.notchTransparency,
						wallpaper: wallpaper,
						wallpaperIsLight: wallpaperIsLight)
				}
			}
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 11)
	}
}

/// A thumbnail of what the notch will look like in a given style.
private struct StylePreview: View {

	let style: Preferences.NotchStyle
	let isSelected: Bool
	let select: () -> Void
	let transparency: Double
	let wallpaper: NSImage?
	let wallpaperIsLight: Bool

	var body: some View {
		Button(action: select) {
			VStack(spacing: 5) {
				ZStack(alignment: .top) {
					// The user's actual wallpaper, cropped to the strip under the notch.
					// An invented gradient made all three styles look identical.
					if let wallpaper {
						Image(nsImage: wallpaper)
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						LinearGradient(
							colors: [
								Color(red: 0.42, green: 0.52, blue: 0.66),
								Color(red: 0.78, green: 0.62, blue: 0.48),
							],
							startPoint: .topLeading, endPoint: .bottomTrailing)
					}

					// A centred drop with wallpaper either side, not a full-width band.
					//
					// Spanning the whole thumbnail was the reason all three looked alike:
					// with nothing but panel across the top there was no unobscured
					// wallpaper to judge it against, so "darker" and "clearer" landed the
					// same. Bordered by the picture it sits on, the differences read.
					panel
						.frame(width: 60, height: 32)
						.overlay {
							Image(systemName: "faceid")
								.font(.system(size: 12))
								.foregroundStyle(.white)
								.padding(.top, 3)
						}
				}
				.frame(width: 112, height: 62)
				.clipShape(.rect(cornerRadius: 7, style: .continuous))
				.overlay { SelectionRing(isSelected: isSelected, isHovering: false) }

				// No `minimumScaleFactor`. It let "Semi Liquid Glass" shrink to 8pt — under
				// the size macOS draws text at legibly — to avoid a wrap the layout can
				// simply absorb.
				Text(style.title)
					.font(Typography.caption)
					.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
					.lineLimit(2)
					.multilineTextAlignment(.center)
					.frame(height: 26, alignment: .top)
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(style.title)
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
		.animation(.easeOut(duration: 0.15), value: isSelected)
	}

	/// The panel deepens itself over a light wallpaper, so the preview has to as well —
	/// otherwise it advertises a paler glass than the lock screen will actually show.
	private var boost: Double { wallpaperIsLight ? 0.22 : 0 }

	private var shape: UnevenRoundedRectangle {
		UnevenRoundedRectangle(
			topLeadingRadius: 0, bottomLeadingRadius: 8,
			bottomTrailingRadius: 8, topTrailingRadius: 0, style: .continuous)
	}

	/// Mirrors `NotchCapsule.background` exactly — same fills, same fade, same exemption.
	///
	/// "Exactly" is a duty, not a nicety: the preview fading Normal to clear is why all
	/// three thumbnails looked like variations of the same grey wash and the user reasonably
	/// concluded the setting did nothing. Normal is solid to its bottom edge here because it
	/// is solid to its bottom edge on the lock screen.
	@ViewBuilder
	private var panel: some View {
		switch style {
		case .normal:
			shape.fill(.black)
		case .semiLiquidGlass:
			shape
				.fill(.black.opacity(NotchGlass.semiTint(transparency: transparency, boost: boost)))
				.background { shape.fill(.ultraThinMaterial) }
				.mask { fade }
		case .liquidGlass:
			Color.clear
				.glassEffect(.regular.tint(.black.opacity(NotchGlass.liquidTint(boost: boost))), in: shape)
				.mask { fade }
		}
	}

	private var fade: some View {
		LinearGradient(
			stops: [
				.init(color: .black, location: 0),
				.init(color: .black, location: 0.36),
				.init(color: .black.opacity(0.72), location: 0.55),
				.init(color: .black.opacity(0.38), location: 0.76),
				.init(color: .black.opacity(0.12), location: 0.92),
				.init(color: .clear, location: 1),
			],
			startPoint: .top, endPoint: .bottom)
	}
}

/// The selected state for a thumbnail.
///
/// A single ring cannot do this job. The tiles are photographs of the user's own wallpaper,
/// so the ring has no known background to contrast against — and drawing it in `Theme.label`
/// meant black-on-a-dark-photo in light mode, which is where "I can't see what is selected"
/// came from.
///
/// Three things together, so no one of them has to work alone: a ring in the accent, a dark
/// halo just outside it that separates the ring from whatever the picture is doing, and a
/// filled tick in the corner. The tick is the part that never fails — it is a different
/// *shape*, not a different shade.
private struct SelectionRing: View {

	let isSelected: Bool
	let isHovering: Bool
	var cornerRadius: CGFloat = 7

	private var shape: RoundedRectangle {
		RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
	}

	var body: some View {
		ZStack(alignment: .topTrailing) {
			if isSelected {
				// The halo is the accent's opposite, not a fixed black. Fixed black works in
				// dark mode, where the ring is white — and in light mode the ring is black
				// too, so the pair would have been black on black and failed in exactly the
				// appearance the ring was added to fix.
				shape.strokeBorder(Theme.onAccent.opacity(0.7), lineWidth: 4)
				shape.strokeBorder(Theme.accent, lineWidth: 2)
			} else {
				shape.strokeBorder(
					isHovering ? Theme.label.opacity(0.45) : Theme.separator, lineWidth: 1)
			}

			if isSelected {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(size: 15, weight: .semibold))
					.symbolRenderingMode(.palette)
					.foregroundStyle(Theme.onAccent, Theme.accent)
					.padding(4)
			}
		}
	}
}

/// The wallpaper strip, selection ring and caption that every notch thumbnail shares.
///
/// Extracted because there are three rows of these now. What differs between them is the
/// sketch drawn on the wallpaper, and nothing else.
private struct PreviewTile<Content: View>: View {

	let title: String
	let isSelected: Bool
	let select: () -> Void
	let wallpaper: NSImage?
	@ViewBuilder var content: Content

	@State private var isHovering = false

	var body: some View {
		Button(action: select) {
			VStack(spacing: 5) {
				ZStack(alignment: .top) {
					if let wallpaper {
						Image(nsImage: wallpaper)
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						LinearGradient(
							colors: [
								Color(red: 0.42, green: 0.52, blue: 0.66),
								Color(red: 0.78, green: 0.62, blue: 0.48),
							],
							startPoint: .topLeading, endPoint: .bottomTrailing)
					}
					content
				}
				.frame(width: 112, height: 62)
				.clipShape(.rect(cornerRadius: 7, style: .continuous))
				.overlay { SelectionRing(isSelected: isSelected, isHovering: isHovering) }

				Text(title)
					.font(Typography.caption)
					.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
					.lineLimit(2)
					.multilineTextAlignment(.center)
					.frame(height: 26, alignment: .top)
			}
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
		.accessibilityLabel(title)
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
		.animation(.easeOut(duration: 0.15), value: isSelected)
	}
}

/// A small drawing of the panel: which shape it is, and where the mark sits.
///
/// Not the real `NotchCapsule`. That one is built around a physical cutout to hide behind
/// and a window sized to the screen, neither of which exists inside a 112pt thumbnail. This
/// draws the same two decisions at a size you can actually see them at.
private struct ShapeSketch: View {

	let shape: Preferences.PanelShape
	let placement: Preferences.GlyphPlacement

	/// The menu bar band, at roughly the proportion the real one occupies.
	private let barHeight: CGFloat = 13

	var body: some View {
		VStack(spacing: 0) {
			if placement == .ear {
				// Nothing drops. The bar carries the padlock on one ear and the mark on the
				// other, which is the whole of what this mode does.
				ZStack {
					Rectangle().fill(.black.opacity(0.88))
					HStack(spacing: 0) {
						glyph(.lock)
						Spacer(minLength: 0)
						glyph(.face)
					}
					.padding(.horizontal, 3)
				}
				.frame(width: 74, height: barHeight)

			} else {
				switch shape {
				case .attached:
					UnevenRoundedRectangle(
						topLeadingRadius: 0, bottomLeadingRadius: 7,
						bottomTrailingRadius: 7, topTrailingRadius: 0, style: .continuous
					)
					.fill(.black.opacity(0.88))
					.frame(width: 62, height: barHeight + 20)
					.overlay(alignment: .center) { glyph(.face).padding(.top, 6) }

				case .island:
					// The bar it comes out of, then the island itself, detached from it.
					Rectangle()
						.fill(.black.opacity(0.88))
						.frame(width: 46, height: barHeight)
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.fill(.black.opacity(0.9))
						.frame(width: 30, height: 30)
						.overlay { glyph(.face) }
						.padding(.top, 4)
				}
			}
			Spacer(minLength: 0)
		}
	}

	private enum Mark { case face, lock }

	private func glyph(_ mark: Mark) -> some View {
		Image(systemName: mark == .face ? "faceid" : "lock.fill")
			.font(.system(size: placement == .ear ? 7 : 11))
			.foregroundStyle(.white)
	}
}
