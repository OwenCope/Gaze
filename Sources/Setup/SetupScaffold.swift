import SwiftUI

struct SetupScaffold<Figure: View, Detail: View, Actions: View>: View {
	var position: SetupPosition?
	var title: String
	var message: String
	var isHero = false
	var figureHeight: CGFloat = 112
	var onBack: (() -> Void)?
	var onClose: (() -> Void)?
	@ViewBuilder var figure: Figure
	@ViewBuilder var detail: Detail
	@ViewBuilder var actions: Actions

	var body: some View {
		VStack(spacing: 0) {
			chrome
			VStack(spacing: 0) {
				Spacer(minLength: 12)
				figure
					.frame(height: figureHeight)
					.padding(.bottom, figureHeight > 0 ? 20 : 0)
				VStack(spacing: 10) {
					Text(title)
						.font(.largeTitle.weight(.semibold).scaled(by: isHero ? 38.0 / 26.0 : 30.0 / 26.0))
						.tracking(-0.5)
						.foregroundStyle(.primary)
						.accessibilityAddTraits(.isHeader)
					Text(message)
						.font(Typography.setupBody)
						.foregroundStyle(Theme.setupSecondary)
						.lineSpacing(3)
						.fixedSize(horizontal: false, vertical: true)
						.frame(maxWidth: 460)
				}
				.multilineTextAlignment(.center)
				detail
				Spacer(minLength: 20)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			VStack(spacing: 12) {
				actions
			}
		.frame(maxWidth: .infinity)
		.frame(minHeight: 80, alignment: .top)
		.padding(.top, 16)
			Group {
				if let position {
					SetupProgress(position: position)
				} else {
					Color.clear
				}
			}
			.frame(height: 28)
		}
		.padding(.horizontal, 32)
		.padding(.bottom, 16)
	}

	private var chrome: some View {
		HStack {
			navigationButton("Back", symbol: "chevron.left", action: onBack)
			Spacer()
			Text("Gaze")
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(Theme.setupSecondary)
			Spacer()
			navigationButton("Close", symbol: "xmark", action: onClose)
		}
		.frame(height: 36)
		.padding(.top, 12)
	}

	@ViewBuilder
	private func navigationButton(_ label: String, symbol: String, action: (() -> Void)?) -> some View {
		if let action {
			Button(action: action) {
				Image(systemName: symbol)
					.font(.system(size: 12, weight: .semibold))
					.frame(width: 32, height: 32)
			}
			.buttonStyle(.glass(.clear))
			.buttonBorderShape(.circle)
			.accessibilityLabel(label)
			.help(label)
			.frame(width: 44)
		} else {
			Color.clear.frame(width: 44, height: 32)
		}
	}
}

extension SetupScaffold where Detail == EmptyView {
	init(
		position: SetupPosition? = nil,
		title: String,
		message: String,
		isHero: Bool = false,
		figureHeight: CGFloat = 112,
		onBack: (() -> Void)? = nil,
		onClose: (() -> Void)? = nil,
		@ViewBuilder figure: () -> Figure,
		@ViewBuilder actions: () -> Actions
	) {
		self.init(
			position: position, title: title, message: message, isHero: isHero,
			figureHeight: figureHeight, onBack: onBack, onClose: onClose,
			figure: figure, detail: { EmptyView() }, actions: actions
		)
	}
}

struct SetupPosition: Equatable {
	var index: Int
	var count: Int
}

struct SetupProgress: View {
	let position: SetupPosition

	var body: some View {
		// One step is not a sequence; saying "Step 1 of 1" only adds noise.
		if position.count > 1 { counter }
	}

	/// TourKit's own page dots, so setup reads as the same card as the tour.
	private var counter: some View {
		PageIndicator(totalPages: position.count, currentIndex: position.index)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Step \(position.index + 1) of \(position.count)")
	}
}
