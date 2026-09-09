import SwiftUI

/// The panel's outline: rounded at the bottom, and **flared outward** at the top.
///
/// The flare is the whole point, and it is what the panel was missing. Its shape was an
/// `UnevenRoundedRectangle` with `topLeadingRadius: 0, topTrailingRadius: 0` — square
/// across the top, and wider than the cutout. A rectangle whose top edge meets the screen
/// edge in a hard corner reads as a box hanging *below* the notch. The notch stays a notch
/// and the panel stays a separate thing stuck underneath it.
///
/// What makes it read as the notch *growing* is a concave curve at each top corner, turning
/// outward into the screen edge, so there is no corner at all where the two meet — the
/// panel's side wall bends into the top edge and keeps going. Apple's own Dynamic Island
/// does this, and it is the difference between "attached" and "adjacent".
///
/// `UnevenRoundedRectangle` cannot express it: its radii only ever round *inward*. So the
/// outline is drawn, and the two halves are drawn differently on purpose:
///
///   - **The bottom** reuses `UnevenRoundedRectangle`'s own path, so the bottom corners
///     stay Apple's continuous curvature rather than becoming circular arcs. That geometry
///     was already right and there is no reason to reimplement it worse.
///   - **The top** flares are quadratic curves, which is exact for this shape: a concave
///     quarter-turn from a vertical wall to a horizontal edge is what a quadratic with the
///     control point at the corner draws.
///
/// The idea, and the observation that the flare is what makes a notch panel look attached,
/// come from reading Glance (MIT, © 2026 Jonathan Zhou) —
/// <https://github.com/jonnyoo/glance>. Its `NotchShape` goes further and lifts the real
/// continuous control points out of a rendered `UnevenRoundedRectangle`; this composes the
/// same primitive instead, which keeps Apple's curvature without the path surgery. See
/// NOTICE.
struct NotchPanelShape: Shape {

	/// How far the top corners flare out into the screen edge. Also how far the body is
	/// inset from the full width, since the flare has to have somewhere to go.
	var topRadius: CGFloat
	/// The ordinary inward rounding at the bottom two corners.
	var bottomRadius: CGFloat

	/// Animatable, so growing and retracting interpolates the outline rather than swapping
	/// between two of them. Without this the panel would pop between shapes whenever the
	/// radius changes with height.
	var animatableData: AnimatablePair<CGFloat, CGFloat> {
		get { AnimatablePair(topRadius, bottomRadius) }
		set {
			topRadius = newValue.first
			bottomRadius = newValue.second
		}
	}

	func path(in rect: CGRect) -> Path {
		// Clamped, because both radii are driven by the panel's height and the panel starts
		// at zero. Unclamped, a height smaller than the radius produces a self-crossing
		// path that renders as a knot for the first frames of the animation.
		let top = max(0, min(topRadius, rect.width / 2))
		let bottom = max(0, min(bottomRadius, max(0, rect.width / 2 - top), rect.height))

		// The body sits between the two flares. Its top corners are square because they are
		// not corners in the finished outline — they are where each flare hands over.
		let body = CGRect(
			x: rect.minX + top, y: rect.minY,
			width: max(0, rect.width - top * 2), height: rect.height)

		// Three filled regions rather than one traced outline.
		//
		// Tracing the whole thing by hand meant redrawing the bottom corners, and the
		// point of using `UnevenRoundedRectangle` is that its continuous curvature is
		// already correct. These abut exactly — the flares' inner edges are the body's
		// walls — so under non-zero winding they fill as one shape with no seam, and the
		// bottom stays Apple's geometry untouched.
		var path = Path()

		path.addPath(
			UnevenRoundedRectangle(
				topLeadingRadius: 0,
				bottomLeadingRadius: bottom,
				bottomTrailingRadius: bottom,
				topTrailingRadius: 0,
				style: .continuous
			).path(in: body))

		guard top > 0 else { return path }

		// Left flare: along the screen edge, down the body's wall, then a concave quarter
		// turn back out to where it started. A quadratic with its control point at the
		// corner is exactly that turn.
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: body.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: body.minX, y: rect.minY + top))
		path.addQuadCurve(
			to: CGPoint(x: rect.minX, y: rect.minY),
			control: CGPoint(x: body.minX, y: rect.minY))
		path.closeSubpath()

		// Right flare, mirrored.
		path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: body.maxX, y: rect.minY + top))
		path.addQuadCurve(
			to: CGPoint(x: rect.maxX, y: rect.minY),
			control: CGPoint(x: body.maxX, y: rect.minY))
		path.closeSubpath()

		return path
	}
}
