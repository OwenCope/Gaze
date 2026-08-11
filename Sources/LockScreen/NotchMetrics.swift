import AppKit

/// The physical notch's position and size.
///
/// Measured rather than hardcoded: notch dimensions differ between MacBook Air and Pro and
/// across sizes, and a capsule that is a few points wider than the cutout reads as a
/// floating pill rather than as the notch itself growing.
enum NotchMetrics {

	/// Width of the camera housing, in points, or nil on a screen without one.
	///
	/// Derived from the two menu bar fragments either side of the cutout: macOS reports
	/// those as auxiliary areas, and whatever lies between them is the notch.
	static func width(on screen: NSScreen) -> CGFloat? {
		guard
			let left = screen.auxiliaryTopLeftArea,
			let right = screen.auxiliaryTopRightArea
		else { return nil }
		let gap = right.minX - left.maxX
		return gap > 0 ? gap : nil
	}

	/// Height of the notch — the menu bar's safe area inset.
	static func height(on screen: NSScreen) -> CGFloat {
		let inset = screen.safeAreaInsets.top
		return inset > 0 ? inset : screen.frame.maxY - screen.visibleFrame.maxY
	}

	/// True when this screen physically has a notch.
	static func hasNotch(on screen: NSScreen) -> Bool {
		width(on: screen) != nil
	}

	/// The rectangle the notch itself occupies, in screen coordinates.
	static func frame(on screen: NSScreen) -> NSRect? {
		guard let width = width(on: screen) else { return nil }
		let height = height(on: screen)
		return NSRect(
			x: screen.frame.midX - width / 2,
			y: screen.frame.maxY - height,
			width: width,
			height: height)
	}
}
