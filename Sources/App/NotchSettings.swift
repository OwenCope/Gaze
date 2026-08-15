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
				//
				// Only shown for the attached panel. The island *is* a panel built to carry
				// the mark, so taking the mark out of it leaves an empty square hanging under
				// the notch — the choice only has two sensible answers in attached mode.
				if settings.panelShape == .attached {
					RowDivider()
					choiceRow(
						title: "Gaze mark",
						values: Preferences.GlyphPlacement.allCases,
					titleFor: \.title,
						isSelected: { settings.glyphPlacement == $0 },
						select: { settings.glyphPlacement = $0 }
					) { placement in
						ShapeSketch(shape: settings.panelShape, placement: placement)
					}
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

			// Leading, not centred. A row of two tiles was centring itself under a heading
			// pinned to the left, so the two rows with two options each sat off-axis from
			// everything above and below them.
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
				Spacer(minLength: 0)
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
				Spacer(minLength: 0)
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

	@State private var isHovering = false

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
				.overlay { SelectionRing(isSelected: isSelected, isHovering: isHovering) }

				// No `minimumScaleFactor`. It let "Semi Liquid Glass" shrink to 8pt — under
				// the size macOS draws text at legibly — to avoid a wrap the layout can
				// simply absorb.
				Text(style.title)
					.font(Typography.caption)
					.fontWeight(isSelected ? .semibold : .regular)
					.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
					.lineLimit(2)
					.multilineTextAlignment(.center)
					.frame(height: 26, alignment: .top)
			}
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
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

/// The ring around the selected thumbnail.
///
/// Two wrong turns to get here. A ring in `Theme.label` was black on a dark photo in light
/// mode; a glass platter behind the tile solved the contrast but read as a stray pale box
/// sitting in the group, because glass on top of a card that is already glass has nothing to
/// separate itself from.
///
/// A coloured ring is what System Settings uses for wallpapers and appearance, and what
/// Dynamic Lake uses for exactly this control. Colour is the point: it belongs to neither the
/// photograph nor the panel, so it cannot be lost in either, in either appearance.
private struct SelectionRing: View {

	let isSelected: Bool
	let isHovering: Bool

	private var shape: RoundedRectangle {
		RoundedRectangle(cornerRadius: 7, style: .continuous)
	}

	var body: some View {
		shape.strokeBorder(
			isSelected
				? Theme.active
				: (isHovering ? Theme.label.opacity(0.35) : Theme.separator),
			lineWidth: isSelected ? 2.5 : 1)
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
					.fontWeight(isSelected ? .semibold : .regular)
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
					// One shape: the housing continuing downward, square across the top and
					// rounded only along the bottom.
					UnevenRoundedRectangle(
						topLeadingRadius: 0, bottomLeadingRadius: 7,
						bottomTrailingRadius: 7, topTrailingRadius: 0, style: .continuous
					)
					.fill(.black.opacity(0.88))
					.frame(width: 62, height: barHeight + 18)
					.overlay(alignment: .center) { glyph(.face).padding(.top, 5) }

				case .island:
					// Two shapes, proportioned against the real ones.
					//
					// The bar is one notch tall and wider than the island; the island is a
					// square with the same radius ratio the panel uses, separated by a gap
					// small enough to read as "just detached" rather than as two unrelated
					// objects. It was a tall bar over a small square with a wide gap, which
					// described neither.
					Rectangle()
						.fill(.black.opacity(0.9))
						.frame(width: 54, height: 9)
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(.black.opacity(0.92))
						.frame(width: 36, height: 36)
						// The hint of green the real island carries at its foot.
						.overlay {
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(
									LinearGradient(
										stops: [
											.init(color: .clear, location: 0.45),
											.init(color: Theme.faceID.opacity(0.22), location: 1),
										],
										startPoint: .top, endPoint: .bottom))
						}
						.overlay { glyph(.face) }
						.padding(.top, 2)
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
