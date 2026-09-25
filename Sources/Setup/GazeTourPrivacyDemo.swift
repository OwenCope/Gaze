import SwiftUI

/// The "Stays on your Mac" tour page, played live. The cloud sits on one side and this
/// Mac on the other; the companion looks at the cloud as it is crossed out, then turns
/// to the Mac as it becomes a Gaze-face padlock that closes. On a loop, camera-free.
struct GazeTourPrivacyDemo: View {
	@State private var step = 0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let holds: [Duration] = [.seconds(1.2), .seconds(1.4), .seconds(1.3), .seconds(0.8), .seconds(2.0)]
	private static let lastStep = 4

	private var cloudActive: Bool { step <= 1 }

	/// Where the companion looks, -1 (the cloud, on the left) to 1 (the Mac). It holds
	/// its gaze on the one being talked about rather than glancing and coming back.
	private var look: Double { step <= 1 ? -1 : 1 }

	var body: some View {
		HStack(spacing: 44) {
			// The cloud never swaps symbols, so it cannot shift; the slash draws across it.
			symbol("icloud.fill", active: cloudActive)
				.overlay { DrawnSlash(progress: step >= 1 ? 1 : 0).opacity(cloudActive ? 1 : 0.35) }
			GazeLookingCompanion(look: look, happy: step == 4)
				.frame(width: 170, height: 170)
				.background { halo(opacity: 0.7) }
			// One slot: the Mac gives way to a padlock shaped like the Gaze face, whose
			// shackle then drops shut, the way Apple's privacy lock is built from its logo.
			ZStack {
				if step < 3 {
					symbol("laptopcomputer", active: !cloudActive)
						.transition(.blurReplace)
				} else {
					GazeFaceLock(closed: step == 4)
						.frame(width: 130, height: 130)
						.background { halo(opacity: 0.55) }
						.transition(.blurReplace)
				}
			}
			.frame(width: 130, height: 130)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Not in the cloud: your face data stays locked on this Mac.")
		.task {
			if reduceMotion {
				step = Self.lastStep
				return
			}
			while !Task.isCancelled {
				for index in Self.holds.indices {
					withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = index }
					do { try await Task.sleep(for: Self.holds[index]) } catch { return }
				}
			}
		}
	}

	private func symbol(_ name: String, active: Bool) -> some View {
		Image(systemName: name)
			.font(.system(size: 72, weight: .medium))
			.symbolRenderingMode(.monochrome)
			.foregroundStyle(.white)
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp.byLayer)))
			.frame(width: 130, height: 130)
			.background { halo(opacity: 0.55) }
			.opacity(active ? 1 : 0.35)
			.scaleEffect(active ? 1 : 0.9)
	}

	/// A radial gradient rather than a blurred circle: a blur re-rasterises whenever a
	/// neighbour animates, and that was costing frames.
	private func halo(opacity: Double) -> some View {
		RadialGradient(colors: [.black.opacity(opacity), .clear], center: .center, startRadius: 30, endRadius: 110)
			.frame(width: 220, height: 220)
			.allowsHitTesting(false)
	}
}

/// A padlock whose body is the Gaze face's rounded square, and a thick shackle that drops into it with a spring and a small settle, the way
/// Apple's privacy lock drops its shackle onto the logo.
private struct GazeFaceLock: View {
	var closed: Bool
	@State private var shown = false

	var body: some View {
		ZStack(alignment: .bottom) {
			Shackle()
				.stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
				.frame(width: 40, height: 40)
				// Legs tuck behind the body when closed; open, a clear gap shows.
				.offset(y: closed ? -44 : -64)
				.animation(.spring(response: 0.38, dampingFraction: 0.62), value: closed)
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(.white)
				.frame(width: 66, height: 58)
		}
		.frame(width: 80, height: 112, alignment: .bottom)
		.scaleEffect(shown ? 1 : 0.6)
		.onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { shown = true } }
	}
}

/// The shackle: two legs joined by a half circle over the top.
private struct Shackle: Shape {
	func path(in rect: CGRect) -> Path {
		let radius = rect.width / 2
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
		path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
			startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		return path
	}
}

/// A slash drawn across a symbol, stroke by stroke. A dark cut runs under the white line
/// so it reads as crossed out, the way SF Symbols' slashed variants do.
private struct DrawnSlash: View {
	var progress: CGFloat

	var body: some View {
		ZStack {
			SlashLine()
				.trim(from: 0, to: progress)
				.stroke(.black, style: StrokeStyle(lineWidth: 16, lineCap: .round))
			SlashLine()
				.trim(from: 0, to: progress)
				.stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
		}
		.frame(width: 92, height: 92)
		.animation(.easeInOut(duration: progress > 0 ? 0.55 : 0.25), value: progress)
	}
}

private struct SlashLine: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		return path
	}
}
