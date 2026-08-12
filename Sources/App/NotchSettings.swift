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

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
			SettingsSection(title: "Notch", footer: styleFooter) {
				styleRow
				if settings.notchStyle == .semiLiquidGlass {
					RowDivider()
					SliderRow(
						title: "Transparency",
						symbol: "circle.righthalf.filled", symbolTint: Theme.teal,
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
					symbol: "arrow.up.and.down", symbolTint: Theme.blue,
					value: $settings.notchHeightAdjust,
					range: -20...20,
					format: { "\(Int($0)) px" })
				RowDivider()
				SliderRow(
					title: "Width",
					symbol: "arrow.left.and.right", symbolTint: Theme.blue,
					value: $settings.notchWidthAdjust,
					range: -40...40,
					format: { "\(Int($0)) px" })
			}
		}
	}

	/// Says what the selected style actually is, so the thumbnail is not the only evidence.
	private var styleFooter: String {
		switch settings.notchStyle {
		case .normal:
			return "Solid black. On a dark wallpaper it's indistinguishable from the cutout."
		case .semiLiquidGlass:
			return "Dark, with the wallpaper coming through a blur."
		case .liquidGlass:
			return "The system's glass material, which refracts what's behind it."
		}
	}

	private var styleRow: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 12) {
				IconTile(symbol: "paintbrush.fill", tint: Theme.purple)
				Text("Style")
					.font(.system(size: 13))
					.foregroundStyle(Theme.label)
				Spacer()
			}

			HStack(spacing: 10) {
				ForEach(Preferences.NotchStyle.allCases, id: \.self) { style in
					StylePreview(
						style: style,
						isSelected: settings.notchStyle == style,
						select: { settings.notchStyle = style },
						transparency: settings.notchTransparency,
						wallpaper: wallpaper)
				}
			}
			.padding(.leading, 38)
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
				.overlay {
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.strokeBorder(
							isSelected ? Color.white : Color.white.opacity(0.12),
							lineWidth: isSelected ? 2 : 1)
				}

				Text(style.title)
					.font(.system(size: 10))
					.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
		}
		.buttonStyle(.plain)
		.animation(.easeOut(duration: 0.15), value: isSelected)
	}

	private var shape: UnevenRoundedRectangle {
		UnevenRoundedRectangle(
			topLeadingRadius: 0, bottomLeadingRadius: 8,
			bottomTrailingRadius: 8, topTrailingRadius: 0, style: .continuous)
	}

	/// Mirrors `NotchCapsule.background` exactly, fade and all.
	///
	/// Including the gradient mask matters as much as the fill: the real panel has no hard
	/// bottom edge, and a preview with one sets an expectation the lock screen does not
	/// meet.
	@ViewBuilder
	private var panel: some View {
		Group {
			switch style {
			case .normal:
				shape.fill(.black)
			case .semiLiquidGlass:
				shape
					.fill(.black.opacity(0.55 + 0.35 * (1 - transparency)))
					.background { shape.fill(.ultraThinMaterial) }
			case .liquidGlass:
				Color.clear
					.glassEffect(.regular.tint(.black.opacity(0.18)), in: shape)
			}
		}
		.mask {
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
}
