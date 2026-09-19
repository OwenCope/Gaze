import SwiftUI

/// A full-row navigation entry inside a settings group.
///
/// A real `Button` wrapping the existing `SettingRow` presentation, so keyboard
/// activation and the system focus treatment keep working. The trailing
/// chevron is a quiet affordance, not a separate control: it stays out of the
/// accessibility tree and the row's label and hint describe where it goes.
struct SettingsNavigationRow: View {
	let title: String
	var detail: String?
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			SettingRow(title: title, detail: detail) {
				Image(systemName: "chevron.right")
					.font(Typography.detail.weight(.semibold))
					.foregroundStyle(Theme.tertiaryLabel)
					.accessibilityHidden(true)
			}
			.contentShape(.rect)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.buttonStyle(.plain)
		.contentShape(.rect)
		.accessibilityLabel(title)
		.accessibilityHint(detail ?? "Opens")
	}
}
