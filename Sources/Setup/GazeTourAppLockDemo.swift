import AppKit
import SwiftUI

/// The "Lock your apps" tour page, played live: a miniature Messages window waits
/// locked under the App Lock shield, the face looks, smiles, and the shield lifts
/// to reveal the messages, on a slow loop. Camera-free; the window is a drawing,
/// not a control.
struct GazeTourAppLockDemo: View {
	@State private var step = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let holds: [Duration] = [.seconds(1.4), .seconds(0.5), .seconds(1.0)]
	private var isOpen: Bool { step == 2 }
	private var isSuccess: Bool { step >= 1 }

	var body: some View {
		ZStack {
			// Mini app window with fake Messages-like content.
			VStack(spacing: 0) {
				HStack(spacing: 5) {
					Circle().fill(.red.opacity(0.9)).frame(width: 7, height: 7)
					Circle().fill(.yellow.opacity(0.9)).frame(width: 7, height: 7)
					Circle().fill(.green.opacity(0.9)).frame(width: 7, height: 7)
					Spacer()
				}
				.padding(.horizontal, 12)
				.frame(height: 22)
				.overlay(alignment: .bottom) { Divider().opacity(0.4) }
				VStack(alignment: .leading, spacing: 7) {
					Spacer(minLength: 0)
					HStack {
						RoundedRectangle(cornerRadius: 9, style: .continuous)
							.fill(.white.opacity(0.16))
							.frame(width: 150, height: 22)
						Spacer()
					}
					HStack {
						Spacer()
						RoundedRectangle(cornerRadius: 9, style: .continuous)
							.fill(.blue.opacity(0.75))
							.frame(width: 120, height: 22)
					}
					RoundedRectangle(cornerRadius: 3)
						.fill(.white.opacity(0.1))
						.frame(width: 190, height: 6)
					RoundedRectangle(cornerRadius: 3)
						.fill(.white.opacity(0.1))
						.frame(width: 150, height: 6)
					Spacer(minLength: 0)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
			}
			.frame(width: 300, height: 210)
			.background(.white.opacity(0.08))
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.strokeBorder(.white.opacity(0.12), lineWidth: 1)
			}
			.background { halo(size: 300) }
			// The shield over the window, dark variant of AppLockShieldView.
			ZStack {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x12 / 255).opacity(0.97))
				VStack(spacing: 0) {
					GazeLessonAnimation(motion: isSuccess ? .accepted : .scanning, paused: false, material: .ink)
						.frame(width: 70, height: 70)
						.overlay(alignment: .bottomTrailing) {
							Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app"))
								.resizable()
								.interpolation(.high)
								.frame(width: 22, height: 22)
								.clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
								.shadow(color: .black.opacity(0.25), radius: 4, y: 2)
								.offset(x: 6, y: 6)
						}
						.accessibilityHidden(true)
					Text(isSuccess ? "Unlocked" : "Looking for you")
						.font(.system(size: 11))
						.foregroundStyle(.white.opacity(0.62))
						.padding(.top, 8)
					Text("Use Password")
						.font(.system(size: 10, weight: .medium))
						.foregroundStyle(.white)
						.padding(.horizontal, 14)
						.frame(height: 24)
						.background(Capsule().fill(.white.opacity(0.12)))
						.padding(.top, 10)
						.opacity(isSuccess ? 0 : 1)
				}
			}
			.frame(width: 300, height: 210)
			.opacity(isOpen ? 0 : 1)
			.scaleEffect(isOpen ? 1.03 : 1)
		}
		.animation(.easeInOut(duration: 0.3), value: step)
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
