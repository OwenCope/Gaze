import SwiftUI

struct SetupBackdrop: View {
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		ZStack {
			LinearGradient(
				colors: colorScheme == .dark
					? [Color(white: 0.14), Color(white: 0.07)]
					: [Color.white, Color(white: 0.90)],
				startPoint: .top,
				endPoint: .bottom
			)
			RadialGradient(
				colors: [
					Color.clear,
					(colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.10)),
				],
				center: .center,
				startRadius: 60,
				endRadius: 520
			)
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
		.ignoresSafeArea()
	}
}
