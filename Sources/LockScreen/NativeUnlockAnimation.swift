import AVFoundation
import AppKit
import SwiftUI

/// The native unlock animation: the iOS-style Face ID mark, shipped as clips.
///
/// This is what the panel draws when the setting asks for it, instead of the drawn head.
/// The head is a procedurally animated character — it turns, nods, smiles and frowns;
/// these are the mark most people mean when they say "unlock animation": the brackets
/// scanning, the swirl, and the tick.
///
/// The clips are black-backed, and they are composited with `.screen` so the black drops
/// out over whatever the panel is made of. On the Solid style that is a no-op — the panel
/// is black too — but on the glass styles a plain video layer would put a hard black
/// square on a translucent panel, which is the one thing that would give the setting away
/// as an add-on rather than part of the notch.
enum NativeUnlockAssets {

	/// Which clip a phase plays.
	enum Clip: String {
		/// Waiting: locked, scanning, or macOS still deciding. Loops.
		///
		/// A movement prompt never reaches this — `NotchFaceMark` takes every challenge
		/// beat, so the pose a prompt stops on is not snapped back to neutral when the
		/// return-to-rest or tick beat arrives.
		case idle
		/// The unlock landed. Plays once and holds on the tick.
		case success
		/// The face did not get through. Plays once and holds.
		case failure

		/// The bundle resource for this clip, in a given colour.
		///
		/// Nil when the clips are not in the bundle — a build from a tree that predates
		/// them, or one where they were not copied. Callers fall back rather than showing
		/// an empty panel.
		func url(colour: Preferences.UnlockAnimationColour) -> URL? {
			Bundle.main.url(
				forResource: "unlock-native-\(rawValue)-\(colour.rawValue)",
				withExtension: "mp4", subdirectory: "Art")
		}

		/// The mark's resting frame: shown under Reduce Motion, and used when a clip
		/// will not load.
		func stillURL(colour: Preferences.UnlockAnimationColour) -> URL? {
			Bundle.main.url(
				forResource: "unlock-native-static-\(colour.rawValue)",
				withExtension: "png", subdirectory: "Art")
		}

		var isLooping: Bool { self == .idle }
	}

	/// Which clip a phase plays.
	///
	/// `.unlocked` is the Mac agreeing to the unlock, and on this platform that is *the*
	/// unlock moment — the watcher goes straight from waiting to open, with no `.success`
	/// in between. Sending it to the resting clip is what left the panel with nothing to
	/// celebrate at the one instant worth celebrating.
	static func clip(for phase: NotchCapsuleModel.Phase) -> Clip {
		switch phase {
		case .success, .unlocked:
			return .success
		case .notRecognised, .spoofRejected, .unavailable:
			return .failure
		case .locked, .scanning, .challenge, .pending:
			return .idle
		}
	}

	/// Whether this colour ships at least one image.
	///
	/// The panel reads this before deciding to stay dropped through the unlock, so a
	/// build without the clips keeps the retract-immediately behaviour it always had.
	static func isAvailable(colour: Preferences.UnlockAnimationColour) -> Bool {
		Clip.idle.url(colour: colour) != nil || Clip.idle.stillURL(colour: colour) != nil
	}
}

/// The mark the lock-screen panel draws.
///
/// A single switch rather than three call sites each making it for themselves: the
/// native animation and the drawn head have to change together, and a panel where one
/// mark swapped and the other two did not would be a worse bug than no option at all.
struct NotchFaceMark: View {
	let phase: NotchCapsuleModel.Phase
	/// Mirrors `Preferences.nativeUnlockAnimation`, captured when the panel was shown.
	let usesNativeAnimation: Bool
	let colour: Preferences.UnlockAnimationColour
	var active = true

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		// A movement prompt is drawn rather than clipped: the idle clip has no idea what
		// is being asked for and would sit there breathing through the instruction.		//
		// Every challenge beat uses the drawn mark, not only the ones that demonstrate an
		// action. Skipping the two that do not — return-to-rest and the brief tick — handed
		// those back to the idle clip, and because the mark is usually mid-turn or mid-nod
		// when they arrive, the swap snapped it from there back to the clip's neutral
		// position: measurably up and to the right, and nothing to do with either
		// animation. One mark for the whole prompt, so the pose it stops on is the pose it
		// keeps animating from.
		if usesNativeAnimation && isChallenge {
			NativeMovementMark(phase: phase, colour: colour, active: active)
		} else if let clip {
			NativeUnlockAnimation(clip: clip, colour: colour, phase: phase, active: active)
		} else {
			GazeFaceMark(phase: phase, active: active)
		}
	}

	/// True for any challenge — the whole prompt sequence, whatever the beat.
	private var isChallenge: Bool {
		if case .challenge = phase { return true }
		return false
	}

	/// The clip this phase plays, or nil to draw the head instead.
	///
	/// Anything that would end with nothing on screen — the option off, or a colour with
	/// no images in the bundle — resolves to nil here, so `body` has exactly two outcomes
	/// and one of them is always the mark that used to be there.
	///
	/// Reduce Motion settles on the still rather than a clip. If this colour ships no
	/// still, that is a nil too, and the drawn head takes over — it already settles to a
	/// static pose under Reduce Motion, so the setting's promise holds either way. Playing
	/// the clip regardless would be the one branch that ignores what Reduce Motion asks.
	private var clip: NativeUnlockAssets.Clip? {
		guard usesNativeAnimation else { return nil }
		let clip = NativeUnlockAssets.clip(for: phase)
		if reduceMotion {
			guard clip.stillURL(colour: colour) != nil else { return nil }
		} else {
			guard clip.url(colour: colour) != nil || clip.stillURL(colour: colour) != nil else { return nil }
		}
		return clip
	}
}

struct NativeUnlockAnimation: View {
	let clip: NativeUnlockAssets.Clip
	let colour: Preferences.UnlockAnimationColour
	let phase: NotchCapsuleModel.Phase
	var active = true

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// The drawn head overscales itself by this much, so the clip does too — swapping
	/// one mark for the other should not change how large it reads in the panel.
	private static let overscale = 1.18

	var body: some View {
		media
			.scaleEffect(Self.overscale)
			.accessibilityElement(children: .ignore)
			.accessibilityHidden(false)
			.accessibilityLabel(phase.markAccessibilityLabel)
	}

	@ViewBuilder
	private var media: some View {
		// Reduce Motion asks for no moving image, and a looping mark is exactly that.
		// The still is the same mark's own resting frame, so nothing is lost but the motion.
		if reduceMotion, let still = clip.stillURL(colour: colour) {
			NativeUnlockStill(url: still)
		} else if let url = clip.url(colour: colour) {
			NativeUnlockPlayer(url: url, looping: clip.isLooping, active: active)
				.blendMode(.screen)
		} else if let still = clip.stillURL(colour: colour) {
			NativeUnlockStill(url: still)
		}
	}
}

/// One clip, muted, with no controls.
///
/// An `NSViewRepresentable` around `AVPlayerLayer` rather than SwiftUI's `VideoPlayer`,
/// which draws controls on hover — there is nothing here to control.
private struct NativeUnlockPlayer: NSViewRepresentable {

	let url: URL
	let looping: Bool
	let active: Bool

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeNSView(context: Context) -> NSView {
		let view = PlayerHostingView()
		view.wantsLayer = true

		let layer = AVPlayerLayer()
		layer.videoGravity = .resizeAspect
		// No autoresizing. The layer is created while the view's bounds are still zero, and
		// CALayer's autoresizing worked from that zero-sized base: every subsequent layout
		// pass nudged it a pixel larger, and it never came back down. Because an NSView does
		// not clip its sublayers, a layer that had outgrown its view drew the mark oversized
		// and outside the frame SwiftUI laid it out at — which is what made the mark jump up
		// and to the right the moment a caption arrived, since a caption arriving is a burst
		// of layout passes. The frame is pinned on every layout instead (see
		// `PlayerHostingView.layout()`), so it can only ever equal the view.
		layer.frame = view.bounds
		view.layer?.addSublayer(layer)

		context.coordinator.layer = layer
		context.coordinator.load(url: url, looping: looping)
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		let coordinator = context.coordinator
		if coordinator.url != url || coordinator.looping != looping {
			coordinator.load(url: url, looping: looping)
		}
		// Paused, never torn down. The panel goes compact between phases, and a rebuild
		// on every one of those would restart the clip from frame zero each time.
		if active { coordinator.player?.play() } else { coordinator.player?.pause() }
	}

	/// Holds the player, its looper, and the layer they draw into.
	///
	/// Without a strong reference to the looper it is collected as soon as `makeNSView`
	/// returns and the clip plays exactly once.
	final class Coordinator {
		var player: AVQueuePlayer?
		var looper: AVPlayerLooper?
		var layer: AVPlayerLayer?
		var url: URL?
		var looping: Bool?

		func load(url: URL, looping: Bool) {
			teardown()
			self.url = url
			self.looping = looping

			let player = AVQueuePlayer()
			player.isMuted = true
			// Nothing on the lock screen makes a sound, and a player that ducks the user's
			// music in order to play silence is a thing real apps do.
			player.audiovisualBackgroundPlaybackPolicy = .pauses

			if looping {
				// A looper rather than seeking on `didPlayToEndTime`: the notification
				// approach leaves a frame or two of nothing at the seam, which on a
				// three-second idle loop is a stutter every three seconds.
				looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
			} else {
				// Pause on the last frame rather than cutting to black. The success clip
				// ends on the tick and the failure clip on the mark dismissing itself,
				// and both endings are the part worth reading.
				player.actionAtItemEnd = .pause
				player.insert(AVPlayerItem(url: url), after: nil)
			}

			self.player = player
			layer?.player = player
			player.play()
		}

		private func teardown() {
			looper?.disableLooping()
			looper = nil
			player?.pause()
			player?.removeAllItems()
			player = nil
			layer?.player = nil
		}
	}
}

/// Hosts the player layer and pins it to the view on every layout pass.
///
/// Pinning rather than autoresizing is the whole point: autoresizing drifted a pixel per
/// pass from the layer's zero-sized origin and left the mark drawing outside its frame.
private final class PlayerHostingView: NSView {
	override func layout() {
		super.layout()
		for sub in layer?.sublayers ?? [] {
			sub.frame = bounds
		}
	}
}

/// The mark's resting frame, for Reduce Motion and for a clip that will not load.
private struct NativeUnlockStill: View {
	let url: URL
	/// Loaded once, not on every body evaluation — this sits inside a `TimelineView`
	/// driven panel, and reading a PNG from the bundle per frame would be needless work.
	@State private var image: NSImage?

	init(url: URL) {
		self.url = url
		_image = State(initialValue: NSImage(contentsOf: url))
	}

	var body: some View {
		if let image {
			Image(nsImage: image)
				.resizable()
				.interpolation(.high)
				.aspectRatio(1, contentMode: .fit)
				// The still is drawn on black, for the same reason the clips are.
				.blendMode(.screen)
		}
	}
}
