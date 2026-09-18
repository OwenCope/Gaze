import SwiftUI

/// The ring of radial ticks that fills as the user turns their head.
///
/// Apple's proportions: many thin ticks set well clear of the preview circle, unfilled
/// ones barely visible against the dark background, filled ones a saturated green. The
/// contrast between the two states is the whole affordance — people work out what to do
/// from watching which ticks are still dark, without reading the label.
struct EnrollmentRing: View {

	let covered: [Bool]
	/// Direction the head is pointing, in radians, matching `FacePose.ringAngle`.
	let currentAngle: Double
	/// Whether the head is turned far enough to be filling ticks right now.
	let isEngaged: Bool
	var targetSegment: Int? = nil
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// Apple's Face ID green — the one in `Theme`, not a second copy of it.
	///
	/// This was `0.20, 0.82, 0.35` while the token was `0.20, 0.78, 0.35`, and the lock
	/// screen used a third value again. Three greens all meaning "recognised", none of them
	/// matching, in an app whose design system exists to prevent exactly that.
	private let filled = Theme.faceID
	private let empty = Theme.tickEmpty

	private let tickWidth: CGFloat = 3.5
	private let tickLength: CGFloat = 22
	/// Gap between the preview circle and the inner end of the ticks.
	private let gap: CGFloat = 16

	var body: some View {
		GeometryReader { geometry in
			let side = min(geometry.size.width, geometry.size.height)
			let radius = side / 2 - tickLength / 2

			ZStack {
				ForEach(covered.indices, id: \.self) { index in
					tick(at: index, radius: radius)
				}
			}
			.frame(width: side, height: side)
			.position(x: geometry.size.width / 2, y: geometry.size.height / 2)
			.animation(reduceMotion ? nil : Theme.Motion.quick, value: covered)
			.animation(reduceMotion ? nil : Theme.Motion.quick, value: targetSegment)
		}
	}

	private func tick(at index: Int, radius: CGFloat) -> some View {
		let angle = Double(index) / Double(covered.count) * 2 * .pi
		let isFilled = covered[index]
		let proximity = proximityToHead(at: angle)
		let isTarget = targetSegment == index && !isFilled

		return Capsule()
			.fill(isFilled ? filled : isTarget ? Color.primary : empty)
			// The ticks nearest the head lengthen and brighten slightly, tying the ring to
			// where the user is looking. It used to also cast a green glow (a 7pt shadow that
			// swelled with proximity), which is the decorative bloom the app avoids everywhere
			// else — the length and opacity change carry the cue on their own.
			.frame(width: isTarget ? tickWidth + 2 : tickWidth, height: tickLength + 8 * proximity + (isTarget ? 6 : 0))
			.offset(y: -radius)
			.rotationEffect(.radians(angle))
			.opacity(isFilled || isTarget ? 1 : 0.55 + 0.45 * proximity)
	}

	/// 1 when this tick is directly under the head's direction, falling to 0 a few ticks
	/// away. Zero when the head isn't turned far enough to be capturing.
	private func proximityToHead(at angle: Double) -> Double {
		guard isEngaged else { return 0 }
		var delta = abs(angle - normalisedHeadAngle)
		if delta > .pi { delta = 2 * .pi - delta }
		let falloff = 2 * .pi / Double(covered.count) * 3
		return max(0, 1 - delta / falloff)
	}

	private var normalisedHeadAngle: Double {
		let remainder = currentAngle.truncatingRemainder(dividingBy: 2 * .pi)
		return remainder < 0 ? remainder + 2 * .pi : remainder
	}

	/// Ticks sit this far outside the preview circle.
	var previewInset: CGFloat { tickLength + gap }
}
