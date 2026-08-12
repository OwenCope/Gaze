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
