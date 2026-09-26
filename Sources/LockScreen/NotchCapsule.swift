import AppKit
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
		/// Matched the enrolled face, but the anti-spoof model judged it a fake — a photo
		/// or a screen held to the camera. Its own phase, not `notRecognised`, because it
		/// is a different answer: "that is your face, but it isn't you here."
		case spoofRejected
		/// Recognised, and now being asked to prove they are present — blink, turn, nod.
		///
		/// Between the match and the password, and only when the user has asked for it. The
		/// object detector catches a device held in frame; this catches the case it cannot,
		/// a photograph filling the whole frame with no bezel to see. A photo cannot blink.
		///
		/// The prompt travels with the phase rather than being read from a model, because
		/// the panel is drawn by an `NSHostingView` in a different process context from the
		/// watcher that picks the action, and a shared observable across that boundary is a
		/// great deal of machinery for one short string.
		case challenge(prompt: String, symbol: String, hintX: CGFloat, hintY: CGFloat, pulses: Bool, isReturningToRest: Bool = false)
		/// The password has been submitted and macOS has not confirmed the unlock yet.
		/// Waiting, neutrally: the padlock stays closed and there is no tick.
		///
		/// A tick here would read as a completed unlock while the login window is still
		/// deciding. `.success` is autofill-only; confirmation arrives as `.unlocked`.
		case pending
		/// Autofill filled the password into a saved app. The tick.
		///
		/// The Mac unlock path never presents this between submission and confirmation —
		/// that gap is `.pending`. Collapsing the two announced an outcome the Mac had
		/// not confirmed yet.
		case success
		/// The Mac is actually open. The padlock lets go.
		///
		/// Separate from `pending` because they are separate events, and the gap between them
		/// is real: pending is this app saying "that was you, here is your password", and the
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
		/// Success and pending keep the panel open to carry the tick and the waiting words.
		/// Unlocked is back to resting: the panel is already on its way home and the
		/// padlock is the only thing left to say.
		var isCompact: Bool { self == .locked || self == .unlocked }

		/// The words shown beneath the mark while waiting for macOS to confirm the unlock.
		static let pendingCaption = "Waiting for macOS"
		/// Neutral waiting symbol: an hourglass, never a tick or an opening padlock.
		static let pendingSymbol = "hourglass"
		/// The words shown when the face does not match, with a retry cue.
		static let notRecognisedCaption = "Not recognised. Try again."
		/// The mark's own symbol for a miss, matching the Settings face glyph.
		static let notRecognisedSymbol = "faceid"
		/// The words shown when the anti-spoof check refuses the attempt.
		///
		/// It does not say "photo": the detector looks for a phone, screen or print
		/// anywhere in frame, so a real face can be refused because of a monitor or a
		/// picture on the wall behind it. Naming a cause the app cannot be sure of
		/// accuses the owner of something they did not do. "Use your password" rather
		/// than "try again" because looking again will not clear it.
		static let spoofRejectedCaption = "Face rejected. Use your password."
		/// A blocked-by-a-check symbol, rather than one naming a cause.
		static let spoofRejectedSymbol = "exclamationmark.shield"

		/// The words the panel shows, where the phase carries its own.
		var challengePrompt: String? {
			if case .challenge(let prompt, _, _, _, _, _) = self { return prompt }
			return nil
		}

		/// Every caption the panel can show: challenge words, the neutral pending
		/// message, or the two rejection captions. Other padlock-closed states
		/// carry no caption.
		var captionText: String? {
			if let prompt = challengePrompt { return prompt }
			if case .pending = self { return Self.pendingCaption }
			if case .notRecognised = self { return Self.notRecognisedCaption }
			if case .spoofRejected = self { return Self.spoofRejectedCaption }
			return nil
		}

		/// The symbol beside the caption, if the phase carries one.
		var captionSymbol: String? {
			if case .challenge(_, let symbol, _, _, _, _) = self { return symbol }
			if case .pending = self { return Self.pendingSymbol }
			if case .notRecognised = self { return Self.notRecognisedSymbol }
			if case .spoofRejected = self { return Self.spoofRejectedSymbol }
			return nil
		}

		/// An outward movement prompt with the gate's progress, in two-movement mode.
		///
		/// The first presentation reads "… · 1 of 2" and the second "… · 2 of 2", so a
		/// fresh prompt after a completed movement reads as progress rather than a reset.
		/// One-movement mode stays exactly as-is: with nothing to count, a suffix would
		/// be clutter. Return-to-rest prompts never pass through here — the animated
		/// return stays captionless by design.
		///
		/// Pure presentation: the gate keeps the count, and `reset()` clears it, so a
		/// reset can never leave a stale "2 of 2" behind — the next presentation is
		/// recomputed from the cleared gate.
		static func outwardPrompt(_ prompt: String, completedActions: Int, requiredActions: Int) -> String {
			guard requiredActions == 2 else { return prompt }
			return "\(prompt) · \(completedActions + 1) of \(requiredActions)"
		}

		/// How the mark should move to demonstrate the action, if it should.
		var challengeHint: (x: CGFloat, y: CGFloat, pulses: Bool)? {
			if case .challenge(_, _, let x, let y, let pulses, _) = self { return (x, y, pulses) }
			return nil
		}

		/// The action's own symbol, shown beside the words rather than instead of the face.
		var challengeSymbol: String? {
			if case .challenge(_, let symbol, _, _, _, _) = self { return symbol }
			return nil
		}

		var isReturningToRest: Bool {
			if case .challenge(_, _, _, _, _, let returning) = self { return returning }
			return false
		}

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
	/// Mirrors `Preferences.showNotchCaptions`, captured when the panel is shown.
	/// Display only: captions reserve space only when enabled.
	var showsCaptions = true
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

	/// Growing out. A spring, because the panel emerges from a physical object and should
	/// carry a little momentum doing it — and because a spring survives interruption, which
	/// matters when a face arrives while the panel is still on its way out.
	static let expand = Animation.spring(response: 0.3, dampingFraction: 0.9)
	static let reducedDuration: TimeInterval = 0.14
	static let reduced = Animation.easeOut(duration: reducedDuration)
	static let feedback = Animation.easeOut(duration: 0.18)
	static let islandExpand = Animation.spring(response: 0.36, dampingFraction: 0.94)

	/// Going home. Ease-out, and quicker than the grow.
	///
	/// Two changes from `.smooth(duration: 0.55)`.
	///
	/// The curve: `.smooth` is SwiftUI's stock ease, and stock easings are too weak to read
	/// as deliberate — this is the strong ease-out (0.23, 1, 0.32, 1), which leaves
	/// immediately and settles slowly.
	///
	/// The duration: 550ms was longer than the grow, which is backwards. An entrance is the
	/// part somebody is waiting for; an exit is the part they have already stopped caring
	/// about, and holding a panel on screen for over half a second after its job is done is
	/// how a status indicator starts feeling like an obstacle.
	static let retractDuration: TimeInterval = 0.22
	static var retract: Animation {
		.timingCurve(0.23, 1, 0.32, 1, duration: retractDuration)
	}

	/// Between phases — the drop opening and closing as the state changes.
	///
	/// Ease-in-**out**, not ease-out: this is not something entering or leaving, it is the
	/// same object changing shape on screen, and movement between two on-screen states wants
	/// symmetry at both ends.
	static let phaseDuration: TimeInterval = 0.24
	static var phase: Animation {
		.timingCurve(0.4, 0, 0.2, 1, duration: phaseDuration)
	}

	/// How long the controller must leave the window alive after asking it to retract.
	/// The margin is for the frame the animation finishes on.
	static var teardownDelay: TimeInterval { max(retractDuration, phaseDuration) + 0.16 }
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

	/// Raised from 0.18. At that tint the panel was so faint you could not tell it was
	/// there, which makes it not a style but an absence — glass you cannot see is just a
	/// hole. Dark enough to read as a panel, light enough that the wallpaper still moves
	/// through it.
	static func liquidTint(boost: Double) -> Double {
		min(0.7, 0.36 + boost)
	}
}

/// The panel that drops out of the notch while Gaze runs.
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
	/// False on screens without a physical notch, where Connected + Beside the camera
	/// falls back to the centred panel.
	var hasNotch: Bool = true

	@Environment(\.accessibilityReduceMotion) private var systemReduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion
	private var reduceMotion: Bool { systemReduceMotion || previewReduceMotion }
	// Reduce Motion skips the grow-out by reading as expanded, so opacity must never gate on isExpanded — that would blank the resting padlock.
	private var expanded: Bool { reduceMotion || model.isExpanded }

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
	/// Capped at 26, not 15.
	///
	/// 15 was set when the panel was small, and on a fully dropped panel it reads as a
	/// square-cornered box — the corner is there but too tight to see against 160pt of
	/// height. The floor and the divisor are unchanged, so the retracting animation still
	/// keeps its rounded lip all the way down; only the ceiling moved.
	private var cornerRadius: CGFloat {
		usesCompactBar ? 9 : min(26, max(9, max(0, visibleHeight) / 1.9))
	}

	// MARK: - Island

	/// Whether this panel is the detached island rather than the attached drop.
	///
	/// Compact phases stay attached whatever the setting: the resting padlock lives in the
	/// menu bar band, and an island cannot be at rest — it is the thing that pops out.
	private var isIsland: Bool { model.shape == .island && showsDrop }

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
	private var islandHiddenOffset: CGFloat { -12 }

	/// Nebulark's gradient: black at the top running into green at the bottom.
	///
	/// Green only ever appears while the island is doing something — it has no resting
	/// state — so this keeps the rule the rest of the app follows, that green means Gaze
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

	/// How far the top corners flare out into the screen edge.
	///
	/// Grows with the panel rather than being fixed. Collapsed, the panel is hidden behind
	/// the physical cutout and a flare there would put two curves on screen that belong to
	/// nothing; as it drops, the flare opens with it so the join is always the width of the
	/// thing it is joining.
	private var usesCompactBar: Bool { isIsland || model.phase.isCompact }

	// MARK: - Ear flank (Connected + Beside the camera)

	/// Connected with the mark beside the camera: black flanking the housing on both
	/// sides, never over it. The middle of the row is the physical cutout, so nothing
	/// is drawn there.
	///
	/// Only Connected offers the choice, and only on a screen with a physical notch to
	/// flank — without one this falls back to the centred panel, as before.
	private var isEarFlank: Bool {
		model.shape == .attached && model.glyphPlacement == .ear && hasNotch
	}

	private enum EarFlankMetrics {
		/// Black beside the cutout on each side. The resting silhouette is the cutout
		/// plus twice this, and grows only sideways from there.
		static let flank: CGFloat = 54
		/// The cutout's own height cannot change, so this is the visible black below it.
		static let heightBump: CGFloat = 8
		static let topRadius: CGFloat = 12
		static let bottomRadius: CGFloat = 12
		static let lockSize: CGFloat = 15
		static let faceSize: CGFloat = 30
		/// Past this width the caption truncates with an ellipsis. The window controller
		/// sizes the ear window for this, so the two must change together.
		static let maxCaptionWidth: CGFloat = 170
	}

	// MARK: - Dynamic Island

	/// A true floating capsule under the notch, on every Mac.
	private var isDynamicIsland: Bool { model.shape == .dynamicIsland }

	private enum DynamicIslandMetrics {
		static let restingWidth: CGFloat = 126
		static let restingHeight: CGFloat = 37
		/// With something to say the island grows only a little taller and exactly as
		/// wide as its words: a Mac has no hardware island to hide in, so a large dark
		/// panel reads as empty space rather than as the island opening.
		static let activeHeight: CGFloat = 44
		static let successWidth: CGFloat = 170
		/// Below the notch's bottom edge — or below the safe area top with no notch.
		static let topGap: CGFloat = 6
		static let edgeInset: CGFloat = 12
		static let glyphSize: CGFloat = 15
		static let restingFaceSize: CGFloat = 24
		static let activeFaceSize: CGFloat = 30
		/// Past this total width the words truncate.
		static let maxWidth: CGFloat = 340
		/// One spring for every change of size, so width, height and radius move as one.
		static let morph = Animation.spring(response: 0.4, dampingFraction: 0.82)
		/// The small celebratory scale on success, up and back.
		static let successPulse = Animation.spring(response: 0.32, dampingFraction: 0.6)
	}


	/// The one-line caption on the face-side flank. Only the phases that carry
	/// guidance show it here: challenge prompts and the two rejection captions. Pending
	/// and success keep the resting silhouette.
	///
	/// Same titles the island carries: the prompt without its " · N of M" step suffix,
	/// which the flank has no room for — the island splits that half into a subtitle.
	private var earCaption: String? {
		guard model.showsCaptions else { return nil }
		switch model.phase {
		case .challenge(let prompt, _, _, _, _, _) where !prompt.isEmpty:
			let parts = prompt.components(separatedBy: " · ")
			return parts.count > 1 ? parts.dropLast().joined(separator: " · ") : prompt
		case .notRecognised:
			return NotchCapsuleModel.Phase.notRecognisedCaption
		case .spoofRejected:
			return NotchCapsuleModel.Phase.spoofRejectedCaption
		default:
			return nil
		}
	}

	/// The measured words for the face-side flank, capped so a long prompt cannot push
	/// the silhouette past its window. A number, not a hug, so the
	/// flank width below animates as one value instead of re-measuring text each frame.
	private var earMessageWidth: CGFloat {
		guard let caption = earCaption else { return 0 }
		return min(Self.textWidth(caption, size: 12, weight: .semibold), EarFlankMetrics.maxCaptionWidth)
	}

	/// The face-side flank widens only to carry a message: resting width plus the
	/// measured words and the gap between face and text. No words, no widening.
	private var earFaceFlankWidth: CGFloat {
		guard earCaption != nil else { return EarFlankMetrics.flank }
		return EarFlankMetrics.flank + 6 + earMessageWidth
	}

	private var isEarUnlocked: Bool {
		model.phase == .success || model.phase == .unlocked
	}

	private var earNotchHeight: CGFloat { notchInset + EarFlankMetrics.heightBump }

	private var earLock: some View {
		Image(systemName: isEarUnlocked ? "lock.open.fill" : "lock.fill")
			.accessibilityHidden(true)
			.font(.system(size: EarFlankMetrics.lockSize, weight: .semibold))
			.foregroundStyle(.white)
			.contentTransition(.symbolEffect(.replace))
	}

	private var earFace: some View {
		GazeFaceMark(phase: model.phase, active: model.isExpanded && !model.phase.isCompact)
			.frame(width: EarFlankMetrics.faceSize, height: EarFlankMetrics.faceSize)
	}

	private var earShape: NotchPanelShape {
		NotchPanelShape(
			topRadius: EarFlankMetrics.topRadius, bottomRadius: EarFlankMetrics.bottomRadius)
	}

	/// The silhouette fill, honouring Style like the island does.
	@ViewBuilder
	private var earSilhouette: some View {
		switch model.style {
		case .normal:
			earShape.fill(.black)
		case .semiLiquidGlass:
			earShape
				.fill(.black.opacity(glassTint))
				.background { earShape.fill(.ultraThinMaterial) }
		case .liquidGlass:
			Color.clear.glassEffect(
				.regular.tint(.black.opacity(NotchGlass.liquidTint(boost: lightWallpaperBoost))),
				in: earShape)
		}
	}

	@ViewBuilder
	private var earBody: some View {
		HStack(spacing: 0) {
			earLock
				.frame(width: EarFlankMetrics.flank, height: earNotchHeight)
			// The physical cutout itself: reserved space, never drawn over.
			Spacer(minLength: 0)
				.frame(width: cutoutWidth)
			if let caption = earCaption {
				// The message rides in the face-side flank, which widens to carry it.
				// It cannot sit in the middle: that space is the camera housing itself.
				HStack(spacing: 6) {
					earFace
					Text(caption)
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.truncationMode(.tail)
						.frame(width: earMessageWidth)
						.accessibilityHidden(true)
				}
				.frame(width: earFaceFlankWidth, height: earNotchHeight, alignment: .leading)
				.transition(.opacity)
			} else {
				earFace
					.frame(width: EarFlankMetrics.flank, height: earNotchHeight)
			}
		}
		.padding(.horizontal, 4)
		.background { earSilhouette }
		// Only the face side grows, so matching clear space on the lock side keeps the
		// reserved gap centred on the camera instead of sliding left of it.
		.padding(.leading, earFaceFlankWidth - EarFlankMetrics.flank)
		.frame(height: earNotchHeight)
		.opacity(expanded ? 1 : 0)
		.animation(reduceMotion ? nil : NotchAnimation.phase, value: earCaption ?? "")
		.animation(reduceMotion ? nil : DynamicIslandMetrics.morph, value: earFaceFlankWidth)
		.animation(
			reduceMotion ? nil : (expanded ? NotchAnimation.expand : NotchAnimation.retract),
			value: expanded)
	}

	// MARK: - Dynamic island body

	/// Whether the island has something to say. Locked and pending rest as the
	/// small capsule; scanning cannot tell whether a face is in frame yet, so it
	/// opens — "Looking for you" is something to say.
	private var isDynamicExpanded: Bool {
		switch model.phase {
		case .scanning, .challenge, .notRecognised, .spoofRejected: true
		case .locked, .pending, .success, .unlocked: false
		}
	}

	private var isDynamicSuccess: Bool { model.phase == .success }

	private var isDynamicUnlocked: Bool {
		model.phase == .success || model.phase == .unlocked
	}

	/// The open panel's headline. Challenge prompts arrive with their step count
	/// as a " · N of M" suffix (see `outwardPrompt`), which splits into a title
	/// and a step line; scanning and the rejections carry no step.
	///
	/// Ignores the caption setting on purpose: the island's whole job is to grow and carry
	/// these words, and with captions off it stayed a small capsule while scanning.
	private var dynamicTitle: String? {
		switch model.phase {
		case .challenge(let prompt, _, _, _, _, _) where !prompt.isEmpty:
			let parts = prompt.components(separatedBy: " · ")
			return parts.count > 1 ? parts.dropLast().joined(separator: " · ") : prompt
		case .scanning:
			return "Looking for you"
		case .notRecognised:
			return NotchCapsuleModel.Phase.notRecognisedCaption
		case .spoofRejected:
			return NotchCapsuleModel.Phase.spoofRejectedCaption
		case .success:
			return "Unlocked"
		default:
			return nil
		}
	}

	private var dynamicSubtitle: String? {
		if case .challenge(let prompt, _, _, _, _, _) = model.phase {
			let parts = prompt.components(separatedBy: " · ")
			if parts.count > 1, let step = parts.last, !step.isEmpty { return step }
		}
		return nil
	}

	private var dynamicHeight: CGFloat {
		isDynamicExpanded ? DynamicIslandMetrics.activeHeight : DynamicIslandMetrics.restingHeight
	}

	/// Always a number, measured from the words when there are any.
	///
	/// It used to be nil with words showing so the capsule could hug them. SwiftUI cannot
	/// interpolate between "hug" and a fixed width, so every open and close re-measured the
	/// text each frame and the morph stuttered. A measured width animates as one value.
	private var dynamicWidth: CGFloat {
		guard (isDynamicExpanded || isDynamicSuccess), let title = dynamicTitle else {
			return isDynamicSuccess ? DynamicIslandMetrics.successWidth : DynamicIslandMetrics.restingWidth
		}
		var words = Self.textWidth(title, size: 13, weight: .semibold)
		if let step = dynamicSubtitle { words += 6 + Self.textWidth(step, size: 12, weight: .medium) }
		words = min(words, DynamicIslandMetrics.maxWidth - 100)
		let chrome = DynamicIslandMetrics.edgeInset * 2 + 20 + DynamicIslandMetrics.activeFaceSize + 20
		// Success measures its word like any other title, with successWidth as the floor
		// rather than the fixed size — a fixed size would clip a wider future caption.
		let minimum = isDynamicSuccess ? DynamicIslandMetrics.successWidth : DynamicIslandMetrics.restingWidth
		return min(DynamicIslandMetrics.maxWidth, max(minimum, (words + chrome).rounded(.up)))
	}

	private static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
		(text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width.rounded(.up)
	}

	/// One key for the morph, so a single spring drives size and radius together.
	private var dynamicLayoutKey: String {
		"\(isDynamicExpanded)-\(isDynamicSuccess)-\(dynamicTitle ?? "")"
	}

	/// A capsule honouring Style, the way the ear pill did.
	@ViewBuilder
	private var dynamicSilhouette: some View {
		let shape = Capsule(style: .continuous)
		switch model.style {
		case .normal:
			shape.fill(.black)
		case .semiLiquidGlass:
			shape
				.fill(.black.opacity(glassTint))
				.background { shape.fill(.ultraThinMaterial) }
		case .liquidGlass:
			Color.clear.glassEffect(
				.regular.tint(.black.opacity(NotchGlass.liquidTint(boost: lightWallpaperBoost))),
				in: shape)
		}
	}

	/// The glyph on the leading end: the movement's own symbol while a prompt is up,
	/// otherwise the lock, opening on success.
	private var dynamicGlyph: some View {
		Image(systemName: model.phase.challengeSymbol ?? (isDynamicUnlocked ? "lock.open.fill" : "lock.fill"))
			.accessibilityHidden(true)
			.font(.system(size: DynamicIslandMetrics.glyphSize, weight: .semibold))
			// Green only on success: the rest of the time the glyph is a status mark, and
			// colour there would spend the confirmation colour before anything is confirmed.
			.foregroundStyle(isDynamicSuccess ? Theme.faceID : .white)
			.contentTransition(.symbolEffect(.replace))
			.frame(width: 20)
	}

	/// One row for every state: glyph, words when there are any, companion. Nothing is
	/// swapped out between states — only the words come and go — so the companion's
	/// renderer is never torn down and rebuilt mid-animation, which is what made the
	/// morph stutter.
	private var dynamicBody: some View {
		HStack(spacing: 10) {
			dynamicGlyph
			if (isDynamicExpanded || isDynamicSuccess), let title = dynamicTitle {
				HStack(spacing: 6) {
					Text(title)
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(.white)
					if let step = dynamicSubtitle {
						Text(step)
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(.white.opacity(0.55))
					}
				}
				.lineLimit(1)
				.truncationMode(.tail)
				// The width cap belongs on the words. Around the capsule it made the black as
				// wide as the cap even at rest.
				.frame(maxWidth: .infinity, alignment: .leading)
				.accessibilityHidden(true)
				// Opacity only: a scale here was a second, differently timed motion inside
				// the morph.
				.transition(.opacity)
			} else {
				Spacer(minLength: 0)
			}
			GazeFaceMark(phase: model.phase, active: model.isExpanded && !model.phase.isCompact)
				.frame(width: DynamicIslandMetrics.activeFaceSize, height: DynamicIslandMetrics.activeFaceSize)
				.scaleEffect(isDynamicExpanded ? 1
					: DynamicIslandMetrics.restingFaceSize / DynamicIslandMetrics.activeFaceSize)
		}
		.padding(.horizontal, DynamicIslandMetrics.edgeInset)
		.frame(width: dynamicWidth, height: dynamicHeight)
		.background { dynamicSilhouette }
		// Words arriving mid-morph stay inside the capsule instead of spilling past it.
		.clipShape(Capsule(style: .continuous))
		// Animate the whole island as one layer, so size, radius and contents stay in step.
		.geometryGroup()
		.scaleEffect(reduceMotion || !isDynamicSuccess ? 1 : 1.04)
		.animation(reduceMotion ? nil : DynamicIslandMetrics.successPulse, value: isDynamicSuccess)
		.animation(reduceMotion ? NotchAnimation.reduced : DynamicIslandMetrics.morph, value: dynamicLayoutKey)
		// The top edge stays put while the island grows downward and sideways.
		.padding(.top, notchInset + DynamicIslandMetrics.topGap)
		.scaleEffect(reduceMotion ? 1 : (expanded ? 1 : 0.6), anchor: .top)
		.opacity(expanded ? 1 : 0)
		// No animation on `expanded` here: the outer body already animates it, and a
		// second spring on the same value fought it over scale and opacity mid-morph.
	}

	private var flareRadius: CGFloat {
		min(17, max(0, usesCompactBar ? restingBarHeight - notchInset : visibleHeight) / 2.4)
	}

	private var shape: NotchPanelShape {
		NotchPanelShape(topRadius: flareRadius, bottomRadius: cornerRadius)
	}

	/// The visible screen either side of the cutout, in whichever shape is currently drawn.
	private var earWidth: CGFloat { max(0, (compactBarWidth - cutoutWidth) / 2) }

	var body: some View {
		ZStack(alignment: .top) {
			// Grows downward out of the cutout and retracts back into it. Collapsed, the
			// shape is exactly the notch's height, so it is completely hidden behind the
			// physical cutout — nothing appears or disappears, it emerges.
			// The bar is always drawn in the attached and island modes. The ear flank
			// draws its own flanking silhouette instead (see earBody), and the
			// dynamic island draws its own floating capsule (see dynamicBody).
			//
			// Island mode used to draw the island *instead* of it, which left the padlock
			// standing on bare menu bar with nothing behind it — the chip's ground is the
			// bar, and taking the bar away took the ground with it. The bar is the notch;
			// the island is a thing the notch hands down. Both, always.
			if isEarFlank {
				earBody
			} else if isDynamicIsland {
				dynamicBody
			} else {
				background
				// Widened by the flare on each side, not narrowed by it.
				//
				// `NotchPanelShape` insets its body to leave room for the flares, so
				// passing `backgroundWidth` straight through made the panel's body 2×12pt
				// narrower than it had been — the walls moved inward and the panel stopped
				// lining up with the cutout. Adding the flare back on means the body stays
				// exactly `backgroundWidth` and the wings extend beyond it, which is what
				// "flared" is supposed to mean.
				.frame(
					width: (expanded && usesCompactBar ? compactBarWidth : backgroundWidth) + flareRadius * 2,
					height: expanded
						? (isIsland ? restingBarHeight : currentHeight)
						: notchInset)
			}

			// Always in the hierarchy while this is island mode, shown or not.
			//
			// It used to be inserted the moment scanning began, so its offset and scale were
			// already at their final values when it appeared — it popped into place with no
			// travel at all, while the attached panel got the full spring. Keeping the view
			// mounted and animating a *value* is what gives both shapes the same timing.
			if model.shape == .island {
				islandBody
					.frame(width: islandWidth, height: islandHeight)
					// The mark rides *inside* the island rather than being positioned against
					// the window. Drawn separately it stayed at its final place while the
					// island travelled, so the two came apart mid-animation and the glyph
					// hung below a panel that had not arrived yet.
					.overlay { content.frame(width: glyphSide, height: glyphSide) }
					.overlay(alignment: .bottom) {
						challengeCaption
							.padding(.horizontal, 10)
							.padding(.bottom, 14)
					}
					.scaleEffect(islandIsOut || reduceMotion ? 1 : 0.96, anchor: .top)
					.offset(y: islandIsOut || reduceMotion ? 0 : islandHiddenOffset)
					.opacity(islandIsOut ? 1 : 0)
					.padding(.top, notchInset + Self.islandGap)
					.animation(
						reduceMotion ? nil
							: (islandIsOut ? NotchAnimation.islandExpand : NotchAnimation.retract),
						value: islandIsOut)
			}

			// Locked: a padlock beside the cutout, at menu bar height.
			//
			// It used to hang below the notch on a stub of panel, which is the one place it
			// could not go — the drop is the *active* state, so a resting padlock sitting in
			// it said the panel was doing something when it was doing nothing. Notch apps
			// put a resting indicator in the screen either side of the housing instead, and
			// that is space this window already covers.
		// The padlock stays closed for the wait: pending shows the waiting words in the
		// drop and the same padlock shut where it has sat all along. Only the confirmed
		// unlock opens it.
			if model.phase.showsLockChip && !isEarFlank && !isDynamicIsland {
				lockChip
					// Always positioned against the *resting* bar, never the panel.
					//
					// This used `backgroundWidth`, which is the resting bar while compact and
					// the full window once a panel drops — so the padlock slid outward the
					// moment scanning began, ending up further left than the ear it had been
					// sitting in. The bar it belongs to does not move, so neither should it.
					.frame(width: compactBarWidth, alignment: .leading)
					.opacity(expanded ? 1 : 0)
					.transition(.opacity)
			}

			if showsDrop && !isIsland && !isEarFlank && !isDynamicIsland {
				VStack(spacing: 7) {
					content
						.frame(width: glyphSide, height: glyphSide)
					challengeCaption
				}
					.animation(reduceMotion ? nil : NotchAnimation.feedback, value: model.phase.captionText)
					// Centred in the solid band — not the whole window (whose top third is
					// behind the cutout) and not the whole visible drop (whose lower part
					// fades to clear, which would dissolve the glyph along with it).
					.padding(.top, glyphTop)
					.opacity(expanded ? 1 : 0)
					.scaleEffect(expanded || reduceMotion ? 1 : 0.94, anchor: .top)
					// Out before the panel is, so the panel never closes over a glyph that
					// is still solid — that overlap is what made the retract look like two
					// separate events instead of one.
					.animation(reduceMotion ? nil : NotchAnimation.feedback, value: expanded)
			}
		}
		.frame(width: width, height: height, alignment: .top)
		// Separate transactions: expand/retract timing for the drop, quicker
		// feedback timing for phase and caption changes.
		.animation(
			reduceMotion ? nil : (expanded ? NotchAnimation.expand : NotchAnimation.retract),
			value: expanded)
		.animation(
			reduceMotion ? nil : NotchAnimation.feedback,
			value: [String(describing: model.phase.isCompact), model.phase.captionText ?? ""].joined(separator: "|"))
		.symbolEffectsRemoved(reduceMotion)
	}

	private var showsChallengeCaption: Bool {
		model.showsCaptions && model.phase.captionText != nil
	}

	private var hidesReturnCaption: Bool {
		model.phase.isReturningToRest && !reduceMotion
	}

	private var challengeCaption: some View {
		ZStack {
			if showsChallengeCaption, let prompt = model.phase.captionText {
				HStack(spacing: 5) {
					if let symbol = model.phase.captionSymbol {
						Image(systemName: symbol)
							.font(.system(size: 10, weight: .semibold))
							// The words beside it already animate on change; without this the
							// glyph was the one thing that cut. Directional rather than magic:
							// a movement prompt and a rejection share no shape to morph.
							.contentTransition(.symbolEffect(.replace.downUp))
							.accessibilityHidden(true)
					}
					Text(prompt)
						.font(.system(size: 11, weight: .medium))
						.multilineTextAlignment(.center)
						.lineLimit(2)
						.fixedSize(horizontal: false, vertical: true)
				}
				.foregroundStyle(.white)
				.opacity(hidesReturnCaption || !model.showsCaptions ? 0 : 1)
				// Always hidden: GazeFaceMark already announces this same text, so
				// exposing the caption would read every state twice.
				.accessibilityHidden(true)
				.id(prompt)
				.transition(.opacity)
			}
		}
	}

	/// The detached island.
	///
	/// Honours Style, which it did not before: the fill was hardcoded, so choosing Normal or
	/// Liquid Glass changed the bar above the island and left the island itself identical.
	/// A style setting that visibly applies to one half of the panel is worse than none.
	///
	/// Nebulark's green stays in every style — it is the island's own identity rather than a
	/// property of the material, and it is the one thing that makes this shape *this* shape.
	private var islandBody: some View {
		islandShape
			.fill(islandFill)
			.background { islandBacking }
			.overlay { islandShape.fill(islandGreen).blendMode(.sourceAtop) }
			.overlay { islandShape.strokeBorder(.white.opacity(0.16), lineWidth: 1) }
			// Softer and tighter than it was. A shadow large enough to need a lot of margin
			// is a shadow large enough to get clipped by something.
			.shadow(color: .black.opacity(0.42), radius: 10, y: 4)
	}

	/// The island's own colour, at the density the chosen style asks for.
	private var islandFill: Color {
		switch model.style {
		case .normal:
			return .black
		case .semiLiquidGlass:
			return .black.opacity(
				NotchGlass.semiTint(transparency: model.transparency, boost: lightWallpaperBoost))
		case .liquidGlass:
			return .black.opacity(NotchGlass.liquidTint(boost: lightWallpaperBoost))
		}
	}

	/// A blur behind the translucent styles, and nothing behind the solid one.
	@ViewBuilder
	private var islandBacking: some View {
		if model.style == .normal {
			islandShape.fill(.black)
		} else {
			islandShape.fill(.ultraThinMaterial)
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
		// Applied only when this shape *is* the panel that hangs below the housing.
		//
		// In island and ear modes the background is the resting bar and nothing more — the
		// island is a separate object below it, and on the ear nothing drops at all. A
		// gradient meant for a tall panel was dissolving the bottom third of a shape exactly
		// one notch tall, so the bar came out visibly shorter than the housing beside it.
		// Stating the condition positively is what stops this needing fixing once per mode.
		let stops: [Gradient.Stop] =
			barIsTheDrop
			? [
				.init(color: .black, location: 0),
				.init(color: .black, location: 0.36),
				.init(color: .black.opacity(0.72), location: 0.55),
				.init(color: .black.opacity(0.38), location: 0.76),
				.init(color: .black.opacity(0.12), location: 0.92),
				.init(color: .clear, location: 1),
			]
			: [
				.init(color: .black, location: 0),
				.init(color: .black, location: 1),
			]
		return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
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
			.accessibilityHidden(true)
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
			// Optically centred in the bar it stands on, lip included — centring it on the
			// housing alone pushed it up against the top edge once the bar grew.
			.frame(width: earWidth, height: restingBarHeight)
	}

	/// Flush with the cutout while resting, the full drop once it is scanning.
	///
	/// The 11pt lip this had was almost the entire overhang: the notch is 32pt tall and a
	/// notch app's bar sits flush with it, so anything hanging below shows as a second shape
	/// behind the first. Nothing hangs below now — the resting bar occupies the menu bar band
	/// and no more, and its corners round *within* that band, which is what the radius floor
	/// is for.
	private var currentHeight: CGFloat {
		model.phase.isCompact ? restingBarHeight : height
	}

	/// The bar that carries the padlock: the housing's height plus a single point.
	///
	/// It looked short once, but that was the bottom fade dissolving its lower third rather
	/// than the height being wrong — and a 12pt lip added to "fix" it made the bar hang below
	/// the notch, which is worse than either.
	///
	/// The one point is not a fudge. Flush leaves the bar's bottom edge and the housing's on
	/// exactly the same line, and any rounding in either direction shows as a hairline of
	/// wallpaper between them; a point of overlap guarantees they meet.
	private var restingBarHeight: CGFloat { notchInset + 1 }

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

	/// Whether the island is currently down out of the notch.
	private var islandIsOut: Bool { isIsland && expanded }

	/// True when the background shape is the panel that hangs below the housing, rather than
	/// just the bar the padlock sits on.
	private var barIsTheDrop: Bool { showsDrop && !isIsland }

	/// Whether anything drops out of the notch at all.
	///
	/// The ear flank and the dynamic island carry their captions inline, so neither
	/// uses the drop.
	private var showsDrop: Bool { !model.phase.isCompact }

	private var glyphSide: CGFloat {
		model.shape == .island
			? min(islandWidth, islandHeight) * 0.62
			: min(width, max(0, visibleHeight - (showsChallengeCaption ? 28 : 0))) * 0.68
	}

	/// Sits high in the drop, where the panel is still dark enough to carry it.
	private var glyphTop: CGFloat {
		guard !isIsland else {
			// Centred, because an island has no fade to stay clear of and no housing to sit
			// under — it is a panel in its own right.
			return notchInset + Self.islandGap + (islandHeight - glyphSide) / 2
		}
		return notchInset + max(6, (visibleHeight - glyphSide - (showsChallengeCaption ? 26 : 0)) / 2)
	}

	private var content: some View {
		GazeFaceMark(phase: model.phase, active: model.isExpanded && !model.phase.isCompact)
			.frame(width: glyphSide, height: glyphSide)
	}
}
