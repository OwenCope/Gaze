import SwiftUI

/// Notch appearance controls.
///
/// Built around previews rather than descriptions. A paragraph explaining what "Semi
/// Liquid Glass" means is both longer and less useful than a thumbnail of it — the eye
/// settles the question before the sentence is finished.
struct NotchSettingsSection: View {

	@Bindable var settings: Preferences

	/// Read once — decoding the desktop picture on every redraw would be wasteful.
	@State private var wallpaper: NSImage? = WallpaperBrightness.notchStripThumbnail()

	var body: some View {
		SettingsSection(title: "Notch") {
			styleRow
			if settings.notchStyle == .semiLiquidGlass {
				RowDivider(inset: 55)
				SliderRow(
					title: "Transparency",
					value: $settings.notchTransparency,
					range: 0...1,
					format: { String(format: "%.2f", $0) })
			}
			RowDivider(inset: 55)
			SliderRow(
				title: "Height",
				value: $settings.notchHeightAdjust,
				range: -20...20,
				format: { "\(Int($0)) px" })
			RowDivider(inset: 55)
			SliderRow(
				title: "Width",
				value: $settings.notchWidthAdjust,
				range: -40...40,
				format: { "\(Int($0)) px" })
		}
	}

	private var styleRow: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 12) {
				IconTile(symbol: "paintbrush.fill")
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
						wallpaper: wallpaper)
				}
			}
		}
		.padding(Theme.rowPadding)
	}
}

/// A thumbnail of what the notch will look like in a given style.
private struct StylePreview: View {

	let style: Preferences.NotchStyle
	let isSelected: Bool
	let select: () -> Void
	let wallpaper: NSImage?

	var body: some View {
		Button(action: select) {
			VStack(spacing: 6) {
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

					notchShape
						.frame(height: 26)
				}
				.frame(height: 56)
				.clipShape(.rect(cornerRadius: 9, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 9, style: .continuous)
						.strokeBorder(
							isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.10),
							lineWidth: isSelected ? 2 : 1)
				}

				Text(style.title)
					.font(.system(size: 10, weight: isSelected ? .semibold : .regular))
					.foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
		}
		.buttonStyle(.plain)
		.animation(.easeOut(duration: 0.15), value: isSelected)
	}

	@ViewBuilder
	private var notchShape: some View {
		let shape = UnevenRoundedRectangle(
			topLeadingRadius: 0, bottomLeadingRadius: 5,
			bottomTrailingRadius: 5, topTrailingRadius: 0, style: .continuous)

		switch style {
		case .normal:
			shape.fill(.black)
		case .semiLiquidGlass:
			shape.fill(.black.opacity(0.72))
				.background(shape.fill(.ultraThinMaterial))
		case .liquidGlass:
			shape.fill(.black.opacity(0.28))
				.background(shape.fill(.ultraThinMaterial))
		}
	}
}

/// A labelled slider with its value in a pill.
///
/// The pill matters: a bare slider tells you there is a value but not what it is, so any
/// adjustment becomes trial and error.
struct SliderRow: View {

	let title: String
	@Binding var value: Double
	let range: ClosedRange<Double>
	var format: (Double) -> String

	var body: some View {
		VStack(spacing: 9) {
			HStack {
				Text(title)
					.font(.system(size: 13))
					.foregroundStyle(Theme.label)
				Spacer()
				Text(format(value))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(Theme.secondaryLabel)
					.padding(.horizontal, 10)
					.padding(.vertical, 4)
					.background(Capsule().fill(Theme.surfaceRaised))
					.contentTransition(.numericText())
			}

			VStack(spacing: 5) {
				Slider(value: $value, in: range)
					.controlSize(.small)
					.tint(Theme.label.opacity(0.85))

				// Tick marks. They give the track a sense of scale, so a slider reads as a
				// measured range rather than a smear between two ends.
				HStack(spacing: 0) {
					ForEach(0..<9, id: \.self) { index in
						Circle()
							.fill(Theme.tertiaryLabel.opacity(0.5))
							.frame(width: 2, height: 2)
						if index < 8 { Spacer(minLength: 0) }
					}
				}
				.padding(.horizontal, 6)
			}
		}
		.padding(Theme.rowPadding)
	}
}
