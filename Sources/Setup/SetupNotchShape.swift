import SwiftUI

/// A panel that starts as the notch and widens below it.
///
/// This is the difference between a panel that *is* the notch and a panel that merely sits
/// near it, and it is why the setup panel read as a floating card. `NotchPanelShape` — which
/// the unlock capsule uses correctly — is full width at its top edge. On this Mac that made
/// the setup panel a 372pt black bar lying across the menu bar with the 179pt cutout buried
/// somewhere in the middle of it. Nothing about that says "the notch opened".
///
/// So the top of this shape is exactly the cutout: 179 × 32 on the measured display, drawn
/// black behind a housing that is already black, which makes it invisible. Below the
/// cutout the walls sweep outward to the panel's full width, and *that* is the part the eye
/// reads as the notch growing — the sweep starts precisely where the physical housing ends.
///
/// Every number comes from `NotchMetrics`, which measures the machine rather than assuming
/// one: the cutout differs between Air and Pro and across sizes, and a shape a few points
/// wider than the housing is exactly the floating pill this exists to avoid.
struct SetupNotchShape: Shape {

	/// The physical cutout, measured. The top of the shape matches it exactly.
	var cutoutWidth: CGFloat
	var cutoutHeight: CGFloat
	/// How far below the cutout the walls take to reach full width. Short and the panel
	/// looks like it has shoulders; long and the widening is lost before anyone sees it.
	var flareDrop: CGFloat = 26
	var bottomRadius: CGFloat = 26

	var animatableData: AnimatablePair<CGFloat, CGFloat> {
		get { AnimatablePair(flareDrop, bottomRadius) }
		set {
			flareDrop = newValue.first
			bottomRadius = newValue.second
		}
	}

	func path(in rect: CGRect) -> Path {
		let centre = rect.midX
		// Never wider than the panel: on a screen with no notch the cutout is zero and the
		// shape degrades to a plain rounded panel rather than to a knot.
		let halfCutout = max(0, min(cutoutWidth, rect.width) / 2)
		let notchBottom = rect.minY + max(0, cutoutHeight)
		let drop = max(0, min(flareDrop, rect.height - cutoutHeight))
		let bottom = max(0, min(bottomRadius, rect.width / 2, rect.height - cutoutHeight - drop))

		var path = Path()

		// Top-left of the cutout, at the screen edge.
		path.move(to: CGPoint(x: centre - halfCutout, y: rect.minY))

		// Straight down the cutout's own wall. Invisible in practice — this is behind the
		// housing — but it has to be here or the sweep below starts from nothing.
		path.addLine(to: CGPoint(x: centre - halfCutout, y: notchBottom))

		// The sweep. Concave, turning the cutout's vertical wall into the panel's, with the
		// control point on the corner they would otherwise have met at.
		path.addQuadCurve(
			to: CGPoint(x: rect.minX, y: notchBottom + drop),
			control: CGPoint(x: rect.minX, y: notchBottom))

		// Down the panel's left wall to the bottom-left corner.
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
		path.addQuadCurve(
			to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
			control: CGPoint(x: rect.minX, y: rect.maxY))

		// Across the bottom.
		path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
		path.addQuadCurve(
			to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
			control: CGPoint(x: rect.maxX, y: rect.maxY))

		// Up the right wall, and the mirrored sweep back into the cutout.
		path.addLine(to: CGPoint(x: rect.maxX, y: notchBottom + drop))
		path.addQuadCurve(
			to: CGPoint(x: centre + halfCutout, y: notchBottom),
			control: CGPoint(x: rect.maxX, y: notchBottom))

		path.addLine(to: CGPoint(x: centre + halfCutout, y: rect.minY))
		path.closeSubpath()

		return path
	}
}
