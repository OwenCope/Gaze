import CoreGraphics

/// Shared dimensions for the TourKit cards in setup.
///
/// The introduction (`GazeWelcomeTour`) and the completion screen
/// (`SetupDoneStep`) render the upstream `TourSlideshowView` at `baseWidth`
/// and uniformly scale it up to `panelWidth`, so both cards share one
/// footprint with the rest of the setup window. Dimensions only — not a
/// custom slideshow. The separate movement guide uses this same enum.
enum GazeTourSizing {
	static let baseWidth: CGFloat = 660
	static let panelWidth: CGFloat = 720
	static let panelHeight: CGFloat = 680
	static let scale: CGFloat = panelWidth / baseWidth
}
