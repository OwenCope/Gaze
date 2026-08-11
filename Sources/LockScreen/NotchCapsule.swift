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
		case scanning
		case notRecognised
		case success
	}

	var phase: Phase = .scanning
	/// Deepen the tint when the wallpaper behind is light, or glass goes pale and the
	/// glyph disappears into it.
	var prefersOpaque = false
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
				.frame(height: expanded ? height : notchInset)

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
	}

	/// Semi-glass: a dark tint over a blurred material, no stroke.
	///
	/// The earlier translucent attempts looked bordered because the panel started *below*
	/// the cutout and the join showed. With the window now spanning the notch that seam
	/// is gone, so glass works — the only visible edges are the rounded bottom corners,
	/// which are meant to be seen.
	///
	/// Tint rather than pure material: unmodified glass over a busy wallpaper leaves the
	/// glyph unreadable, and over a light one washes out completely.
	/// macOS 27 Spotlight's material: heavily blurred, deeply tinted, but still passing
	/// colour from behind rather than flattening to a solid.
	///
	/// The tint has to be strong — a light one leaves the panel washed out over a bright
	/// backdrop — while the blur is what keeps it reading as glass instead of as a dark
	/// rectangle. Both together, not either alone.
	/// Dark glass: `.glassEffect` alone, tinted black.
	///
	/// It previously sat on a `.ultraThinMaterial` backing, which is a *light* material —
	/// it brightens whatever is behind it. Under a dark tint the light layer won, and the
	/// panel came out as a pale grey slab on a dark wallpaper. Every attempt to fix that
	/// by deepening the tint was fighting a layer that should not have been there.
	///
	/// `.glassEffect` already provides the blur. Nothing goes behind it.
	private var background: some View {
		shape
			.fill(
				// An explicit dark fill, not a material.
				//
				// Every glass and material attempt rendered pale grey on a dark lock
				// screen, and the reason is structural: this window lives in its own
				// SkyLight space, so there is nothing behind it in the compositor for a
				// material to blur. With no backdrop to sample, `.glassEffect` falls back
				// to its light appearance — the tint was never the problem, and no amount
				// of darkening it could have worked.
				//
				// Darkest where it leaves the cutout, lightening as it descends, so it
				// looks like the notch's black bleeding downward and thinning out rather
				// than a shape with a colour of its own.
				// Pure opaque black at the top so it is indistinguishable from the cutout
				// it grows out of, lightening as it descends.
				LinearGradient(
					stops: [
						.init(color: .black, location: 0),
						.init(color: .black, location: 0.45),
						.init(color: Color(white: 0.16).opacity(0.85), location: 1),
					],
					startPoint: .top,
					endPoint: .bottom)
			)
			// Fades to clear toward the bottom.
			//
			// This is what stops it reading as a rectangle stuck under the notch. A
			// uniform panel ends in a hard boundary wherever it stops; dissolving the
			// lower edge means it has no visible end, so it belongs to the cutout it
			// grew out of. Solid across the top two-thirds so the glyph stays legible.
			.mask {
				// Stops are fractions of the *whole* window, and the top third of that
				// is hidden behind the cutout — so a fade starting at 0.62 began almost
				// immediately below the notch and swallowed most of the visible panel.
				// It only gets the last stretch.
				// Opacity thins steadily through the lower half rather than holding solid
				// and then dropping off — a late hard fade reads as a cut edge, a long
				// one reads as it dissolving.
				// Fully opaque only across the strip hidden behind the cutout, then thinning
				// continuously all the way down. Holding solid into the visible drop made
				// it read as a black slab with a fade tacked on the end; the dissolve has
				// to be most of the panel, not its last few points.
				//
				// The glyph is a separate layer and is not masked, so it stays legible
				// however far this is pushed.
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

	/// Where the bottom fade begins, as a fraction of the whole window height.

	/// The part of the panel that actually shows below the cutout.
	private var visibleHeight: CGFloat { height - notchInset }

	/// Sized against the visible drop. The mask does not touch the glyph, so it only has
	/// to fit — it does not have to stay inside the opaque part.
	private var glyphSide: CGFloat { min(width, visibleHeight) * 0.52 }

	/// Sits high in the drop, where the panel is still dark enough to carry it.
	private var glyphTop: CGFloat { notchInset + visibleHeight * 0.30 - glyphSide / 2 }

	/// Apple's own symbols, animated by Apple's own effects.
	///
	/// Hand-drawing the Face ID mark and morphing it to a tick was the wrong instinct:
	/// every version was a guess at the real animation and read as an approximation.
	/// `faceid` and `checkmark.circle.fill` are both system symbols, and
	/// `.replace.magic` is the transition Apple uses to morph between them — so this is
	/// the genuine article rather than an imitation of it.
	private var content: some View {
		Image(systemName: symbolName)
			.font(.system(size: glyphSide, weight: model.phase == .success ? .semibold : .regular))
			// Hierarchical only for the tick, where the softened circle is what makes it
			// read as frosted. Applied to the Face ID mark it just dims the whole glyph,
			// which left it washed out against the glass.
			.symbolRenderingMode(model.phase == .success ? .hierarchical : .monochrome)
			.foregroundStyle(symbolTint)
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
			// Breathing while it looks — the system effect, not an opacity loop.
			.symbolEffect(.breathe, options: .repeating, isActive: model.phase == .scanning)
			.symbolEffect(.bounce, value: model.phase == .notRecognised)
			.animation(.spring(response: 0.36, dampingFraction: 0.72), value: model.phase)
	}

	/// The filled variant, rendered hierarchically.
	///
	/// The outlined `checkmark.circle` was thin and, at partial opacity, read as faint
	/// rather than as confirmation. Filled plus hierarchical keeps the translucency — the
	/// disc sits back while the tick stays solid — while giving the mark enough weight to
	/// land.
	private var symbolName: String {
		model.phase == .success ? "checkmark.circle.fill" : "faceid"
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
		case .scanning: return .white
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
