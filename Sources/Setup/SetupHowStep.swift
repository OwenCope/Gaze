import AVFoundation
import AppKit
import SwiftUI

/// What Gaze actually does, before it asks for anything.
///
/// Three facts, one screen. Other face-unlock apps split these — how it works on one
/// screen, where the password lives on another — and the split is what makes an
/// onboarding feel long. They are the same question asked twice: someone who wants to
/// know that macOS still performs the unlock wants to know where the password sits, and
/// they want both answers before they hand one over, not one screen apart.
///
/// It sits between the welcome and the camera because this is the last screen before
/// Gaze starts asking. Trust is cheap to establish here and expensive to repair after a
/// permission prompt has already appeared.
struct SetupHowStep: View {
	var position: SetupPosition?
	var onContinue: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)? = nil
	var movementCount = 2

	var body: some View {
		SetupScaffold(
			position: position,
			title: "How Gaze unlocks your Mac",
			message: "Look at the camera, then follow \(movementCount == 1 ? "one small movement" : "two small movements").\nGaze enters your saved login password after verification.",
			figureHeight: 0,
			onBack: onBack,
			onClose: onClose
		) {
			EmptyView()
		} detail: {
			VStack(alignment: .leading, spacing: 24) {
				fact("person.crop.rectangle", "Recognition stays on your Mac",
					"Gaze uses the built-in camera. Face recognition runs on this device, not in the cloud.")
				fact("lock", "You’re trusting Gaze with your login",
					"To unlock, Gaze needs an encrypted, recoverable copy of your Mac password. This is not Apple Face ID.")
				fact("keyboard", "Your usual way in stays available",
					"Keep using your password or Touch ID whenever available. You can pause Gaze at any time.")
			}
			.frame(maxWidth: 440)
			.padding(.top, 32)
		} actions: {
			SetupButton(action: onContinue)
		}
	}

	private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
		HStack(alignment: .top, spacing: 18) {
			Image(systemName: symbol)
				.font(.system(size: 23, weight: .regular))
				.foregroundStyle(Theme.setupSecondary)
				.frame(width: 30, height: 30)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 5) {
				Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
				Text(detail)
					.font(.system(size: 13))
					.foregroundStyle(Theme.setupSecondary)
					.fixedSize(horizontal: false, vertical: true)
					.lineSpacing(2)
			}
		}
		.accessibilityElement(children: .combine)
	}

	static let facts: [SetupFact] = [
		SetupFact(
			art: .unlock,
			title: "macOS does the unlocking",
			detail:
				"Gaze recognises your face and enters your login password for you. "
				+ "The system still performs the unlock itself."
		),
		SetupFact(
			art: .keychain,
			title: "Your password stays here",
			detail:
				"It is kept in this Mac's keychain — never synced, never logged, "
				+ "never sent anywhere."
		),
		SetupFact(
			art: .onDevice,
			title: "Your face never leaves",
			detail:
				"Recognition runs entirely on this Mac. No image is stored and "
				+ "nothing is uploaded."
		),
	]
}

struct SetupFact: Identifiable, Equatable {
	var art: SetupFactArt.Kind
	var title: String
	var detail: String
	var id: String { title }
}

/// The picture on a fact card: a Mac, with something on its screen.
///
/// Every card is the same machine on the same ground, and only what is on the display
/// changes. That is the whole trick behind a set of Apple feature graphics — one shape
/// repeated, so the three read as three facts about one product rather than three
/// unrelated pictures that happen to be the same size.
///
/// What goes on the screen is a screenshot where the claim is something you can see
/// happening (the lock screen recognising you; recognition running), and composed icons
/// where it is not. "Your password never goes to iCloud" is an absence — there is nothing
/// to photograph, and a capture of a settings row reading *Stored* is a picture of text.
/// The real Passwords icon beside a struck-out iCloud says it at a glance.
///
/// Screenshots live in `Resources/Art/<name>.png` and are optional: each falls back to a
/// composed screen, so a fresh checkout builds and still looks deliberate.
struct SetupFactArt: View {
	enum Kind { case unlock, keychain, onDevice }

	let kind: Kind

	private let width: CGFloat = 384
	private let height: CGFloat = 240

	var body: some View {
		// The picture, rounded, on a shadow. No device frame.
		//
		// Three attempts at putting this inside a drawn MacBook — two hand-drawn, one built
		// on the `macbook` SF Symbol — all read as a cheap mockup, and for the same reason:
		// at 360pt the frame is thicker than anything on the screen inside it, so the eye
		// lands on a grey plastic border instead of the content. The reference this was
		// modelled on had no device in it either. A rounded rectangle and a real shadow is
		// the whole effect.
		screenContent
			.frame(width: width, height: height)
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay {
				// The edge. Without it a bright wallpaper dissolves into the black window
				// behind the card and the picture loses its shape.
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.strokeBorder(.white.opacity(0.16), lineWidth: 1)
			}
			.shadow(color: .black.opacity(0.6), radius: 26, y: 14)
	}

	// MARK: - What is on the display

	@ViewBuilder
	private var screenContent: some View {
		// A clip if there is one, then a still, then the drawn fallback.
		//
		// The unlock is an animation — the panel appears, scans, ticks — and a frozen
		// frame of it is a card that has thrown away the only interesting thing it had.
		// Where a claim moves, the card moves.
		if let movie = Self.movie(named: screenshotName) {
			LoopingVideo(url: movie)
		} else if let shot = Self.image(named: screenshotName) {
			Image(nsImage: shot)
				.resizable()
				.aspectRatio(contentMode: .fill)
		} else {
			composedScreen
		}
	}

	static func movie(named name: String) -> URL? {
		guard !name.isEmpty else { return nil }
		return Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Art")
	}

	/// Empty means "compose it". The old `how-*` recordings showed an earlier Settings
	/// layout, a beige wallpaper and a real account name, so unlock uses the current Pro
	/// Black tour art and the other two draw their subject live from the app's own parts.
	private var screenshotName: String {
		switch kind {
		case .unlock: return "tour-how-unlock"
		case .keychain, .onDevice: return ""
		}
	}

	/// A different picture of a different thing, per card.
	///
	/// The version before this gave both composed cards the same wallpaper and changed only
	/// the glyph on top — three cards that are meant to show three things, showing one
	/// picture three times. That is worse than the unreadable screenshots it replaced: at
	/// least those were distinct.
	///
	/// A screenshot is not the answer either. A card is 384pt wide and a Settings pane is
	/// 700pt of 11pt type; shrinking one into the other leaves a grey rectangle with the
	/// *shape* of text in it, and cropping to a row cuts the claim in half, because on both
	/// of these rows the claim lives at both ends — "Account password" on the left, "Stored,
	/// encrypted in the Secure Enclave" and its badge on the right.
	///
	/// So each card draws its subject at card scale, from the app's own parts:
	///
	///   - **keychain** — the Settings row itself, redrawn. Legible because it is composed
	///     at the size it is shown at rather than photographed at three times that size.
	///   - **onDevice** — the enrolment ring, the one piece of UI that is unmistakably this
	///     app, filling the way it does during a capture.
	@ViewBuilder
	private var composedScreen: some View {
		switch kind {
		case .keychain: StoredPasswordRowArt()
		case .onDevice: EnrolmentRingArt()
		case .unlock: backdrop
		}
	}

	// MARK: - Backdrop

	/// `Resources/Art/backdrop.png`; drop a different image in and every card changes
	/// together. A gradient stands in when it is missing.
	@ViewBuilder
	private var backdrop: some View {
		if let image = Self.image(named: "lockscreen-base") ?? Self.image(named: "backdrop") {
			Image(nsImage: image)
				.resizable()
				.aspectRatio(contentMode: .fill)
		} else {
			LinearGradient(
				colors: [
					Color(red: 0.16, green: 0.42, blue: 0.72),
					Color(red: 0.09, green: 0.20, blue: 0.42),
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		}
	}

	/// Decoded once and kept. `SetupFactCarousel` holds all three cards in the layout at
	/// all times, so without this the images would decode on every tick of the progress
	/// bar — thirty times a second, three times over.
	private static let cache = NSCache<NSString, NSImage>()

	static func image(named name: String) -> NSImage? {
		guard !name.isEmpty else { return nil }
		if let hit = cache.object(forKey: name as NSString) { return hit }
		guard
			let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art"),
			let image = NSImage(contentsOf: url)
		else { return nil }
		cache.setObject(image, forKey: name as NSString)
		return image
	}
}

/// One fact at a time, cycling.
///
/// Three rows stacked down the window said all of this at once and none of it landed —
/// the eye takes the shape of a list and moves on. Shown one at a time each fact gets the
/// middle of the window to itself, and the screen has something to do while it is being
/// read, which is the difference between a page and a product.
///
/// The bars underneath fill over the dwell rather than sitting as inert dots, so the
/// screen says how long it intends to hold before it moves — a carousel that advances
/// with no warning reads as a page that changed on its own. They are also the control:
/// clicking one jumps to that fact and hovering anywhere holds the current one, because a
/// timed carousel that cannot be stopped is a carousel that outruns whoever is reading it.
///
/// The timer is a plain accumulator ticked 30 times a second rather than an animation
/// with a completion. A completion-driven version has to be cancelled and rebuilt every
/// time it is paused or jumped, and desynchronises from the bar it is supposed to be
/// driving; adding to a number does neither.
struct SetupFactCarousel: View {
	let facts: [SetupFact]

	/// When the current fact started being shown. Progress is derived from this rather
	/// than accumulated, which is what makes the bar smooth — see `bars`.
	@State private var startedAt = Date()
	@State private var index = 0
	@State private var isHovering = false
	/// How far through the dwell we were when the pointer arrived, so hovering holds
	/// rather than restarts.
	@State private var heldAt: Double = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private let dwell: Double = 4.5

	var body: some View {
		// Reduced motion gets the list. The carousel's whole mechanism is timed movement,
		// and there is no way to honour "don't move things" and still cycle — so it stops
		// being a carousel rather than becoming a worse one.
		if reduceMotion {
			VStack(alignment: .leading, spacing: 20) {
				ForEach(facts) { fact in
					row(fact)
				}
			}
			.padding(.horizontal, 6)
		} else {
			carousel
		}
	}

	private var carousel: some View {
		VStack(spacing: 34) {
			cards
			bars
		}
		.onHover { hovering in
			if hovering {
				heldAt = progress * dwell
			} else {
				// Resume from where it was held, by moving the start back that far.
				startedAt = Date().addingTimeInterval(-heldAt)
			}
			isHovering = hovering
		}
		.task {
			// Only the *advance* runs on a timer, and it only has to be accurate to a
			// frame or two. The bar's motion is not driven from here — that is the whole
			// point of the split.
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(50))
				guard !isHovering, Date().timeIntervalSince(startedAt) >= dwell else { continue }
				advance(to: (index + 1) % facts.count)
			}
		}
	}

	/// One card at a time, replaced rather than cross-faded in place.
	///
	/// `.id(index)` with an asymmetric transition, so the outgoing card leaves in the
	/// direction of travel and the incoming one arrives from the other side. Holding all
	/// three in a `ZStack` and toggling opacity — the previous version — meant SwiftUI saw
	/// no insertion or removal at all, so there was nothing for it to animate and the cards
	/// simply swapped.
	private var cards: some View {
		ZStack {
			card(facts[index])
				.id(index)
				.transition(
					.asymmetric(
						insertion: .offset(x: 34).combined(with: .opacity),
						removal: .offset(x: -34).combined(with: .opacity)
					)
				)
		}
		.frame(height: 308)
		// Clipped, or the sliding cards are visible outside the card area on their way
		// in and out.
		.clipped()
	}

	private func advance(to next: Int) {
		withAnimation(Theme.Motion.standard) { index = next }
		startedAt = Date()
		heldAt = 0
	}

	// MARK: - Progress

	/// How far through the current fact we are, 0…1.
	private var progress: Double {
		min(Date().timeIntervalSince(startedAt) / dwell, 1)
	}

	/// One bar per fact: filled behind, filling on the current one, empty ahead.
	///
	/// Driven by `TimelineView(.animation)`, which redraws in step with the display rather
	/// than on a timer of ours. The previous version ticked a counter thirty times a second
	/// and animated each step, so the fill advanced in thirty visible jumps per second on a
	/// 120Hz screen — which is exactly the stepping you can see. Reading elapsed time from
	/// a start date and drawing it every frame has no steps in it at all.
	///
	/// Real glass on the track. The glow that used to sit at the leading edge is gone — a
	/// bloom on a 5pt capsule is decoration, and Gaze settled that argument when the
	/// enrolment ring's tick lost its glow — but the material stays, because a glass track
	/// under a solid fill is the thing that reads as Apple's.
	private var bars: some View {
		TimelineView(.animation(paused: isHovering)) { _ in
			HStack(spacing: 7) {
				ForEach(Array(facts.enumerated()), id: \.element.id) { offset, fact in
					Button { advance(to: offset) } label: {
						bar(offset: offset)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(fact.title)
				}
			}
		}
	}

	@ViewBuilder
	private func bar(offset: Int) -> some View {
		Capsule(style: .continuous)
			.fill(.white.opacity(0.12))
			.frame(width: 38, height: 5)
			.overlay(alignment: .leading) {
				GeometryReader { proxy in
					Capsule(style: .continuous)
						.fill(.white.opacity(0.95))
						.frame(width: proxy.size.width * fill(for: offset))
				}
			}
			.clipShape(Capsule(style: .continuous))
			.glassEffect(.regular, in: .capsule)
			// A 5pt-tall click target is not a click target. Widen what can be hit without
			// widening what can be seen.
			.contentShape(Rectangle().inset(by: -9))
	}

	private func card(_ fact: SetupFact) -> some View {
		VStack(spacing: 18) {
			SetupFactArt(kind: fact.art)

			Text(fact.title)
				.font(.system(.title3, weight: .semibold))
				.multilineTextAlignment(.center)

			Text(fact.detail)
				.font(Typography.setupBody)
				.foregroundStyle(Theme.setupSecondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 26)
		}
		.frame(maxWidth: .infinity)
	}

	/// The reduced-motion list has no room for a scene, so it names the category instead.
	private func rowSymbol(_ art: SetupFactArt.Kind) -> String {
		switch art {
		case .unlock: return "lock.open.fill"
		case .keychain: return "key.fill"
		case .onDevice: return "eye.slash.fill"
		}
	}

	private func fill(for offset: Int) -> Double {
		if offset < index { return 1 }
		if offset > index { return 0 }
		return progress
	}

	/// The reduced-motion list — three rows, no timer, no movement.
	private func row(_ fact: SetupFact) -> some View {
		HStack(alignment: .top, spacing: 15) {
			Image(systemName: rowSymbol(fact.art))
				.font(.system(size: 16, weight: .semibold))
				.foregroundStyle(Theme.setupSecondary)
				.frame(width: 24, alignment: .center)
				.padding(.top, 2)

			VStack(alignment: .leading, spacing: 2) {
				Text(fact.title)
					.font(Typography.setupBody.weight(.semibold))
				Text(fact.detail)
					.font(Typography.setupBody)
					.foregroundStyle(Theme.setupSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}


/// A muted clip, looping, with no controls.
///
/// `AVPlayerLooper` rather than watching for `didPlayToEndTime` and seeking back to zero:
/// the notification approach leaves a visible stutter at the seam — a frame or two of
/// nothing while the seek completes — which on an eight-second loop is noticeable every
/// eight seconds. The looper keeps a second item queued and cuts to it.
///
/// An `NSViewRepresentable` around `AVPlayerLayer` rather than SwiftUI's `VideoPlayer`,
/// which draws playback controls that appear on hover. There is nothing here to control.
struct LoopingVideo: NSViewRepresentable {

	let url: URL

	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		view.wantsLayer = true

		let player = AVQueuePlayer()
		player.isMuted = true
		// Nothing else on this screen makes a sound, and a card that ducks the user's music
		// to play silence is a real thing that real apps do.
		player.audiovisualBackgroundPlaybackPolicy = .pauses

		let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
		context.coordinator.player = player
		context.coordinator.looper = looper

		let layer = AVPlayerLayer(player: player)
		layer.videoGravity = .resizeAspectFill
		layer.frame = view.bounds
		layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
		view.layer?.addSublayer(layer)

		player.play()
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {}

	func makeCoordinator() -> Coordinator { Coordinator() }

	/// Holds the player and the looper. Without a strong reference the looper is collected
	/// as soon as `makeNSView` returns and the clip plays exactly once.
	final class Coordinator {
		var player: AVQueuePlayer?
		var looper: AVPlayerLooper?
	}
}

/// The Settings row that holds the claim, drawn at the size the card shows it.
///
/// A photograph of this row is illegible on a 384pt card; a drawing of it is not, because
/// it is composed at the size it is displayed. It is the same row, in the same order, with
/// the same words — a reconstruction rather than a decoration, so it stays true if someone
/// goes looking for it in Settings.
struct StoredPasswordRowArt: View {
	var body: some View {
		ZStack {
			// The window ground rather than the wallpaper: this is a picture of a settings
			// window, and settings windows are not translucent over your desktop here.
			Color(red: 0.09, green: 0.09, blue: 0.10)

			VStack(alignment: .leading, spacing: 0) {
				Text("Use Gaze for")
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.white.opacity(0.55))
					.padding(.bottom, 8)

				HStack(spacing: 12) {
					Image(systemName: "key.fill")
						.font(.system(size: 15))
						.foregroundStyle(.white.opacity(0.75))
						.frame(width: 26, height: 26)
						.background {
							RoundedRectangle(cornerRadius: 7, style: .continuous)
								.fill(.white.opacity(0.09))
						}

					VStack(alignment: .leading, spacing: 1) {
						Text("Account password")
							.font(.system(size: 14))
							.foregroundStyle(.white)
						Text("Encrypted with a key from this Mac's Secure Enclave")
							.font(.system(size: 12))
							.foregroundStyle(.white.opacity(0.6))
					}

					Spacer(minLength: 16)

					HStack(spacing: 5) {
						Image(systemName: "checkmark.circle.fill")
							.font(.system(size: 12))
							.foregroundStyle(Theme.faceID)
						Text("Stored")
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(Theme.faceID)
					}
				}
				.padding(14)
				.background {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(.white.opacity(0.06))
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.strokeBorder(.white.opacity(0.08), lineWidth: 1)
				}
			}
			.padding(.horizontal, 26)
		}
	}
}

/// The enrolment ring, filling.
///
/// The one piece of UI that could only be this app — nothing else on a Mac looks like it.
/// It runs on a loop rather than sitting full, because a completed ring says "this already
/// happened" and the card is describing something that happens on your machine, repeatedly.
///
/// No camera. The preview circle is the app's own mark instead, which keeps the card
/// honest — a face in there would be a face that never leaves someone's Mac, printed inside
/// a downloadable binary.
struct EnrolmentRingArt: View {

	private static let tickCount = 44

    @State private var filled = 0

	var body: some View {
		ZStack {
			Color(red: 0.05, green: 0.05, blue: 0.06)

			EnrollmentRing(
				covered: (0..<Self.tickCount).map { $0 < filled },
				currentAngle: (Double(filled) / Double(Self.tickCount)) * 2 * .pi - .pi / 2,
				isEngaged: filled > 0 && filled < Self.tickCount
			)
			.frame(width: 190, height: 190)

			Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
				.resizable()
				.frame(width: 86, height: 86)
				.clipShape(Circle())
		}
		.task {
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(90))
				withAnimation(.easeOut(duration: 0.16)) {
					filled = filled >= Self.tickCount ? 0 : filled + 1
				}
				if filled == Self.tickCount {
					try? await Task.sleep(for: .milliseconds(1400))
				}
			}
		}
	}
}
