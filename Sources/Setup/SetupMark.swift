import AppKit
import SwiftUI

/// The mark setup shows: looking, recognised, or not.
///
/// It's the app's own icon — the Gaze target — rather than an invented scanner or Apple's
/// `faceid` glyph. It sits still: a native onboarding screen doesn't breathe or pulse, and an
/// idle looping animation is decoration with no signal (this one used to scale-breathe the
/// icon forever). The one beat of motion is the one that means something — a tick or cross
/// bouncing in on the result. Ours, plain SwiftUI, no framework.
struct SetupMark: View {

	enum Kind: Equatable {
		case looking
		case success
		case failure
	}

	let kind: Kind
	var diameter: CGFloat = 180
	/// Bump to replay the result animation. Ignored while looking.
	var trigger: Int = 0

	private var icon: NSImage { NSApplication.shared.applicationIconImage ?? NSImage() }

	var body: some View {
		ZStack {
			Image(nsImage: icon)
				.resizable()
				.interpolation(.high)
				.frame(width: diameter * 0.72, height: diameter * 0.72)
				.overlay(alignment: .bottomTrailing) {
					if kind != .looking {
						Image(systemName: kind == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
							.font(.system(size: diameter * 0.2, weight: .bold))
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, kind == .success ? Theme.faceID : Theme.danger)
							.background(Circle().fill(Theme.setupGround).padding(2))
							.offset(x: diameter * 0.05, y: diameter * 0.05)
							.transition(.scale(scale: 0.7).combined(with: .opacity))
							.symbolEffect(.bounce, value: trigger)
					}
				}
		}
		.frame(width: diameter, height: diameter)
		.animation(.spring(response: 0.5, dampingFraction: 0.72), value: kind)
	}
}
