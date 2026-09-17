import SwiftUI

private struct NotchChoiceMenu<Selection: Hashable, Options: View>: View {
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
				.font(.system(size: 13))
				.frame(width: 140, alignment: .leading)
		}
		.menuStyle(.button)
		.buttonStyle(.glass)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.accessibilityLabel(title)
		.accessibilityValue(valueLabel)
	}
}

struct NotchSettingsSection: View {
	@Bindable var settings: Preferences
	@State private var sizeExpanded = false
	@State private var expressionsExpanded = false

	private var isOnEar: Bool {
		settings.panelShape == .attached && settings.glyphPlacement == .ear
	}

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
		NotchAppearancePreview(settings: settings)

		SettingsSection(title: "Appearance", info: styleFooter) {
			SettingRow(title: "Panel") {
				Picker("Panel", selection: $settings.panelShape) {
					ForEach(Preferences.PanelShape.allCases, id: \.self) { shape in
						Text(shape.title).tag(shape)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.controlSize(.regular)
				.frame(width: 330)
				.accessibilityLabel("Panel")
			}

				if settings.panelShape == .attached {
					RowDivider(inset: Theme.rowInset)
					SettingRow(title: "Face position") {
						NotchChoiceMenu(title: "Face position",
							valueLabel: settings.glyphPlacement == .centred ? "In the panel" : "Beside the camera",
							selection: $settings.glyphPlacement) {
							ForEach(Preferences.GlyphPlacement.allCases, id: \.self) { placement in
								Text(placement == .centred ? "In the panel" : "Beside the camera").tag(placement)
							}
						}
					}
				}

				if !isOnEar {
					RowDivider(inset: Theme.rowInset)
				SettingRow(title: "Material") {
					Picker("Material", selection: $settings.notchStyle) {
						ForEach(Preferences.NotchStyle.allCases, id: \.self) { style in
							Text(materialTitle(style)).tag(style)
						}
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.controlSize(.regular)
					.frame(width: 330)
					.accessibilityLabel("Material")
				}
					if settings.notchStyle == .semiLiquidGlass {
						RowDivider(inset: Theme.rowInset)
						NotchAdjustmentRow(
							title: "Transparency",
							value: $settings.notchTransparency,
							range: 0...1,
							step: 0.01,
							format: { "\(Int(($0 * 100).rounded()))%" })
					}
				}
			}

		sizeControls

		SettingsSection {
			DisclosureGroup("What Gaze’s expressions mean", isExpanded: $expressionsExpanded) {
				GazeExpressionGuide(compact: true, movementCount: settings.unlockMovementCount.rawValue)
					.padding(.vertical, 12)
			}
			.padding(Theme.rowInset)
		}
	}
		.onChange(of: settings.panelShape, initial: true) { _, shape in
			if shape == .island && settings.glyphPlacement != .centred {
				settings.glyphPlacement = .centred
			}
		}
	}

	private var sizeControls: some View {
		SettingsSection {
			DisclosureGroup(isExpanded: $sizeExpanded) {
				VStack(spacing: 0) {
					if !isOnEar {
						NotchAdjustmentRow(title: "Height", value: $settings.notchHeightAdjust,
							range: -20...20, format: adjustmentLabel)
					}
					NotchAdjustmentRow(title: "Width", value: $settings.notchWidthAdjust,
						range: -40...40, format: adjustmentLabel)
					HStack(alignment: .firstTextBaseline, spacing: 16) {
						Text("Adjust only if the panel doesn't fit your notch.")
							.font(Typography.detail)
							.foregroundStyle(Theme.secondaryLabel)
						Spacer(minLength: 0)
						Button("Reset Size") {
							if !isOnEar { settings.notchHeightAdjust = 0 }
							settings.notchWidthAdjust = 0
						}
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.disabled(settings.notchWidthAdjust == 0 && (isOnEar || settings.notchHeightAdjust == 0))
					}
					.padding(.horizontal, Theme.rowInset)
					.padding(.top, 4)
					.padding(.bottom, 12)
				}
			} label: {
				Text("Fine-tune size")
					.font(Typography.row)
					.foregroundStyle(Theme.label)
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 14)
			.tint(Theme.secondaryLabel)
		}
	}

	private func adjustmentLabel(_ value: Double) -> String {
		"\(value > 0 ? "+" : "")\(Int(value.rounded())) pt"
	}

	private func materialTitle(_ style: Preferences.NotchStyle) -> String {
		switch style {
		case .normal: "Solid"
		case .semiLiquidGlass: "Frosted glass"
		case .liquidGlass: "Liquid Glass"
		}
	}

	private var styleFooter: String {
		if isOnEar {
			return "The mark sits beside the camera. No panel drops below the notch."
		}
		switch settings.notchStyle {
		case .normal:
			return "Solid black, blending into your Mac's camera housing."
		case .semiLiquidGlass:
			return "A dark panel with a softly blurred background."
		case .liquidGlass:
			return "Native glass that responds to the background."
		}
	}
}

private struct NotchAppearancePreview: View {
	let settings: Preferences
	@State private var model: NotchCapsuleModel
	@State private var wallpaper = DesktopWallpaper.shared

	init(settings: Preferences) {
		self.settings = settings
		let model = NotchCapsuleModel()
		model.shape = settings.panelShape
		model.style = settings.notchStyle
		model.glyphPlacement = settings.panelShape == .island ? .centred : settings.glyphPlacement
		model.transparency = settings.notchTransparency
		model.isExpanded = true
		_model = State(initialValue: model)
	}

	var body: some View {
		VStack(spacing: 0) {
			NotchPreviewCanvas(model: model,
				widthAdjust: settings.notchWidthAdjust,
				heightAdjust: settings.notchHeightAdjust,
				wallpaper: wallpaper.image,
				background: Color(nsColor: .windowBackgroundColor))
				.frame(height: 252)
				.clipShape(.rect(cornerRadius: 12))
				.allowsHitTesting(false)
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("Notch appearance preview")
				.accessibilityValue(previewDescription)
			HStack {
				Text("Appearance preview")
					.font(Typography.groupTitle)
				Spacer()
				Label("Camera off", systemImage: "video.slash")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
			}
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 12)
		}
		.onChange(of: settings.panelShape) { _, _ in syncAppearance() }
		.onChange(of: settings.notchStyle) { _, _ in syncAppearance() }
		.onChange(of: settings.glyphPlacement) { _, _ in syncAppearance() }
		.onChange(of: settings.notchTransparency) { _, _ in syncAppearance() }
		.onAppear { syncAppearance(); model.isExpanded = true }
		.onDisappear { model.isExpanded = false }
	}

	private var previewDescription: String {
		let appearance = model.glyphPlacement == .ear ? "Mark on the ear" : model.style.title
		return "\(model.shape.title), \(appearance). Simulated appearance; camera off."
	}

	private func syncAppearance() {
		model.shape = settings.panelShape
		model.style = settings.notchStyle
		model.glyphPlacement = settings.panelShape == .island ? .centred : settings.glyphPlacement
		model.transparency = settings.notchTransparency
	}
}

private struct NotchAdjustmentRow: View {
	let title: String
	@Binding var value: Double
	let range: ClosedRange<Double>
	var step: Double = 1
	let format: (Double) -> String

	var body: some View {
		HStack(spacing: 16) {
			Text(title)
				.font(Typography.row)
				.frame(width: 104, alignment: .leading)
			Slider(value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }), in: range, step: step)
				.controlSize(.small)
				.tint(Theme.label.opacity(0.85))
				.accessibilityLabel(title)
				.accessibilityValue(format(value))
			Text(format(value))
				.font(Typography.detail.monospacedDigit())
				.foregroundStyle(Theme.secondaryLabel)
				.frame(width: 48, alignment: .trailing)
				.accessibilityHidden(true)
		}
		.padding(.horizontal, Theme.rowInset)
		.padding(.vertical, 12)
	}
}
