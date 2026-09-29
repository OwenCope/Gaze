import SwiftUI

/// The "Lock your apps" tour page, played live: an app window waits locked, the Gaze
/// face mark covers the lock, and the card opens, on a slow loop. Camera-free; the
/// window is a drawing, not a control.
struct GazeTourAppLockDemo: View {
	@State private var step = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let holds: [Duration] = [.seconds(1.4), .seconds(0.6), .seconds(1.2)]
	private var faceVisible: Bool { step >= 1 }
	private var isOpen: Bool { step == 2 }

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(.white.opacity(isOpen ? 0.14 : 0.07))
				.frame(width: 220, height: 150)
				.overlay {
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.strokeBorder(.white.opacity(0.12), lineWidth: 1)
				}
				.background { halo(size: 230) }
			Image(systemName: "lock.fill")
				.font(.system(size: 30, weight: .semibold))
				.foregroundStyle(.white)
				.opacity(isOpen ? 0 : 1)
			GazeLessonAnimation(motion: .accepted, paused: false, material: .ink)
				.frame(width: 72, height: 72)
				.opacity(faceVisible ? 1 : 0)
				.scaleEffect(faceVisible ? 1 : 0.6)
		}
		.animation(.easeInOut(duration: 0.45), value: step)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Apps you choose open only for your face.")
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
