import AppKit
import SwiftUI

/// Setup as a sequence of small panels, each the size it actually needs.
///
/// The first attempt at notch onboarding took `SetupFlow` — written for a resizable window
/// — and put it in a fixed box. That is not the same design at a smaller size, it is a
/// different and worse one: every step got the same rectangle, sized for the largest of
/// them, so the intro sat in a mostly empty panel and the capture was cramped in the same
/// one. It also grew past the screen and could not be closed, because content and container
/// were never designed against each other.
///
/// What makes a notch panel read as belonging to the notch is that it is **small, and grows
/// only as far as the thing it is currently showing**. So each step declares its own height
/// and the window springs between them. Coming out of enrolment the panel shrinks to a
/// checkmark, which is a fifth of the height it just was, and that shrink is most of what
/// sells it.
enum SetupNotchStep: String, CaseIterable, Identifiable {
	case intro
	case permission
	case enrol
	case password
	case done

	var id: String { rawValue }

	/// Sized by content, measured rather than guessed: each is the smallest height at which
	/// that step's tallest arrangement does not clip.
	var height: CGFloat {
		switch self {
		case .intro: 196
		case .permission: 246
		case .enrol: 348
		case .password: 254
		case .done: 158
		}
	}
}

enum SetupNotchMetrics {
	/// Narrower than the 460 the first attempt used. Past roughly 400 a panel stops reading
	/// as something the notch produced and starts reading as a window that happens to be
	/// near the top of the screen.
	static let width: CGFloat = 380

	/// The panel changing size is the main animation in the whole flow, so it gets a spring
	/// rather than a curve — a resize that eases to a stop reads as a window resizing,
	/// where one that settles reads as an object changing shape.
	static let resize = Animation.spring(response: 0.42, dampingFraction: 0.82)

	static let contentPadding: CGFloat = 22
}

// MARK: - Model

/// What step we are on, and how to get to the next one.
///
/// Separate from `SetupFlow`'s state for one reason: the controller needs to know the step
/// changed so it can resize the window, and an AppKit window cannot observe SwiftUI state
/// without being told. `onStepChange` is that telling.
@Observable
@MainActor
final class SetupNotchModel {

	private(set) var plan: [SetupNotchStep] = []
	private(set) var step: SetupNotchStep = .intro {
		didSet { onStepChange?(step) }
	}

	/// Set by the controller so it can spring the window to the new height.
	@ObservationIgnored var onStepChange: ((SetupNotchStep) -> Void)?

	init() {
		plan = Self.makePlan()
	}

	/// Only the steps this Mac actually needs.
	///
	/// The same reasoning as `SetupFlow.makePlan`: a screen that exists only to be skipped
	/// past is a step in the count nobody takes. On a Mac with the password already stored
	/// and Accessibility already granted this is intro → enrol → done, and enrolment is the
	/// only one that asks anything of you.
	private static func makePlan() -> [SetupNotchStep] {
		var steps: [SetupNotchStep] = [.intro]
		if !AXIsProcessTrusted() { steps.append(.permission) }
		steps.append(.enrol)
		if !PasswordVault.hasPassword { steps.append(.password) }
		steps.append(.done)
		return steps
	}

	var position: (index: Int, count: Int)? {
		guard let index = plan.firstIndex(of: step) else { return nil }
		return (index, plan.count)
	}

	func advance() {
		guard let index = plan.firstIndex(of: step), index + 1 < plan.count else { return }
		withAnimation(SetupNotchMetrics.resize) { step = plan[index + 1] }
	}

	/// Re-plans from the current state and jumps to whatever is still outstanding.
	///
	/// Granting Accessibility happens in System Settings, outside this panel, so the step
	/// cannot advance itself on a button press — it has to notice the answer changed.
	func refreshPlan() {
		plan = Self.makePlan()
		if !plan.contains(step) { step = plan.first ?? .done }
	}
}

// MARK: - Chrome

/// The frame every step sits in: a title, a body, and whatever controls it needs.
struct SetupNotchStepFrame<Content: View>: View {

	let title: String
	var detail: String?
	@ViewBuilder var content: Content

	var body: some View {
		VStack(spacing: 10) {
			Text(title)
				.font(.system(size: 19, weight: .semibold))
				.foregroundStyle(.white)
				.multilineTextAlignment(.center)

			if let detail {
				Text(detail)
					.font(.system(size: 12))
					.foregroundStyle(.white.opacity(0.62))
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			content
				.padding(.top, 2)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.horizontal, SetupNotchMetrics.contentPadding)
		.padding(.vertical, 18)
	}
}

/// The panel's own button. Capsule, filled, and sized for a 380pt panel rather than a
/// window — the app's `gazeButton` is tuned for Settings and reads oversized here.
struct SetupNotchButton: View {

	let title: String
	var isProminent = true
	var isEnabled = true
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.system(size: 13, weight: .semibold))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 7)
		}
		.buttonStyle(.plain)
		.background {
			Capsule().fill(isProminent ? Color.white : Color.white.opacity(0.14))
		}
		.foregroundStyle(isProminent ? Color.black : Color.white)
		.opacity(isEnabled ? 1 : 0.4)
		.disabled(!isEnabled)
	}
}
