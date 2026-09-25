import SwiftUI

/// The "Unlocking stays your choice" tour page, played live: the companion waits beside a
/// switch that starts off, looks at it, and brightens when it is turned on. On a loop,
/// camera-free; the switch is a drawing, not a control.
struct GazeTourChoiceDemo: View {
	@State private var step = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let holds: [Duration] = [.seconds(1.2), .seconds(1.4), .seconds(3.0)]
	private var isOn: Bool { step == 2 }

	var body: some View {
		HStack(spacing: 56) {
			GazeLookingCompanion(look: step == 0 ? 0 : 1, happy: isOn)
				.frame(width: 170, height: 170)
				.background { halo(size: 190) }
			BigSwitch(isOn: isOn)
				.background { halo(size: 200) }
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Automatic unlocking stays off until you switch it on.")
		.task {
			if reduceMotion {
				step = 0
				return
			}
			while !Task.isCancelled {
				for index in Self.holds.indices {
					step = index
					do { try await Task.sleep(for: Self.holds[index]) } catch { return }
				}
			}
		}
	}

	private func halo(size: CGFloat) -> some View {
		RadialGradient(colors: [.black.opacity(0.65), .clear], center: .center, startRadius: size * 0.2, endRadius: size * 0.6)
			.frame(width: size * 1.2, height: size * 1.2)
	}
}

/// The iOS 26 switch, after the Liquid Glass toggle in the reference Figma file, in white.
///
/// At rest the knob is a white capsule inset in a long track. While it moves it swells
/// into a larger glass capsule that spills past the track: clear inside, so the track
/// shows through, with a bright rim that is strongest along the bottom and a soft glow.
/// Then it settles back into the solid capsule.
private struct BigSwitch: View {
	var isOn: Bool
	@State private var moving = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private let trackSize = CGSize(width: 150, height: 66)
	private let knobSize = CGSize(width: 86, height: 54)
	private let lensSize = CGSize(width: 116, height: 80)
	private var inset: CGFloat { (trackSize.height - knobSize.height) / 2 }
	private var trackColor: Color { .white.opacity(isOn ? 0.92 : 0.2) }

	/// The knob's centre along the track.
	private var knobCenterX: CGFloat {
		isOn ? trackSize.width - inset - knobSize.width / 2 : inset + knobSize.width / 2
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			Capsule(style: .continuous)
				.fill(trackColor)
				.frame(width: trackSize.width, height: trackSize.height)

			ZStack {
				// Resting: a solid white capsule.
				Capsule(style: .continuous)
					.fill(.white)
					.shadow(color: .black.opacity(0.28), radius: 4, y: 2)
					.frame(width: knobSize.width, height: knobSize.height)
					.opacity(moving ? 0 : 1)
				lens
					.opacity(moving ? 1 : 0)
			}
			.frame(width: moving ? lensSize.width : knobSize.width, height: moving ? lensSize.height : knobSize.height)
			.position(x: knobCenterX, y: trackSize.height / 2)
		}
		.frame(width: trackSize.width, height: trackSize.height)
		.animation(.spring(response: 0.9, dampingFraction: 0.78), value: isOn)
		.onChange(of: isOn) { _, _ in
			guard !reduceMotion else { return }
			withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { moving = true }
			Task {
				try? await Task.sleep(for: .seconds(0.85))
				withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { moving = false }
			}
		}
	}

	/// Clear glass: the track colour seen through a slightly smaller inner capsule, a thin
	/// bright rim heavier at the bottom, and a soft outer glow.
	private var lens: some View {
		ZStack {
			Capsule(style: .continuous)
				.fill(.white.opacity(0.06))
			Capsule(style: .continuous)
				.fill(trackColor)
				.padding(.horizontal, 12)
				.padding(.vertical, 12)
			Capsule(style: .continuous)
				.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.15), .white.opacity(0.95)],
					startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
			Capsule(style: .continuous)
				.strokeBorder(.black.opacity(0.18), lineWidth: 0.75)
				.padding(2.5)
		}
		.shadow(color: .white.opacity(0.18), radius: 14)
		.shadow(color: .black.opacity(0.2), radius: 6, y: 3)
	}
}
