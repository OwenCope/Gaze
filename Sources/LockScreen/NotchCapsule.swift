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
		/// Recognised, and the password has gone in. The tick.
		case success
		/// The Mac is actually open. The padlock lets go.
		///
		/// Separate from `success` because they are separate events, and the gap between them
		/// is real: the tick is this app saying "that was you, here is your password", and the
		/// padlock opening is the Mac agreeing. Collapsing the two meant the padlock opened
		/// while the login window was still deciding — announcing an outcome we had not been
		/// told yet.
		case unlocked

		/// Compact whenever the padlock is the thing being shown.
		///
		/// A panel that hangs open all the while the Mac is locked is a permanent lump
		/// under the notch; one that sits flush and grows when it has something to say is
		/// a status indicator.
		///
		/// Success keeps the panel open to carry the tick. Unlocked is back to resting: the
		/// panel is already on its way home and the padlock is the only thing left to say.
		var isCompact: Bool { self == .locked || self == .unlocked }

		/// The padlock is drawn in every phase.
		///
		/// It used to disappear while scanning and come back for the unlock, which made it a
		/// thing that flickered rather than a state you can read: the padlock *is* the answer
		/// to "is this Mac locked", and that question has an answer the whole time. It stays
		/// put and changes at the one moment its answer changes.
		var showsLockChip: Bool { true }
	}

	var phase: Phase = .scanning
	/// Deepen the tint when the wallpaper behind is light, or glass goes pale and the
	/// glyph disappears into it.
	var prefersOpaque = false
	/// Mirrors `Preferences.notchStyle`, captured when the panel is shown.
	var style: Preferences.NotchStyle = .normal
	/// Mirrors `Preferences.panelShape`, captured when the panel is shown.
	var shape: Preferences.PanelShape = .attached
	/// Mirrors `Preferences.glyphPlacement`.
	var glyphPlacement: Preferences.GlyphPlacement = .centred
	var transparency: Double = 0.3
	/// Drives the grow-out and retract-back. False collapses the panel to the notch's own
	/// height, where it is hidden behind the cutout.
	var isExpanded = false
}

/// The island's measurements, in one place.
///
/// Shared with the controller because the window has to be built big enough to hold what the
/// view will draw, and the two disagreeing is how the shadow ended up clipped against the
/// window's edge.
enum IslandMetrics {
	/// Between the housing and the island, so it reads as a separate object rather than as
	/// the panel with its corners filed off.
	static let gap: CGFloat = 8

	/// Empty space below the island for its shadow to fall into.
	static let shadowRoom: CGFloat = 24

	/// The window's drop for an island of a given cutout width.
	static func dropHeight(cutoutWidth: CGFloat) -> CGFloat {
		gap + cutoutWidth + shadowRoom
	}
}

/// The panel's timings, in one place.
///
/// They have to be shared, because the controller tears the window down on a timer and the
/// view animates on a curve — and when those two numbers lived apart they disagreed. The
/// teardown fired at 0.5s against a spring whose *response* alone was 0.58, so the last third
/// of every retract was cut off and the panel appeared to snap out of the notch.
enum NotchAnimation {

	/// Growing out. Springy, because emerging should feel like it has some life in it.
	static let expand = Animation.spring(response: 0.44, dampingFraction: 0.78)

	/// Going home. `.smooth` rather than a spring: no overshoot, and a duration that means
	/// what it says, so the controller can wait exactly long enough.
	static let retractDuration: TimeInterval = 0.55
	static var retract: Animation { .smooth(duration: retractDuration) }

	/// Between phases — the drop opening and closing as the state changes.
	static let phaseDuration: TimeInterval = 0.5
	static var phase: Animation { .smooth(duration: phaseDuration) }

	/// How long the controller must leave the window alive after asking it to retract.
	/// The margin is for the frame the animation finishes on.
	static var teardownDelay: TimeInterval { max(retractDuration, phaseDuration) + 0.12 }
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

	// MARK: - Island

	/// Whether this panel is the detached island rather than the attached drop.
	///
	/// Compact phases stay attached whatever the setting: the resting padlock lives in the
	/// menu bar band, and an island cannot be at rest — it is the thing that pops out.
	private var isIsland: Bool { model.shape == .island && !model.phase.isCompact }

	private static var islandGap: CGFloat { IslandMetrics.gap }

	/// A square with one radius on all four corners, the way Apple Pay's card drops from the
	/// Dynamic Island.
	///
	/// It was a wide rectangle, which reads as a panel that happens to be detached rather
	/// than as an object the notch handed you. Equal sides and equal corners is what makes it
	/// a *thing*.
	private var islandShape: RoundedRectangle {
		RoundedRectangle(cornerRadius: islandSide * 0.28, style: .continuous)
	}

	/// One dimension, used for both.
	/// As wide as the housing it comes out of.
	///
	/// It was a fraction of the window, and the window is deliberately wider than the cutout
	/// — so the island came out narrower than the notch and read as unrelated to it. Matching
	/// the cutout is what makes it look like the thing the notch handed down.
	private var islandSide: CGFloat {
		let available = height - notchInset - Self.islandGap - Self.islandShadowRoom
		return max(0, min(cutoutWidth > 0 ? cutoutWidth : width * 0.52, available))
	}

	private static var islandShadowRoom: CGFloat { IslandMetrics.shadowRoom }

	private var islandHeight: CGFloat { islandSide }
	private var islandWidth: CGFloat { islandSide }

	/// How far the island travels on its way out of the housing.
	///
	/// Collapsed, it sits *inside* the notch — up behind the cutout and scaled down to
	/// almost nothing — so growing it is the notch handing something down rather than a
	/// panel appearing under it, and retracting is the notch taking it back.
	private var islandHiddenOffset: CGFloat { -(Self.islandGap + islandSide / 2) }

	/// Nebulark's gradient: black at the top running into green at the bottom.
	///
	/// Green only ever appears while the island is doing something — it has no resting
	/// state — so this keeps the rule the rest of the app follows, that green means Face ID
	/// and nothing else, while taking the look he built.
	/// Two gradients, not one, because they were two jobs sharing a stop list.
	///
	/// Turning the green down also turned the *black* down — the stops ran from black at the
	/// top to green at the bottom, so the bottom of the panel had nothing dark left in it and
	/// the glass simply showed the wallpaper through. Over a bright desktop the island came
	/// out pale blue.
	///
	/// The dark keeps the panel legible from top to bottom. The green is a separate wash on
	/// top of it, so it can be dialled to a hint without taking the ground with it.
	private var islandTint: LinearGradient {
		LinearGradient(
			stops: [
				.init(color: .black.opacity(0.94 + lightWallpaperBoost), location: 0),
				.init(color: .black.opacity(0.90 + lightWallpaperBoost), location: 0.45),
				.init(color: .black.opacity(0.84 + lightWallpaperBoost), location: 1),
			],
			startPoint: .top,
			endPoint: .bottom)
	}

	/// A hint, at the bottom, and nowhere else.
	private var islandGreen: LinearGradient {
		LinearGradient(
			stops: [
				.init(color: .clear, location: 0.42),
				.init(color: Theme.faceID.opacity(0.05), location: 0.72),
				.init(color: Theme.faceID.opacity(0.15), location: 1),
			],
			startPoint: .top,
			endPoint: .bottom)
	}

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
			// The bar is always drawn, in every mode.
			//
			// Island mode used to draw the island *instead* of it, which left the padlock
			// standing on bare menu bar with nothing behind it — the chip's ground is the
			// bar, and taking the bar away took the ground with it. The bar is the notch;
			// the island is a thing the notch hands down. Both, always.
			background
				.frame(
					width: isIsland ? compactBarWidth : backgroundWidth,
					height: expanded ? (isIsland ? notchInset : currentHeight) : notchInset)

			if isIsland {
				islandBody
					.frame(width: islandWidth, height: islandHeight)
					.padding(.top, notchInset + Self.islandGap)
					// Travels, rather than growing in place. Collapsed it is up inside the
					// cutout at almost no size; expanded it has come down to where it sits.
					// Same two values in reverse on the way back, so it leaves the way it
					// arrived instead of simply disappearing.
					.offset(y: expanded ? 0 : islandHiddenOffset)
					.scaleEffect(expanded ? 1 : 0.24, anchor: .top)
					.opacity(expanded ? 1 : 0)
			}

			// Locked: a padlock beside the cutout, at menu bar height.
			//
			// It used to hang below the notch on a stub of panel, which is the one place it
			// could not go — the drop is the *active* state, so a resting padlock sitting in
			// it said the panel was doing something when it was doing nothing. Notch apps
			// put a resting indicator in the screen either side of the housing instead, and
			// that is space this window already covers.
			// The padlock stays for the unlock, so success shows both: the tick in the drop
			// and the same padlock opening where it has sat all along.
			if model.phase.showsLockChip {
				lockChip
					// Positioned against the *resting* bar, not the window — the window is
					// wider, so aligning to it put the padlock outside the black.
					.frame(width: backgroundWidth, alignment: .leading)
					.opacity(expanded ? 1 : 0)
					.transition(.opacity.combined(with: .scale(scale: 0.7)))
			}

			if !model.phase.isCompact {
				content
					.frame(width: glyphSide, height: glyphSide)
					// Ruken's placement: tucked into the trailing corner instead of filling
					// the middle, so the panel reads as a status strip with a mark on it
					// rather than as a mark with a panel around it.
					.frame(
						maxWidth: isCorner ? .infinity : nil,
						alignment: isCorner ? .trailing : .center)
					.padding(.trailing, isCorner ? cornerGlyphInset : 0)
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
		.animation(expanded ? NotchAnimation.expand : NotchAnimation.retract, value: expanded)
		// The grow from padlock to scanner is the same spring, so the two states read as
		// one object changing rather than two panels swapping.
		.animation(NotchAnimation.phase, value: model.phase.isCompact)
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

	/// The detached island: Nebulark's gradient, a tint over it, and a lit rim.
	///
	/// No `.glassEffect`, and the reason is written six lines below in `background` — where
	/// it was already learned once. This window lives in its own SkyLight space, so there is
	/// nothing behind it in the compositor for a material to sample. Unbacked glass does not
	/// fail invisibly; it falls back to a pale grey slab, and a pale grey slab under a dark
	/// island is exactly the faint rectangle that gives away that the floating object is a
	/// window. It looked right on the desktop, where there *is* something behind it, which is
	/// why the desktop preview never showed the problem.
	///
	/// The gradient does the work instead. That is also what the attached styles do, for the
	/// same reason, and now the whole panel is honest about the space it lives in.
	private var islandBody: some View {
		islandShape
			.fill(
				LinearGradient(
					colors: [
						.black,
						.black,
						Color(red: 0, green: 0.10, blue: 0.05),
					],
					startPoint: .top, endPoint: .bottom)
			)
			.overlay {
				islandShape
					.fill(islandTint)
					.blendMode(.sourceAtop)
			}
			.overlay {
				islandShape.fill(islandGreen).blendMode(.sourceAtop)
			}
			.overlay {
				islandShape.strokeBorder(.white.opacity(0.16), lineWidth: 1)
			}
			// Softer and tighter than it was. A shadow large enough to need a lot of margin
			// is a shadow large enough to get clipped by something.
			.shadow(color: .black.opacity(0.42), radius: 10, y: 4)
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
			// Also suppressed in island mode. The bar there is only ever the resting bar —
			// the drop is a separate object below it — so a gradient meant for a tall panel
			// was dissolving the bottom third of a shape exactly one notch tall, and the bar
			// came out visibly shorter than the housing beside it.
			stops: model.phase.isCompact || isIsland
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
		Image(systemName: model.phase == .unlocked ? "lock.open.fill" : "lock.fill")
			.font(.system(size: 11, weight: .semibold))
			// White, not green. This is the menu bar's own vocabulary — the padlock beside
			// the cutout is a status glyph like the ones to its right, and those are never
			// coloured. Green was borrowed from a confirmation panel that no longer exists.
			.foregroundStyle(.white)
			// The shackle morphs rather than the glyph swapping, so it reads as one padlock
			// opening rather than two icons exchanged.
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
			// The one mechanical beat in an otherwise smooth sequence: a lock lets go all at
			// once.
			.symbolEffect(.bounce.up, options: .speed(0.9), value: model.phase == .unlocked)
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
		// Going home: narrow to the cutout, so the whole shape ends up behind the housing.
		//
		// The retract used to bring the height down to the menu bar band and stop there,
		// leaving the bar's ears — 36pt either side of the camera housing — sitting on open
		// menu bar. Those are visible screen, so ordering the window out made them disappear
		// in one frame: the height animated beautifully and then the last of it went *boop*.
		//
		// Collapsing the width as well means the bar slides in behind the cutout and there is
		// nothing left on screen to pop when the window goes.
		guard expanded else { return cutoutWidth }
		return model.phase.isCompact ? compactBarWidth : width
	}

	/// The bar at rest: the housing plus a short ear either side.
	private var compactBarWidth: CGFloat {
		min(width, cutoutWidth + 2 * Self.restingEar)
	}

	/// Screen either side of the housing that the resting bar covers.
	private static let restingEar: CGFloat = 36

	/// The part of the panel that actually shows below the cutout.
	private var visibleHeight: CGFloat { currentHeight - notchInset }

	/// Sized against the visible drop. The mask does not touch the glyph, so it only has
	/// to fit — it does not have to stay inside the opaque part.
	/// True when the mark sits in a corner rather than the middle.
	private var isCorner: Bool { model.glyphPlacement == .corner }

	/// Held off the rounded edge so it does not crowd the corner it sits in.
	private var cornerGlyphInset: CGFloat {
		isIsland ? islandSide * 0.16 : max(10, earWidth * 0.5)
	}

	private var glyphSide: CGFloat {
		// Smaller in a corner. A mark that keeps its full size and merely moves is not
		// tucked into anything — it is the same mark, off-centre.
		let base = isIsland ? min(islandWidth, islandHeight) * 0.46
			: min(width, visibleHeight) * 0.52
		return isCorner ? base * 0.52 : base
	}

	/// Sits high in the drop, where the panel is still dark enough to carry it.
	private var glyphTop: CGFloat {
		if isCorner {
			// Just under the housing for the attached panel; just inside the island's own
			// top edge for the island.
			return isIsland
				? notchInset + Self.islandGap + islandSide * 0.14
				: notchInset + max(6, visibleHeight * 0.14)
		}
		guard !isIsland else {
			// Centred, because an island has no fade to stay clear of and no housing to sit
			// under — it is a panel in its own right.
			return notchInset + Self.islandGap + (islandHeight - glyphSide) / 2
		}
		return notchInset + visibleHeight * 0.30 - glyphSide / 2
	}

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
			// Hierarchical only for the tick, where the softened disc is what makes it read
			// as frosted rather than as a sticker. On the Face ID mark it just dims the whole
			// glyph, which left it washed out against the glass.
			.symbolRenderingMode(model.phase == .success ? .hierarchical : .monochrome)
			.foregroundStyle(symbolTint)
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
			// Breathing while it looks — the system effect, not an opacity loop.
			.symbolEffect(.breathe, options: .repeating, isActive: model.phase == .scanning)
			.symbolEffect(.bounce, value: model.phase == .notRecognised)
			// The shackle springing open. `.bounce` on the padlock is the one moment in the
			// sequence that should feel mechanical rather than smooth — a lock is a physical
			// thing, and it lets go all at once.
			.symbolEffect(.bounce.up, options: .speed(0.9), value: model.phase == .unlocked)
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
		case .locked, .unlocked: return "lock.fill"
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
		case .success: return Theme.faceID
		case .notRecognised: return Theme.danger
		case .locked, .scanning, .unlocked: return .white
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
