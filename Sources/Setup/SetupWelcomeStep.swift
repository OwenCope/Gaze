import SwiftUI

/// Thin host around `GazeWelcomeTour`; the flow owns the window.
struct SetupWelcomeStep: View {
	var onContinue: () -> Void
	var onClose: () -> Void
	var initialPageIndex: Int = 0

	var body: some View {
		GazeWelcomeTour(
			onContinue: onContinue,
			onClose: onClose,
			initialPageIndex: initialPageIndex
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.overlay(alignment: .top) {
			Color.clear
				.frame(height: 10)
				.contentShape(Rectangle())
				.gesture(WindowDragGesture())
				.allowsWindowActivationEvents(true)
				.accessibilityHidden(true)
		}
	}
}
