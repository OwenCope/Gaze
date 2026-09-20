import SwiftUI

enum GazeExpressionLesson: String, CaseIterable, Identifiable {
	case waiting, scanning, turnLeft, turnRight, nod, blink, openMouth, success, retry
	var id: String { rawValue }
	var title: String {
		switch self {
		case .waiting: "Ready when you are"
		case .scanning: "Looking for you"
		case .turnLeft: "Turn left"
		case .turnRight: "Turn right"
		case .nod: "Nod"
		case .blink: "Blink"
		case .openMouth: "Open mouth"
		case .success: "Verified"
		case .retry: "Not verified"
		}
	}
	func explanation(movementCount: Int = 2) -> String {
		switch self {
		case .waiting: "Gaze is ready. Its eyes may wander—you don’t need to follow them."
		case .scanning: "Look toward the camera and hold still. Before unlocking, Gaze asks for \(movementCount == 1 ? "one short movement" : "two short movements"). Follow along, then return to your starting position."
		case .turnLeft: "Make a small turn toward your own left, then return to your starting position."
		case .turnRight: "Make a small turn toward your own right, then return to your starting position."
		case .nod: "Lower your chin a little, then return to your starting position. You don’t need to look up."
		case .blink: "Close both eyes briefly, then open them. Gaze only blinks when it’s asking you to."
		case .openMouth: "Open your mouth briefly, then relax. Keep your face toward the camera."
		case .success: "Gaze recognised you. The smile means your face check passed—there’s no movement to copy."
		case .retry: "Gaze couldn’t confirm it’s you. Use your password or Touch ID, if available."
		}
	}
	var motion: GazeFaceMotion {
		switch self {
		case .waiting: .resting
		case .scanning: .scanning
		case .turnLeft: .turnLeft
		case .turnRight: .turnRight
		case .nod: .nod
		case .blink: .blink
		case .openMouth: .openMouth
		case .success: .accepted
		case .retry: .rejected
		}
	}
	var category: String {
		switch self {
		case .waiting, .scanning: "Just look at the camera"
		case .success, .retry: "Your result"
		default: "When asked, follow along"
		}
	}
	var index: Int { Self.allCases.firstIndex(of: self)! }
	var previous: Self? { index > 0 ? Self.allCases[index - 1] : nil }
	var next: Self? { index + 1 < Self.allCases.count ? Self.allCases[index + 1] : nil }
}

struct GazeExpressionGuide: View {
	var compact = false
	var movementCount: Int
	@State private var lesson = GazeExpressionLesson.waiting
	@State private var paused = false
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion

	init(compact: Bool = false, lesson: GazeExpressionLesson = .waiting, movementCount: Int = 2) {
		self.compact = compact
		self.movementCount = movementCount
		_lesson = State(initialValue: lesson)
	}

	var body: some View {
		VStack(spacing: compact ? 16 : 24) {
			HStack(alignment: .center) {
				Text(lesson.category)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.secondary)
				Spacer()
				lessonMenu
			}
			HStack(spacing: compact ? 20 : 28) {
				GazeLessonAnimation(motion: lesson.motion, paused: paused,
					material: colorScheme == .dark ? .ink : .charcoal)
					.frame(width: compact ? 132 : 180, height: compact ? 132 : 180)
				VStack(alignment: .leading, spacing: 10) {
					Text(lesson.title)
						.font(.system(size: compact ? 20 : 23, weight: .semibold))
						.accessibilityAddTraits(.isHeader)
					Text(lesson.explanation(movementCount: movementCount))
						.font(.system(size: compact ? 13 : 14))
						.foregroundStyle(.secondary)
						.lineSpacing(3)
						.fixedSize(horizontal: false, vertical: true)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(height: compact ? 154 : 180)
			HStack(spacing: 12) {
				Button { if let previous = lesson.previous { select(previous) } } label: {
					Label("Previous", systemImage: "chevron.left")
						.frame(minWidth: compact ? 75 : 88)
				}
				.disabled(lesson.previous == nil)
				.help(lesson.previous.map { "Previous expression: \($0.title)" } ?? "First expression")
				Button { paused.toggle() } label: {
					Label(paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
						.frame(minWidth: compact ? 56 : 64)
				}
				.disabled(reduceMotion || previewReduceMotion)
				.help(paused ? "Resume this animation" : "Pause this animation")
				Button {
					select(lesson.next ?? .waiting)
				} label: {
					HStack(spacing: 8) {
						Text(lesson.next == nil ? "Again" : "Next")
						Image(systemName: lesson.next == nil ? "arrow.counterclockwise" : "chevron.right")
					}
					.frame(minWidth: compact ? 75 : 88)
				}
				.help(lesson.next.map { "Next expression: \($0.title)" } ?? "Watch from the beginning")
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			HStack(spacing: 6) {
				Text(reduceMotion || previewReduceMotion ? "Reduce Motion is on · Camera off" : "Just a demonstration · Camera off")
					.font(.caption).foregroundStyle(.secondary)
				InfoButton(title: "A preview, not a face check") {
					Text("Your camera stays off here. During a real check, only copy the movement Gaze asks for—not its idle glances or the nod after a smile.")
					Text("These use Gaze’s real animations. Results repeat at a gentler pace here so you can learn them. macOS still handles unlocking; a preview never unlocks anything.")
				}
			}
		}
		.frame(maxWidth: 480)
	}

	private var lessonMenu: some View {
		Menu {
			Section("Waiting") { choices([.waiting, .scanning]) }
			Section("Movement prompts") { choices([.turnLeft, .turnRight, .nod, .blink, .openMouth]) }
			Section("Results") { choices([.success, .retry]) }
		} label: {
			Text("\(lesson.index + 1) of \(GazeExpressionLesson.allCases.count)")
				.font(.system(size: 12, weight: .medium)).monospacedDigit()
				.padding(.horizontal, 6)
		}
		.menuStyle(.button)
		.buttonStyle(.glass)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.accessibilityLabel("Choose an expression, \(lesson.index + 1) of \(GazeExpressionLesson.allCases.count)")
		.help("See all expressions")
		.fixedSize()
	}

	@ViewBuilder private func choices(_ items: [GazeExpressionLesson]) -> some View {
		ForEach(items) { item in
			Button { select(item) } label: {
				if item == lesson { Label(item.title, systemImage: "checkmark") }
				else { Text(item.title) }
			}
		}
	}

	private func select(_ item: GazeExpressionLesson) {
		lesson = item
		paused = false
	}
}

struct SetupMeetGazeStep: View {
	var position: SetupPosition?
	var onContinue: () -> Void
	var onBack: (() -> Void)?
	var movementCount = 2

	var body: some View {
		SetupScaffold(position: position, title: "Meet Gaze",
			message: "Gaze asks for \(movementCount == 1 ? "one small movement" : "two small movements").\nWhen it turns back, return your head to where you started.",
			figureHeight: 0, onBack: onBack) {
			EmptyView()
		} detail: {
			// Opens on the scanning lesson: it carries the one/two-movement instruction,
			// which is the thing this screen is for. Waiting stays one step back via
			// Previous and the lesson menu, and every other lesson is still reachable.
			GazeExpressionGuide(lesson: .scanning, movementCount: movementCount).padding(.top, 20)
		} actions: {
			SetupButton(title: "Continue Setup", action: onContinue)
		}
	}
}
