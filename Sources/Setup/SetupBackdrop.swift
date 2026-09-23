import SwiftUI

struct SetupBackdrop: View {
	var body: some View {
		ZStack {
			LinearGradient(
				colors: [Color(white: 0.11), Color.black],
				startPoint: .top,
				endPoint: .bottom
			)
			RadialGradient(
				colors: [
					Color(white: 0.32).opacity(0.22),
					Color.clear,
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
