import SwiftUI

/// Design tokens.
///
/// Face ID is dark on every Apple platform and accents in the system green, so the whole
/// palette is derived from those two facts rather than following the system appearance.
enum Theme {

	// MARK: - Colour

	static let background = Color.black
	/// Card fill. Light enough to separate from the ground, dark enough that white text
	/// stays comfortable.
	static let surface = Color.white.opacity(0.055)
	static let surfaceRaised = Color.white.opacity(0.09)
	static let separator = Color.white.opacity(0.08)

	static let label = Color.white
	static let secondaryLabel = Color.white.opacity(0.55)
	static let tertiaryLabel = Color.white.opacity(0.35)

	/// Apple's system green — the Face ID accent.
	static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)
	static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
	static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

	// MARK: - Metrics

	static let cornerRadius: CGFloat = 12
	static let rowPadding: CGFloat = 14
	static let sectionSpacing: CGFloat = 26
}

// MARK: - Section

/// A titled group of rows.
struct SettingsSection<Content: View>: View {

	let title: String
	var footer: String?
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title.uppercased())
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(Theme.tertiaryLabel)
				.tracking(0.6)
				.padding(.leading, 4)

			VStack(spacing: 0) {
				content
			}
			.background(Theme.surface)
			.clipShape(.rect(cornerRadius: Theme.cornerRadius))

			if let footer {
				Text(footer)
					.font(.system(size: 11))
					.foregroundStyle(Theme.tertiaryLabel)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, 4)
			}
		}
	}
}

/// Hairline between rows, inset to line up with the text rather than the card edge.
struct RowDivider: View {
	var body: some View {
		Rectangle()
			.fill(Theme.separator)
			.frame(height: 1)
			.padding(.leading, Theme.rowPadding)
	}
}

// MARK: - Rows

/// A row with a title, optional explanation, and trailing control.
struct SettingRow<Trailing: View>: View {

	let title: String
	var detail: String?
	var isEnabled = true
	@ViewBuilder var trailing: Trailing

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
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
		.padding(Theme.rowPadding)
	}
}

/// A toggle styled to the palette, with its explanation inline.
struct SettingToggle: View {

	let title: String
	var detail: String?
	var isEnabled = true
	@Binding var isOn: Bool

	var body: some View {
		SettingRow(title: title, detail: detail, isEnabled: isEnabled) {
			Toggle("", isOn: $isOn)
				.labelsHidden()
				.toggleStyle(.switch)
				.tint(Theme.accent)
				.disabled(!isEnabled)
		}
	}
}

/// A selectable option in a radio-style list.
struct SettingChoice: View {

	let title: String
	let detail: String
	let isSelected: Bool
	let select: () -> Void

	var body: some View {
		Button(action: select) {
			HStack(alignment: .top, spacing: 11) {
				Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
					.font(.system(size: 15))
					.foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryLabel)
					.padding(.top, 1)

				VStack(alignment: .leading, spacing: 3) {
					Text(title)
						.font(.system(size: 13, weight: isSelected ? .medium : .regular))
						.foregroundStyle(Theme.label)
					Text(detail)
						.font(.system(size: 11))
						.foregroundStyle(Theme.secondaryLabel)
						.fixedSize(horizontal: false, vertical: true)
						.multilineTextAlignment(.leading)
				}
				Spacer(minLength: 0)
			}
			.padding(Theme.rowPadding)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}
}

/// Status pill — readiness, lockout, warnings.
struct StatusPill: View {

	enum Kind {
		case ok, warning, error

		var tint: Color {
			switch self {
			case .ok: return Theme.accent
			case .warning: return Theme.warning
			case .error: return Theme.danger
			}
		}

		var symbol: String {
			switch self {
			case .ok: return "checkmark.circle.fill"
			case .warning: return "exclamationmark.circle.fill"
			case .error: return "xmark.circle.fill"
			}
		}
	}

	let kind: Kind
	let message: String

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: kind.symbol)
				.font(.system(size: 12))
				.foregroundStyle(kind.tint)
				.padding(.top, 1)
			Text(message)
				.font(.system(size: 11))
				.foregroundStyle(Theme.secondaryLabel)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, Theme.rowPadding)
		.padding(.vertical, 11)
		.background(kind.tint.opacity(0.09))
	}
}

/// The app's primary button.
struct AccentButtonStyle: ButtonStyle {
	var role: ButtonRole?

	func makeBody(configuration: Configuration) -> some View {
		let tint = role == .destructive ? Theme.danger : Theme.accent
		return configuration.label
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(tint)
			.padding(.horizontal, 14)
			.padding(.vertical, 7)
			.background(tint.opacity(configuration.isPressed ? 0.28 : 0.16))
			.clipShape(.capsule)
	}
}
