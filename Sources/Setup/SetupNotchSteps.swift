import AppKit
import SwiftUI

/// Setup, as a panel that is exactly as tall as whatever it is currently showing.
///
/// **The size comes from the content.** Three earlier attempts drove this the other way —
/// the window was given a height and the content was poured into it — and each failed the
/// same way: content and container disagreed, and the container won. First the panel grew
/// to 875pt because `NSHostingView` published a large intrinsic size. Then it filled the
/// screen because a step asked for `maxHeight: .infinity`. Both were patched, and a table
/// of hand-measured per-step heights was added, which is just the same mistake written
/// down: numbers that are correct until someone edits a string.
///
/// So the content measures itself and the window follows. A step is laid out at its natural
/// height, reports it, and the panel springs to match. Editing a sentence changes the panel
/// size automatically, and there is no number to keep in step with the copy.
enum SetupNotchStep: String, CaseIterable, Identifiable {
	case intro
	case permission
	case enrol
	case password
	case done

	var id: String { rawValue }
}

enum SetupNotchMetrics {
	/// Past roughly 400 a panel stops reading as something the notch produced and starts
	/// reading as a window that happens to be near the top of the screen.
	static let width: CGFloat = 372

	/// One spring, used by the window and by the content, so the panel changing shape is a
	/// single movement rather than two things animating at once in slight disagreement.
	static let morph = Animation.spring(response: 0.44, dampingFraction: 0.82)
	/// The same curve expressed for `NSAnimationContext`, which has no springs.
	static let morphDuration: TimeInterval = 0.44

	static let hover = Animation.easeOut(duration: 0.14)
	static let horizontalPadding: CGFloat = 24
	static let verticalPadding: CGFloat = 20
}

// MARK: - Measuring

/// Carries a step's natural height up to the controller.
struct SetupPanelHeightKey: PreferenceKey {
	static let defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}

extension View {
	/// Reports the view's laid-out height. Used once, around the step content, so the
	/// window can be sized from what is actually on screen rather than from a guess.
	func measuringPanelHeight() -> some View {
		background {
			GeometryReader { geometry in
				Color.clear.preference(key: SetupPanelHeightKey.self, value: geometry.size.height)
			}
		}
	}
}

// MARK: - Model

@Observable
@MainActor
final class SetupNotchModel {

	private(set) var plan: [SetupNotchStep] = []
	private(set) var step: SetupNotchStep = .intro

	init() {
		plan = Self.makePlan()
	}

	/// Only the steps this Mac needs. On a Mac with the password stored and Accessibility
	/// granted this is intro → enrol → done, and enrolment is the only one that asks
	/// anything of you.
	private static func makePlan() -> [SetupNotchStep] {
		var steps: [SetupNotchStep] = [.intro]
		if !AXIsProcessTrusted() { steps.append(.permission) }
		steps.append(.enrol)
		if !PasswordVault.hasPassword { steps.append(.password) }
		steps.append(.done)
		return steps
	}

	var progress: (index: Int, count: Int)? {
		guard let index = plan.firstIndex(of: step) else { return nil }
		return (index, plan.count)
	}

	func advance() {
		guard let index = plan.firstIndex(of: step), index + 1 < plan.count else { return }
		withAnimation(SetupNotchMetrics.morph) { step = plan[index + 1] }
	}

	/// Granting Accessibility happens in System Settings, so the step cannot advance on a
	/// button press — it has to notice the answer changed.
	func refreshPlan() {
		plan = Self.makePlan()
		if !plan.contains(step) {
			withAnimation(SetupNotchMetrics.morph) { step = plan.first ?? .done }
		}
	}
}

// MARK: - Controls

/// The panel's button, with the hover and press states the old one had none of.
///
/// Both are transform and opacity only, and both are small: 1.02 on hover, 0.97 on press.
/// A control in a 372pt panel that jumps 10% is a control that looks broken. The press
/// state is faster than the hover one because it is confirming something you just did,
/// where the hover is only acknowledging that you are near it.
struct SetupNotchButton: View {

	let title: String
	var isProminent = true
	var isEnabled = true
	let action: () -> Void

	@State private var hovering = false
	@State private var pressing = false

	var body: some View {
		Text(title)
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(isProminent ? Color.black : Color.white)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
			.background {
				Capsule()
					.fill(fill)
			}
			.scaleEffect(pressing ? 0.97 : (hovering ? 1.02 : 1))
			.opacity(isEnabled ? 1 : 0.35)
			.animation(SetupNotchMetrics.hover, value: hovering)
			.animation(.easeOut(duration: 0.09), value: pressing)
			.contentShape(Capsule())
			.onHover { hovering = isEnabled && $0 }
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { _ in if isEnabled { pressing = true } }
					.onEnded { _ in
						pressing = false
						if isEnabled { action() }
					}
			)
			.allowsHitTesting(isEnabled)
	}

	private var fill: Color {
		if isProminent {
			return hovering ? .white : .white.opacity(0.92)
		}
		return .white.opacity(hovering ? 0.20 : 0.13)
	}
}

/// The quiet secondary action — "Not now", "Skip". Underlined on hover rather than
/// changing colour, because at 12pt on black there is nowhere lighter for it to go.
struct SetupNotchQuietButton: View {

	let title: String
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Text(title)
			.font(.system(size: 12))
			.foregroundStyle(.white.opacity(hovering ? 0.85 : 0.5))
			.animation(SetupNotchMetrics.hover, value: hovering)
			.contentShape(Rectangle())
			.onHover { hovering = $0 }
			.onTapGesture(perform: action)
	}
}

/// A row of dots, one per step, filling as the flow proceeds.
///
/// Small enough to ignore and specific enough to answer "how much more of this is there",
/// which is the only question a progress indicator in a five-step flow needs to answer.
struct SetupNotchProgress: View {

	let index: Int
	let count: Int

	var body: some View {
		HStack(spacing: 5) {
			ForEach(0..<count, id: \.self) { position in
				Capsule()
					.fill(.white.opacity(position <= index ? 0.85 : 0.22))
					.frame(width: position == index ? 14 : 5, height: 5)
			}
		}
		.animation(SetupNotchMetrics.morph, value: index)
	}
}
