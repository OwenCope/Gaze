import SwiftUI

/// The welcome stop of setup: the TourKit introduction, hosted in the flow.
///
/// A thin host around `GazeWelcomeTour` — the flow owns the window, the
/// slideshow owns only its pages. TourKit's Next pages internally and calls
/// `onContinue` on its final page; closing (Escape) calls `onSkip`.
struct SetupWelcomeStep: View {
	var movementCount: Int = 2
	var initialPageIndex: Int = 0
	var onPageChange: ((Int) -> Void)? = nil
	var onContinue: () -> Void
	var onSkip: () -> Void

	var body: some View {
		GazeWelcomeTour(
			onContinue: onContinue,
			onClose: onSkip,
			movementCount: movementCount,
			initialPageIndex: initialPageIndex,
			onPageChange: onPageChange
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.multilineTextAlignment(.center)
		.padding(.horizontal, 24)
	}
}
