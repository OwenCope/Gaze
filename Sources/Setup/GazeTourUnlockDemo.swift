import SwiftUI

/// The "How unlock works" tour page, played live: the real lock-screen panel drops from
/// the notch, asks for a movement, and unlocks, on a loop. Camera-free; nothing here can
/// unlock anything.
struct GazeTourUnlockDemo: View {
	@State private var model: NotchCapsuleModel = {
		let model = NotchCapsuleModel()
		model.shape = .attached
		model.style = .normal
		model.glyphPlacement = .centred
		model.showsCaptions = true
		model.phase = .locked
		model.isExpanded = true
		return model
	}()
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let steps: [(NotchCapsuleModel.Phase, Duration)] = [
		(.locked, .seconds(1)),
		(.scanning, .seconds(1.6)),
		(.challenge(prompt: "Turn slightly left", symbol: "arrow.left", hintX: -1, hintY: 0, pulses: true), .seconds(2.2)),
		(.success, .seconds(1.4)),
		(.unlocked, .seconds(1)),
	]

	var body: some View {
		ZStack(alignment: .top) {
			NotchCapsule(model: model, width: 300, height: 150, notchInset: 32, cutoutWidth: 190, hasNotch: true)
			UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
				.fill(.black)
				.frame(width: 190, height: 32)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		// TourKit insets page media; the notch belongs on the top edge.
		.padding(.top, -36)
		.allowsHitTesting(false)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("The Gaze panel drops from the notch, asks you to turn slightly left, then unlocks.")
		.task {
			if reduceMotion {
				model.phase = Self.steps[2].0
				return
			}
			while !Task.isCancelled {
				for (phase, hold) in Self.steps {
					model.phase = phase
					do { try await Task.sleep(for: hold) } catch { return }
				}
			}
		}
	}
}
