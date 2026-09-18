import SwiftUI

struct SetupMark: View {
	enum Kind: Equatable {
		case looking, success, failure
	}

	let kind: Kind
	var diameter: CGFloat = 72
	var trigger = 0
	@State private var appeared = false
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var motion: GazeFaceMotion {
		switch kind {
		case .looking: .resting
		case .success: .accepted
		case .failure: .rejected
		}
	}

	var body: some View {
		HStack {
			Spacer(minLength: 0)
			Group {
				if kind == .looking {
					GazeLessonAnimation(motion: .resting, paused: true,
						material: colorScheme == .dark ? .ink : .charcoal)
				} else {
					GazeCompanionView(motion: motion, active: true,
						material: colorScheme == .dark ? .ink : .charcoal, trigger: trigger)
				}
			}
			.frame(width: diameter * 0.94, height: diameter * 0.94)
			.frame(width: diameter, height: diameter)
			.opacity(appeared ? 1 : 0)
			.scaleEffect(appeared ? 1 : 0.96)
			.onAppear {
				if reduceMotion {
					appeared = true
				} else {
					withAnimation(.easeOut(duration: 0.35)) { appeared = true }
				}
			}
			.frame(maxWidth: .infinity, alignment: .center)
			.padding(.top, 12)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(kind == .looking ? "Gaze" : kind == .success ? "Completed" : "Try again")
		}
	}
}
