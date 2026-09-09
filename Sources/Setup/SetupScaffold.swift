import SwiftUI

/// The shape every setup screen has.
///
/// Setup used to be six independent `VStack`s that each chose their own spacing, their
/// own figure size and their own idea of where the buttons sat. Individually they were
/// fine; in sequence they read as six dialogs shown in a row, because the title moved a
/// few points between every one of them and nothing carried across the cut.
///
/// So the layout lives here and the screens supply only their content. Four bands, fixed
/// for the whole flow: a chrome strip, a figure, the words, the actions. The figure band
/// keeps its height whether or not a screen fills it, which is what stops the title
/// walking up and down the window as you go.
///
/// Motion is the other half. Each band arrives on `Theme.Motion.standard` with a short
/// stagger — blur out, a little low, transparent, then settled — so a new screen resolves
/// top-down rather than appearing all at once. The stagger is what reads as "designed";
/// the individual values are barely perceptible on their own.
struct SetupScaffold<Figure: View, Detail: View, Actions: View>: View {

	/// Which screen this is, for the progress row. Nil hides the row entirely — the
	/// welcome and the finish are the two ends of the flow and neither is a step you are
	/// "on".
	var position: SetupPosition?
	var title: String
	/// The one line under the title. Empty renders the space anyway, so screens whose
	/// caption comes and goes (the capture) don't shuffle their own buttons.
	var message: String
	/// Set on the welcome, where the title is the whole design.
	var isHero = false
	/// Height reserved for the figure. The capture ring needs far more than an SF Symbol.
	var figureHeight: CGFloat = 132
	var onBack: (() -> Void)?
	var onClose: (() -> Void)?
	/// Shows the user's wallpaper across the top of the window, fading out.
	///
	/// Set on the opening screen. A first screen that is an app icon on a flat ground is a
	/// splash screen; a product page puts the thing you are about to use on something real
	/// and lets it fall away. The picture is the wallpaper of the machine being set up —
	/// which is the one image guaranteed to be relevant and never needs shipping.
	var showsHero = false
	@ViewBuilder var figure: Figure
	/// Anything a screen needs between its message and its buttons — a list of facts, a
	/// password field. Arrives on the same clock as the rest, one beat later.
	@ViewBuilder var detail: Detail
	@ViewBuilder var actions: Actions

	@State private var hasAppeared = false

	var body: some View {
		VStack(spacing: 0) {
			chrome

			Spacer(minLength: 8)

			figure
				.frame(height: figureHeight)
				.entrance(hasAppeared, delay: 0)

			Spacer().frame(height: isHero ? 26 : 30)

			VStack(spacing: 10) {
				Text(title)
					.font(isHero ? Typography.setupHero : Typography.setupTitle)
					.tracking(isHero ? -0.8 : -0.2)
					.multilineTextAlignment(.center)
					.contentTransition(.opacity)

				Text(message)
					.font(Typography.setupBody)
					.foregroundStyle(Theme.setupSecondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
					// A measure, not a margin.
					//
					// The window is 880 wide now, and a centred paragraph allowed to use all
					// of it runs to about 110 characters a line — roughly twice what is
					// comfortable. Apple's own onboarding copy sits in a column regardless of
					// how wide the sheet is, for the same reason every book does.
					.frame(maxWidth: isHero ? 620 : 520)
			}
			.entrance(hasAppeared, delay: 0.05)

			detail
				.entrance(hasAppeared, delay: 0.1)

			// A real gap before the actions — and a ceiling on it.
			//
			// The floor came first: at `minLength: 12` the screens that nearly fill the
			// window put the primary button almost against the content above it, which reads
			// as part of that content rather than as the way out of it.
			//
			// The ceiling is the opposite failure, and it was the visible one. Two flexible
			// spacers in a stack split the slack evenly, so on the welcome screen — one mark
			// and two lines of copy in a 624pt window — roughly 150pt of nothing opened up
			// between the message and Continue, and the button drifted free of the sentence
			// it answers. Capped, the surplus goes to the top spacer instead, which is where
			// it belongs: the top of this window is the wallpaper fading out, so space there
			// is the design rather than an absence of one.
			Spacer(minLength: 40)
				.frame(maxHeight: 120)

			VStack(spacing: 14) {
				actions
			}
			.entrance(hasAppeared, delay: 0.15)
		}
		.padding(.horizontal, 52)
		.padding(.bottom, 44)
		.background(alignment: .top) {
			if showsHero { HeroWallpaper() }
		}
		// One frame late, so the arrival plays *into* the window rather than being
		// already finished by the time the step transition uncovers it.
		.task {
			try? await Task.sleep(for: .milliseconds(20))
			withAnimation(Theme.Motion.standard) { hasAppeared = true }
		}
	}

	/// Back, progress, close — the strip that persists across every screen.
	///
	/// It is the only thing in setup that does not animate in, and that is the point: a
	/// fixed frame around content that moves is what tells you the screens belong to one
	/// window rather than replacing each other.
	private var chrome: some View {
		ZStack {
			HStack {
				chromeButton("chevron.backward", action: onBack)
				Spacer()
				chromeButton("xmark", action: onClose)
			}
		}
		.frame(height: 30)
		// Clear of the traffic lights. With the title bar hidden they sit over the
		// content at the top-left, and a back chevron underneath them is both unclickable
		// and — worse — briefly visible through them.
		.padding(.top, 26)
	}

	/// Nil actions render as empty space rather than a disabled control, so the strip
	/// keeps its height and the close button keeps its corner.
	@ViewBuilder
	private func chromeButton(_ symbol: String, action: (() -> Void)?) -> some View {
		if let action {
			// Glass circles, like every other round control macOS 26 draws.
			//
			// These were `.buttonStyle(.plain)`: a bare chevron and a bare cross with a 26pt
			// hit area and no fill, no hover and no press state. On a dark, mostly-empty
			// screen that is two grey marks in the corners — not obviously controls at all,
			// and the only two things in setup you can click that gave nothing back when the
			// pointer arrived. The system's glass button is the same shape the window's own
			// traffic lights are, a few points to their right.
			Button(action: action) {
				Image(systemName: symbol)
					.font(.system(size: 12, weight: .semibold))
					.frame(width: 26, height: 26)
					.contentShape(.circle)
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.tint(Theme.setupTertiary)
		} else {
			Color.clear.frame(width: 26, height: 26)
		}
	}
}

extension SetupScaffold where Detail == EmptyView {
	/// For the screens whose words are the whole middle of the window.
	init(
		position: SetupPosition? = nil,
		title: String,
		message: String,
		isHero: Bool = false,
		figureHeight: CGFloat = 132,
		onBack: (() -> Void)? = nil,
		onClose: (() -> Void)? = nil,
		showsHero: Bool = false,
		@ViewBuilder figure: () -> Figure,
		@ViewBuilder actions: () -> Actions
	) {
		self.init(
			position: position,
			title: title,
			message: message,
			isHero: isHero,
			figureHeight: figureHeight,
			onBack: onBack,
			onClose: onClose,
			showsHero: showsHero,
			figure: figure,
			detail: { EmptyView() },
			actions: actions
		)
	}
}

/// Where a screen sits in the flow.
struct SetupPosition: Equatable {
	var index: Int
	var count: Int
}

/// The progress row.
///
/// Dashes rather than dots. A row of dots is the iOS page-control idiom and carries its
/// promise — that the pages are peers you can swipe between — which is wrong here: these
/// steps are ordered, each one depends on the last, and you cannot go and look at the
/// fourth. A filling row of short rules says sequence instead of set, and it is quieter
/// at the top of a window that is mostly camera.
struct SetupProgress: View {
	let position: SetupPosition

	var body: some View {
		HStack(spacing: 5) {
			ForEach(0..<position.count, id: \.self) { index in
				Capsule(style: .continuous)
					.fill(.white)
					.opacity(index <= position.index ? 0.85 : 0.18)
					.frame(width: index == position.index ? 16 : 7, height: 3)
			}
		}
		.animation(Theme.Motion.standard, value: position)
		.accessibilityElement()
		.accessibilityLabel("Step \(position.index + 1) of \(position.count)")
	}
}

/// The app's arrival: out of focus, a little low, transparent — then settled.
///
/// A modifier struct rather than a bare `View` extension so it can read the environment.
/// It needs to, because this is the app's largest piece of motion — every block on every
/// setup screen travels and defocuses on the way in — and "Reduce Motion" is a request not
/// to do exactly that.
///
/// Reduced, it keeps the fade and drops the movement and the blur, which is what Apple's
/// own guidance asks for: the element still announces itself arriving, it just does not
/// travel to do it. The delay stays, so the stagger survives and the screen still assembles
/// in order rather than all at once.
private struct Entrance: ViewModifier {
	let hasAppeared: Bool
	let delay: Double

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	func body(content: Content) -> some View {
		content
			.blur(radius: hasAppeared || reduceMotion ? 0 : Theme.Motion.entryBlur)
			.offset(y: hasAppeared || reduceMotion ? 0 : Theme.Motion.rise)
			.opacity(hasAppeared ? 1 : 0)
			.animation(Theme.Motion.standard.delay(delay), value: hasAppeared)
	}
}

extension View {
	/// Written as a modifier rather than a `transition` because it has to run when the
	/// step's own cross-fade has already put the view on screen. A transition would be
	/// consumed by that outer change and never play.
	func entrance(_ hasAppeared: Bool, delay: Double) -> some View {
		modifier(Entrance(hasAppeared: hasAppeared, delay: delay))
	}
}


/// The user's wallpaper across the top of the opening screen, falling away to nothing.
///
/// Two thirds of the window tall, and gone well before the copy starts — the picture is
/// there to place the app on this machine, not to sit behind text. The fade is a mask
/// rather than a gradient drawn on top, so it works against whatever ground the window
/// has without needing to know its colour.
///
/// The exposure follows the appearance rather than being fixed. A wallpaper bright enough
/// to be pleasant in light mode is a glare in dark mode, and the same picture dimmed for
/// dark mode is a grey smear in light — so dark gets it darkened and light gets it lifted,
/// which is what "matches the system" has to mean for a photograph.
struct HeroWallpaper: View {

	@Environment(\.colorScheme) private var colorScheme
	@State private var wallpaper = DesktopWallpaper.shared

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				if let image = wallpaper.image {
					Image(nsImage: image)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.frame(width: proxy.size.width, height: proxy.size.height * 0.66)
						.clipped()
						.overlay {
							colorScheme == .dark
								? Color.black.opacity(0.42)
								: Color.white.opacity(0.34)
						}
						.mask(
							LinearGradient(
								stops: [
									.init(color: .white, location: 0),
									.init(color: .white.opacity(0.85), location: 0.45),
									.init(color: .clear, location: 1),
								],
								startPoint: .top,
								endPoint: .bottom
							)
						)
				}
			}
			.frame(width: proxy.size.width, alignment: .top)
		}
		.allowsHitTesting(false)
		.ignoresSafeArea()
	}
}
