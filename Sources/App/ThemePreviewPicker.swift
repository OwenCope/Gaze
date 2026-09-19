import SwiftUI

/// Compact visual choices for the Appearance theme row.
///
/// Each option is a schematic miniature of the same simplified settings window
/// (a top bar and two rows), not a screenshot. The parent owns the value through
/// `selection`; this view only assigns it on button activation.
struct ThemePreviewPicker: View {
	@Binding var selection: Preferences.AppTheme

	init(selection: Binding<Preferences.AppTheme>) {
		_selection = selection
	}

	private let columns = [GridItem(.adaptive(minimum: 112), spacing: 12)]

	var body: some View {
		LazyVGrid(columns: columns, spacing: 12) {
			ForEach(Preferences.AppTheme.allCases, id: \.self) { theme in
				let isSelected = theme == selection
				Button { selection = theme } label: {
					VStack(spacing: 5) {
						ThemePreviewThumbnail(theme: theme, isSelected: isSelected)
						Text(theme.title)
							.font(Typography.control)
							.foregroundStyle(Theme.secondaryLabel)
							.multilineTextAlignment(.center)
					}
					.frame(minWidth: 104)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(theme.title)
				.accessibilityAddTraits(isSelected ? .isSelected : [])
			}
		}
	}
}

/// A schematic settings-window miniature in fixed colours, so each preview shows
/// its own theme regardless of the appearance the Settings window is drawn in.
private struct ThemePreviewThumbnail: View {
	let theme: Preferences.AppTheme
	let isSelected: Bool

	var body: some View {
		ZStack(alignment: .topTrailing) {
			preview
				.frame(width: 104, height: 56)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			if isSelected {
				Circle()
					.fill(Theme.accent)
					.frame(width: 16, height: 16)
					.overlay {
						Image(systemName: "checkmark")
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(Theme.onAccent)
					}
					.padding(4)
			}
		}
		.overlay {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.strokeBorder(
					isSelected ? Theme.accent : Theme.separator,
					lineWidth: isSelected ? 2 : 1)
		}
		.accessibilityHidden(true)
	}

	@ViewBuilder
	private var preview: some View {
		switch theme {
		case .system:
			HStack(spacing: 0) {
				miniWindow(
					ground: Color(white: 0.92), bar: .white,
					row: .white, label: .black.opacity(0.65))
				miniWindow(
					ground: Color(white: 0.09), bar: .white.opacity(0.12),
					row: .white.opacity(0.14), label: .white.opacity(0.75))
			}
		case .light:
			miniWindow(
				ground: Color(white: 0.92), bar: .white,
				row: .white, label: .black.opacity(0.65))
		case .dark:
			miniWindow(
				ground: Color(white: 0.09), bar: .white.opacity(0.12),
				row: .white.opacity(0.14), label: .white.opacity(0.75))
		case .glass:
			// Same dark ground as the notch panel, with a solid highlight band
			// across the top instead of a gradient.
			VStack(spacing: 0) {
				Color.white.opacity(0.16).frame(height: 4)
				miniWindow(
					ground: .black, bar: .white.opacity(0.10),
					row: .white.opacity(0.14), label: .white.opacity(0.8))
			}
		}
	}

	private func miniWindow(ground: Color, bar: Color, row: Color, label: Color) -> some View {
		VStack(spacing: 4) {
			RoundedRectangle(cornerRadius: 2, style: .continuous)
				.fill(bar)
				.frame(height: 8)
			ForEach(0..<2, id: \.self) { _ in
				RoundedRectangle(cornerRadius: 3, style: .continuous)
					.fill(row)
					.frame(height: 12)
					.overlay(alignment: .leading) {
						RoundedRectangle(cornerRadius: 1.5, style: .continuous)
							.fill(label)
							.frame(width: 30, height: 4)
							.padding(.leading, 6)
					}
			}
		}
		.padding(6)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(ground)
	}
}
