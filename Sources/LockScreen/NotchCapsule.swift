import Observation
import SwiftUI

/// Live state for the lock screen panel.
///
/// The phase lives in an observable model rather than being passed as a plain value,
/// because the panel is hosted in an `NSHostingView` that outlives any single phase.
/// Replacing the hosting view's `rootView` on each change destroys the SwiftUI view's
/// identity, which resets its `@State` and leaves the transitions with nothing to animate
/// between — the symptom is a glyph that appears, sits still, and vanishes.
@Observable
@MainActor
final class NotchCapsuleModel {
	enum Phase: Equatable {
		/// Screen is locked, nobody in frame. A padlock, no camera activity implied.
		case locked
		case scanning
		case notRecognised
		case success

		/// Compact while it is only showing a padlock, expanded once it is doing something.
		///
		/// A panel that hangs open all the while the Mac is locked is a permanent lump
		/// under the notch; one that sits flush and grows when it has something to say is
		/// a status indicator.
		var isCompact: Bool { self == .locked }
	}

	var phase: Phase = .scanning
	/// Deepen the tint when the wallpaper behind is light, or glass goes pale and the
	/// glyph disappears into it.
	var prefersOpaque = false
	/// Mirrors `Preferences.notchStyle`, captured when the panel is shown.
	var style: Preferences.NotchStyle = .normal
	var transparency: Double = 0.3
	/// Drives the grow-out and retract-back. False collapses the panel to the notch's own
	/// height, where it is hidden behind the cutout.
	var isExpanded = false
}

/// The panel that drops out of the notch while Face ID runs.
///
/// Shaped to read as the notch itself growing downwards: same width as the camera
/// housing, square across the top where it meets the cutout, rounded only along the
/// bottom — the way the Dynamic Island expands.
struct NotchCapsule: View {

	@Bindable var model: NotchCapsuleModel
	var width: CGFloat
	var height: CGFloat
	/// Top strip hidden behind the physical cutout. Content is centred below it.
	var notchInset: CGFloat = 0

	@State private var breathe = false
	@State private var expanded = false

	// Success animation state. Kept as separate values rather than derived from `phase`
	// so each beat can be timed independently.
	@State private var glyphOpacity: Double = 1
	@State private var featureOpacity: Double = 1
	/// -1 sits above the panel, 0 is in place. The reference slides the face down over
	/// its first 27 frames rather than fading it in.
	@State private var dropIn: CGFloat = -1
	/// 0 = Face ID brackets, 1 = closed ring.
	@State private var morph: CGFloat = 0
	@State private var tickProgress: CGFloat = 0
	@State private var tickScale: CGFloat = 0.55

	private var cornerRadius: CGFloat { min(15, height / 2.4) }

	private var shape: UnevenRoundedRectangle {
		UnevenRoundedRectangle(
			topLeadingRadius: 0,
			bottomLeadingRadius: cornerRadius,
			bottomTrailingRadius: cornerRadius,
			topTrailingRadius: 0,
			style: .continuous)
	}

	var body: some View {
		ZStack(alignment: .top) {
			// Grows downward out of the cutout and retracts back into it. Collapsed, the
			// shape is exactly the notch's height, so it is completely hidden behind the
			// physical cutout — nothing appears or disappears, it emerges.
			background
				.frame(height: expanded ? currentHeight : notchInset)

			content
				.frame(width: glyphSide, height: glyphSide)
				// Centred in the solid band — not the whole window (whose top third is
				// behind the cutout) and not the whole visible drop (whose lower part
				// fades to clear, which would dissolve the glyph along with it).
				.padding(.top, glyphTop)
				.opacity(expanded ? 1 : 0)
				.scaleEffect(expanded ? 1 : 0.6)
		}
		.frame(width: width, height: height, alignment: .top)
		.animation(.spring(response: 0.44, dampingFraction: 0.78), value: expanded)
		// The grow from padlock to scanner is the same spring, so the two states read as
		// one object changing rather than two panels swapping.
		.animation(.spring(response: 0.40, dampingFraction: 0.76), value: model.phase.isCompact)
		.modifier(Shaker(active: model.phase == .notRecognised))
		.onAppear {
			breathe = true
			// Driven from the view's own state rather than straight off the model: the
			// controller flips `isExpanded` before the hosting view has mounted, so the
			// change lands with nothing observing it and the panel stays collapsed.
			expanded = true
		}
		// The controller still owns the retract, so mirror it back in.
		.onChange(of: model.isExpanded) { _, wanted in expanded = wanted }
		.onChange(of: model.phase) { _, phase in
			if phase == .success { playSuccess() } else { resetSuccess() }
		}
	}

	/// The panel body.
	///
	/// Three styles, chosen in Settings: solid black, or black at a chosen opacity over a
	/// blurred material. The material is applied here rather than relying on `.glassEffect`
	/// to sample the wallpaper — this window lives in its own SkyLight space, so there is
	/// nothing behind it in the compositor for a material to blur, and unbacked glass falls
	/// back to a pale grey slab on a dark lock screen.
	private var background: some View {
		shape
			.fill(fillStyle)
			.background {
				// Glass needs something behind it to blur. In an isolated SkyLight space
				// there is no backdrop, so the material is applied here rather than relied
				// on to sample the wallpaper.
				if model.style != .normal {
					shape.fill(.ultraThinMaterial)
				}
			}
			// Fades to clear toward the bottom, so the panel has no visible end and reads
			// as the notch extending rather than a rectangle stuck under it.
			.mask {
				LinearGradient(
					stops: [
						.init(color: .black, location: 0),
						.init(color: .black, location: 0.36),
						.init(color: .black.opacity(0.72), location: 0.55),
						.init(color: .black.opacity(0.38), location: 0.76),
						.init(color: .black.opacity(0.12), location: 0.92),
						.init(color: .clear, location: 1),
					],
					startPoint: .top,
					endPoint: .bottom)
			}
	}

	/// Opaque black, or black at a chosen transparency over a blurred material.
	private var fillStyle: Color {
		switch model.style {
		case .normal:
			return .black
		case .semiLiquidGlass:
			// The slider is "how transparent", so it subtracts from opacity.
			return .black.opacity(1 - model.transparency)
		case .liquidGlass:
			return .black.opacity(model.prefersOpaque ? 0.42 : 0.24)
		}
	}


	/// Shorter while it is only a padlock, full height once it is scanning.
	private var currentHeight: CGFloat {
		model.phase.isCompact ? notchInset + Self.compactDrop : height
	}

	/// Just enough to seat the padlock below the cutout.
	private static let compactDrop: CGFloat = 26

	/// The part of the panel that actually shows below the cutout.
	private var visibleHeight: CGFloat { currentHeight - notchInset }

	/// Sized against the visible drop. The mask does not touch the glyph, so it only has
	/// to fit — it does not have to stay inside the opaque part.
	private var glyphSide: CGFloat {
		model.phase.isCompact ? 15 : min(width, visibleHeight) * 0.52
	}

	/// Sits high in the drop, where the panel is still dark enough to carry it.
	private var glyphTop: CGFloat { notchInset + visibleHeight * 0.30 - glyphSide / 2 }

	/// Apple's own symbols, animated by Apple's own effects.
	///
	/// Hand-drawing the Face ID mark and morphing it to a tick was the wrong instinct:
	/// every version was a guess at the real animation and read as an approximation.
	/// `faceid` and `checkmark.circle.fill` are both system symbols, and
	/// `.replace.magic` is the transition Apple uses to morph between them — so this is
	/// the genuine article rather than an imitation of it.
	/// Glyph while scanning; a spinning ring that resolves into a tick on success.
	///
	/// The success beat is hand-built rather than an SF Symbol transition, because a
	/// symbol replace *swaps* two icons and this needs one object to *become* another.
	/// The glyph collapses, a ring arrives edge-on and rotates flat, then the tick draws
	/// inside it. Everything is stroked and green — nothing is ever filled, so the panel
	/// shows through the middle.
	/// The mark: brackets that converge into a ring, then a tick inside it.
	///
	/// One continuous path throughout. `FaceBracketMorph` grows its own corner radius and
	/// segment length, so the Face ID brackets *become* the circle rather than one fading
	/// out while the other fades in. That convergence is the whole animation.
	private var content: some View {
		let lineWidth = max(2, glyphSide * 0.075)

		return ZStack {
			// Brackets → ring.
			FaceBracketMorph(progress: morph)
				.stroke(
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
				.foregroundStyle(markStyle)

			// The face's features, which shrink into the middle as the brackets close.
			FaceFeatures()
				.stroke(
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
				.foregroundStyle(markStyle)
				.opacity(featureOpacity)
				.scaleEffect(0.4 + 0.6 * featureOpacity)

			// The tick pops rather than drawing on: the reference has a small tick at
			// frame 72 and a larger one at 94, which reads as a scale-up, not a trim.
			TickShape()
				.stroke(
					Self.faceGreen,
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
				.padding(glyphSide * 0.3)
				.opacity(tickProgress > 0 ? 1 : 0)
				.scaleEffect(tickScale)
		}
		.frame(width: glyphSide, height: glyphSide)
		.opacity(glyphOpacity)
		.offset(y: dropIn * glyphSide * 0.9)
		.symbolEffect(.breathe, options: .repeating, isActive: model.phase == .scanning)
		.onAppear {
			withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { dropIn = 0 }
		}
	}

	/// Frosted white while scanning, green once it has recognised you.
	private var markStyle: AnyShapeStyle {
		switch model.phase {
		case .notRecognised:
			return AnyShapeStyle(Color.red.opacity(0.9))
		case .success:
			return AnyShapeStyle(Self.faceGreen)
		case .locked, .scanning:
			return AnyShapeStyle(
				LinearGradient(
					colors: [.white.opacity(0.95), .white.opacity(0.6)],
					startPoint: .top, endPoint: .bottom))
		}
	}

	private static let faceGreen = Color(red: 0.20, green: 0.86, blue: 0.38)

	/// Runs the four beats: glyph collapses, ring spins in, settles, tick draws.
	private func playSuccess() {
		// The features go first, so the brackets are closing on an empty middle.
		withAnimation(.easeIn(duration: 0.22)) { featureOpacity = 0 }
		// Then the brackets converge into the ring.
		withAnimation(.spring(response: 0.6, dampingFraction: 0.74).delay(0.12)) { morph = 1 }
		// Small tick, then it springs up to full size.
		withAnimation(.linear(duration: 0.01).delay(0.55)) { tickProgress = 1 }
		withAnimation(.spring(response: 0.34, dampingFraction: 0.6).delay(0.56)) {
			tickScale = 1
		}
	}

	private func resetSuccess() {
		glyphOpacity = 1
		featureOpacity = 1
		morph = 0
		tickProgress = 0
		tickScale = 0.55
		dropIn = -1
	}

	/// The filled variant, rendered hierarchically.
	///
	/// The outlined `checkmark.circle` was thin and, at partial opacity, read as faint
	/// rather than as confirmation. Filled plus hierarchical keeps the translucency — the
	/// disc sits back while the tick stays solid — while giving the mark enough weight to
	/// land.
	private var symbolName: String {
		switch model.phase {
		case .locked: return "lock.fill"
		case .success: return "checkmark.circle.fill"
		case .scanning, .notRecognised: return "faceid"
		}
	}

	/// Green on success, white while scanning.
	///
	/// White for both was an attempt to keep the morph purely a change of shape, but at
	/// hierarchical opacity the tick read as disabled rather than as confirmation. Colour
	/// is what makes it land — a shape change alone is too quiet for the one moment that
	/// needs to be unambiguous.
	private var symbolTint: Color {
		switch model.phase {
		case .success: return Color(red: 0.20, green: 0.86, blue: 0.38)
		case .notRecognised: return .red
		case .locked, .scanning: return .white
		}
	}
}

/// The lateral knock a rejected password field gives, for the same reason: it reads as
/// "no" without needing to be read.
private struct Shaker: ViewModifier {
	let active: Bool
	@State private var offset: CGFloat = 0

	func body(content: Content) -> some View {
		content
			.offset(x: offset)
			.onChange(of: active) { _, isActive in
				guard isActive else { return }
				withAnimation(.linear(duration: 0.055).repeatCount(5, autoreverses: true)) {
					offset = 6
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { offset = 0 }
			}
	}
}


/// The Face ID brackets morphing into a ring.
///
/// The trick is that the brackets already *are* corner segments of a rounded square. Grow
/// the corner radius until it reaches half the side, and extend each segment until it
/// meets its neighbours, and the same path becomes a circle. No crossfade, no second
/// shape — one set of strokes that converges.
///
/// `progress` 0 draws the brackets, 1 draws a closed ring.
struct FaceBracketMorph: Shape {
	var progress: CGFloat

	var animatableData: CGFloat {
		get { progress }
		set { progress = newValue }
	}

	func path(in rect: CGRect) -> Path {
		let side = min(rect.width, rect.height)
		let x0 = rect.midX - side / 2
		let y0 = rect.midY - side / 2

		// At p = 1 the radius is half the side, which is exactly a circle.
		let r = side * (0.22 + 0.28 * progress)
		let edge = max(0, side - 2 * r)
		// How much of each straight edge is drawn, from a stub to the whole thing.
		let arm = edge / 2 * (0.36 + 0.64 * progress)

		var path = Path()

		// Each corner: run in along one edge, round the corner, run out along the next.
		let corners: [(CGPoint, CGFloat, CGFloat, CGPoint, CGPoint)] = [
			// centre, startAngle, endAngle, armStart, armEnd
			(CGPoint(x: x0 + r, y: y0 + r), 180, 270,
			 CGPoint(x: x0, y: y0 + r + arm), CGPoint(x: x0 + r + arm, y: y0)),
			(CGPoint(x: x0 + side - r, y: y0 + r), 270, 360,
			 CGPoint(x: x0 + side - r - arm, y: y0), CGPoint(x: x0 + side, y: y0 + r + arm)),
			(CGPoint(x: x0 + side - r, y: y0 + side - r), 0, 90,
			 CGPoint(x: x0 + side, y: y0 + side - r - arm), CGPoint(x: x0 + side - r - arm, y: y0 + side)),
			(CGPoint(x: x0 + r, y: y0 + side - r), 90, 180,
			 CGPoint(x: x0 + r + arm, y: y0 + side), CGPoint(x: x0, y: y0 + side - r - arm)),
		]

		for (centre, start, end, armStart, armEnd) in corners {
			path.move(to: armStart)
			path.addArc(
				center: centre, radius: r,
				startAngle: .degrees(start), endAngle: .degrees(end),
				clockwise: false)
			path.addLine(to: armEnd)
		}

		return path
	}
}

/// The eyes, nose and mouth, which shrink away as the brackets close.
struct FaceFeatures: Shape {
	func path(in rect: CGRect) -> Path {
		let side = min(rect.width, rect.height)
		let x0 = rect.midX - side / 2
		let y0 = rect.midY - side / 2
		func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
			CGPoint(x: x0 + side * fx, y: y0 + side * fy)
		}

		var path = Path()
		// Eyes.
		path.move(to: p(0.33, 0.34)); path.addLine(to: p(0.33, 0.46))
		path.move(to: p(0.67, 0.34)); path.addLine(to: p(0.67, 0.46))
		// Nose.
		path.move(to: p(0.50, 0.36)); path.addLine(to: p(0.50, 0.56))
		path.addQuadCurve(to: p(0.59, 0.60), control: p(0.50, 0.60))
		// Mouth.
		path.move(to: p(0.34, 0.68))
		path.addQuadCurve(to: p(0.66, 0.68), control: p(0.50, 0.79))
		return path
	}
}


/// The tick drawn inside the closed ring.
struct TickShape: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
		path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08))
		return path
	}
}
