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

/// The one statement of how the semi-glass tint responds to its slider.
///
/// The lock screen panel and the settings preview both draw this; when the formula lived in
/// each separately they disagreed, and a preview that disagrees with the thing it previews
/// is worse than none.
enum NotchGlass {
	/// 0 = clear, 1 = opaque. Runs nearly the whole visible range so the slider does
	/// something at every position; clamped so a light-wallpaper boost can't flatten its
	/// top end into a single value.
	static func semiTint(transparency: Double, boost: Double) -> Double {
		min(0.96, 0.92 - 0.80 * transparency + boost)
	}

	static func liquidTint(boost: Double) -> Double {
		min(0.6, 0.18 + boost)
	}
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
	/// The physical cutout's width. The window is wider than it, and the difference is the
	/// screen either side of the camera housing — where a padlock can sit at menu bar height
	/// without dropping anything out of the notch at all.
	var cutoutWidth: CGFloat = 0

	@State private var breathe = false
	@State private var expanded = false

	/// Proportional to what is actually showing, not to the window.
	///
	/// This was a constant 15 derived from the window height, so a panel retracting through
	/// its last twenty points kept a 15pt radius on a shape only a few points tall — which
	/// is what made the retract go square and hard right before it vanished. Tying the
	/// radius to the visible drop lets it round off to nothing as the panel closes.
	/// Floored, not just derived.
	///
	/// A radius proportional to the drop goes to nothing as the panel retracts, and the last
	/// thing you see before it disappears is a hard-cornered rectangle. The floor keeps the
	/// resting lip rounded, which is the whole reason it hangs below the cutout at all.
	private var cornerRadius: CGFloat { min(15, max(9, max(0, visibleHeight) / 1.9)) }

	private var shape: UnevenRoundedRectangle {
		UnevenRoundedRectangle(
			topLeadingRadius: 0,
			bottomLeadingRadius: cornerRadius,
			bottomTrailingRadius: cornerRadius,
			topTrailingRadius: 0,
			style: .continuous)
	}

	/// The visible screen either side of the cutout, in whichever shape is currently drawn.
	private var earWidth: CGFloat { max(0, (backgroundWidth - cutoutWidth) / 2) }

	var body: some View {
		ZStack(alignment: .top) {
			// Grows downward out of the cutout and retracts back into it. Collapsed, the
			// shape is exactly the notch's height, so it is completely hidden behind the
			// physical cutout — nothing appears or disappears, it emerges.
			background
				.frame(
					width: backgroundWidth,
					height: expanded ? currentHeight : notchInset)

			// Locked: a padlock beside the cutout, at menu bar height.
			//
			// It used to hang below the notch on a stub of panel, which is the one place it
			// could not go — the drop is the *active* state, so a resting padlock sitting in
			// it said the panel was doing something when it was doing nothing. Notch apps
			// put a resting indicator in the screen either side of the housing instead, and
			// that is space this window already covers.
			if model.phase.isCompact {
				lockChip
					// Positioned against the *resting* bar, not the window — the window is
					// wider, so aligning to it put the padlock outside the black.
					.frame(width: backgroundWidth, alignment: .leading)
					.opacity(expanded ? 1 : 0)
					.transition(.opacity.combined(with: .scale(scale: 0.7)))
			} else {
				content
					.frame(width: glyphSide, height: glyphSide)
					// Centred in the solid band — not the whole window (whose top third is
					// behind the cutout) and not the whole visible drop (whose lower part
					// fades to clear, which would dissolve the glyph along with it).
					.padding(.top, glyphTop)
					.opacity(expanded ? 1 : 0)
					.scaleEffect(expanded ? 1 : 0.72, anchor: .top)
					// Out before the panel is, so the panel never closes over a glyph that
					// is still solid — that overlap is what made the retract look like two
					// separate events instead of one.
					.animation(.easeOut(duration: expanded ? 0.28 : 0.16), value: expanded)
			}
		}
		.frame(width: width, height: height, alignment: .top)
		// Softer and slower than the grow. A retract that uses the same snappy spring as the
		// expand reads as a snap-shut; the panel should look absorbed, not swallowed.
		.animation(
			expanded
				? .spring(response: 0.44, dampingFraction: 0.78)
				: .spring(response: 0.58, dampingFraction: 0.92),
			value: expanded)
		// The grow from padlock to scanner is the same spring, so the two states read as
		// one object changing rather than two panels swapping.
		.animation(.spring(response: 0.46, dampingFraction: 0.82), value: model.phase.isCompact)
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
		Group {
			switch model.style {
			case .normal:
				// Genuinely opaque, and genuinely *un-faded*.
				//
				// This used to be masked to clear at the bottom like the other two, which
				// meant the one style whose whole promise is "solid black, indistinguishable
				// from the cutout" was neither solid nor black below its first third. It
				// looked washed next to the glass styles it was supposed to contrast with.
				shape.fill(.black)

			case .semiLiquidGlass:
				// Dark, with the wallpaper's light coming through a blur. The slider moves
				// how much — across a range you can actually see.
				//
				// The tint ran 0.55…0.90, a 35% band at the dark end, so dragging the
				// slider from one stop to the other changed almost nothing and the control
				// read as broken. It runs nearly the whole way now.
				shape
					.fill(.black.opacity(glassTint))
					.background { shape.fill(.ultraThinMaterial) }
					.mask { fade }

			case .liquidGlass:
				// The real macOS 26 material — it refracts and picks up what is behind
				// it rather than just being a dark tint over a blur.
				Color.clear
					.glassEffect(
						.regular.tint(.black.opacity(NotchGlass.liquidTint(boost: lightWallpaperBoost))),
						in: shape)
					.mask { fade }
			}
		}
	}

	/// Fades to clear toward the bottom, so a glass panel has no visible end and reads as
	/// the notch extending rather than a rectangle stuck under it.
	///
	/// Only while it is extending. The resting bar sits inside the menu bar band, where a
	/// fade has nothing to resolve into — it just softens the one edge that should be as
	/// crisp as the housing it continues, and every other notch app's bar is crisp there.
	private var fade: some View {
		LinearGradient(
			stops: model.phase.isCompact
				? [
					.init(color: .black, location: 0),
					.init(color: .black, location: 1),
				]
				: [
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

	private var glassTint: Double {
		NotchGlass.semiTint(transparency: model.transparency, boost: lightWallpaperBoost)
	}

	/// Extra black mixed in when the wallpaper behind the panel is bright.
	///
	/// `prefersOpaque` was computed on every show — `WallpaperBrightness.isLight(on:)`, set
	/// on the model, and then read by nothing at all. The whole point of measuring it is
	/// this: over a pale wallpaper both glass styles wash out and a white glyph on them has
	/// almost no contrast left. Only the two translucent styles use it; `.normal` is already
	/// solid black and has nothing to gain.
	private var lightWallpaperBoost: Double { model.prefersOpaque ? 0.22 : 0 }

	/// The padlock, in the screen beside the cutout.
	///
	/// A bare glyph, with nothing behind it.
	///
	/// It used to sit in a circle — `black 0.55` over `.ultraThinMaterial`, ringed in white.
	/// Every one of those layers was working against it: a translucent dark fill laid over a
	/// band that is *already* black comes out **lighter** than its surroundings, so the
	/// container read as a grey disc stuck onto the notch, and the ring drew a hard outline
	/// around the blob. It looked applied, not built in.
	///
	/// The band it stands on is the panel's own black, so there is nothing to separate the
	/// glyph from — it can simply be drawn into the bar. That is the whole difference
	/// between a status indicator and a sticker.
	private var lockChip: some View {
		Image(systemName: "lock.fill")
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(.white)
			// No chip behind it.
			//
			// It briefly had one, added when the resting panel was hidden behind the housing
			// and the padlock was left standing on bare wallpaper with nothing to read
			// against. Now that the panel is back to full width, the glyph stands on the
			// panel's own black again — and a translucent dark chip laid over black comes out
			// *lighter* than what surrounds it, which is what made it look like a sticker
			// pasted next to the notch rather than part of it.
			//
			// Optically centred in the ear: the visible band is the notch inset, and the
			// glyph belongs in the middle of that, clear of the lip below it.
			.frame(width: earWidth, height: notchInset)
	}

	/// Flush with the cutout while resting, the full drop once it is scanning.
	///
	/// The 11pt lip this had was almost the entire overhang: the notch is 32pt tall and a
	/// notch app's bar sits flush with it, so anything hanging below shows as a second shape
	/// behind the first. Nothing hangs below now — the resting bar occupies the menu bar band
	/// and no more, and its corners round *within* that band, which is what the radius floor
	/// is for.
	private var currentHeight: CGFloat {
		model.phase.isCompact ? notchInset : height
	}

	/// Narrower while resting, full width once it drops.
	///
	/// Deliberately smaller than the bar a notch app draws over the same area. Dynamic Lake
	/// Pro's is about 276pt across and flush with the menu bar; ours resting inside that
	/// disappears under it entirely, instead of peeking out a few points wider and lower and
	/// reading as a second notch behind the first.
	///
	/// It still has to look right on its own, so this is a smaller version of the same shape
	/// rather than nothing at all — rounded, ears either side of the housing, just tighter.
	private var backgroundWidth: CGFloat {
		model.phase.isCompact ? min(width, cutoutWidth + 2 * Self.restingEar) : width
	}

	/// Screen either side of the housing that the resting bar covers.
	private static let restingEar: CGFloat = 36

	/// The part of the panel that actually shows below the cutout.
	private var visibleHeight: CGFloat { currentHeight - notchInset }

	/// Sized against the visible drop. The mask does not touch the glyph, so it only has
	/// to fit — it does not have to stay inside the opaque part.
	private var glyphSide: CGFloat {
		min(width, visibleHeight) * 0.52
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
			// Monochrome throughout now. Hierarchical existed for the tick's disc, where the
			// softened ring read as frosted; an open padlock has no disc to soften, and
			// hierarchical only bleeds the shackle away from the body.
			.symbolRenderingMode(.monochrome)
			.foregroundStyle(symbolTint)
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
			// Breathing while it looks — the system effect, not an opacity loop.
			.symbolEffect(.breathe, options: .repeating, isActive: model.phase == .scanning)
			.symbolEffect(.bounce, value: model.phase == .notRecognised)
			// The shackle springing open. `.bounce` on the padlock is the one moment in the
			// sequence that should feel mechanical rather than smooth — a lock is a physical
			// thing, and it lets go all at once.
			.symbolEffect(.bounce.up, options: .speed(0.9), value: model.phase == .success)
			.animation(.spring(response: 0.36, dampingFraction: 0.72), value: model.phase)
	}

	/// The filled variant, rendered hierarchically.
	///
	/// The outlined `checkmark.circle` was thin and, at partial opacity, read as faint
	/// rather than as confirmation. Filled plus hierarchical keeps the translucency — the
	/// disc sits back while the tick stays solid — while giving the mark enough weight to
	/// land.
	/// The padlock it started as, opening.
	///
	/// This was a green tick. A tick means "that worked", which is true of any operation; an
	/// opening padlock means *this* worked — and it is the same object the panel showed while
	/// resting, so the sequence closes where it began. `.replace.magic` morphs the shackle
	/// rather than swapping one glyph for another.
	private var symbolName: String {
		switch model.phase {
		case .locked: return "lock.fill"
		case .success: return "lock.open.fill"
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
		case .success: return Theme.faceID
		case .notRecognised: return Theme.danger
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
