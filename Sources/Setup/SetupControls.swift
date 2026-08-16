import SwiftUI

/// Setup's primary button.
///
/// Full-width capsule on a dark ground, the way Apple's own setup assistants do
/// it: at this size the button is the only thing to press, so it is stated
/// plainly rather than tucked into a corner.
struct SetupButton: View {
	var title: String = "Continue"
	var isProminent = true
	var action: () -> Void

	@Environment(\.isEnabled) private var isEnabled

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.body.weight(.semibold))
				.frame(maxWidth: .infinity)
				.frame(height: 40)
		}
		.buttonStyle(SetupButtonStyle(isProminent: isProminent, isEnabled: isEnabled))
		.frame(maxWidth: 280)
	}
}

private struct SetupButtonStyle: ButtonStyle {
	let isProminent: Bool
	let isEnabled: Bool

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.foregroundStyle(isProminent ? Color.black : Color.white)
			.opacity(isEnabled ? 1 : 0.35)
			.background {
				Capsule().fill(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)))
			}
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
	}
}


