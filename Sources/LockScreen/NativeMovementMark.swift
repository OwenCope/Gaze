import SwiftUI

/// The movement prompt, drawn in the same line-art mark the unlock clips use.
///
/// Until now the native animation had a hole in the middle of the unlock. `clip(for:)`
/// sent `.challenge` to the idle clip, so with the option on the panel played a face
/// quietly breathing while the caption underneath asked you to turn or blink — the mark
/// stopped demonstrating the movement it was asking for, which was the one thing the drawn
/// head did that made the prompt readable without reading it.
///
/// There are no clips for this. The shipped clips are a blue line-art mark and the only
/// movement artwork in the tree is a storyboard of an unrelated character, so rather than
/// invent a second art style the mark is drawn here instead, from the same measurements as
/// the clips, and animated from `GazeCompanionTiming.guidance` — the very function that
/// drives the drawn head. Both marks therefore turn, nod and blink to the same clock, and
/// switching the option off changes how the movement looks but never when it happens.
enum NativeMovementAssets {

	/// True for Follow the light: a look action, where the head holds still and only the
	/// eyes move.
	///
	/// `GazeFaceMotion` folds both look actions into `.resting` — the drawn head has no
	/// way to show them and leans on a chevron and a light at the panel edge instead. The
	/// mark drawn here does have eyes, so it can show the movement itself.
	static func lookDirection(for phase: NotchCapsuleModel.Phase) -> CGFloat? {
		guard case .challenge(_, let symbol, let horizontal, _, _, _) = phase,
			symbol == "eye.fill", horizontal != 0 else { return nil }
		return horizontal < 0 ? -1 : 1
	}
}

/// The mark itself: the four brackets, two eyes, nose and smile from the unlock clips.
///
/// Measured off `unlock-native-idle-*.mp4` rather than eyeballed — the component bounding
/// boxes and stroke weight of a decoded frame are what the constants below are, as fractions
/// of the clip's 432pt canvas. Getting these from the pixels is the difference between a
/// mark that reads as the same character and one that reads as a similar one.
struct NativeGlyph: View {

	var face = GazeFacePose()
	var tint: Color

	/// Stroke weight, as a fraction of the canvas. The clips are one weight throughout —
	/// measured at 23pt on the 432pt canvas across brackets, smile and nose alike.
	private static let stroke: CGFloat = 0.053
	/// Eye width; the capsules are this thick and about two and a half times as tall.
	private static let eyeWidth: CGFloat = 0.053

	var body: some View {
		Canvas { context, size in
			let u = min(size.width, size.height)
			// Everything below is in unit space — 0 to 1 — and the context is scaled once,
			// so the stroke weight is a unit value too. Mixing the two, as an earlier
			// version did, scaled the stroke by 432 as well and painted the panel solid.
			let stroke = StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round)

			context.translateBy(x: size.width / 2, y: size.height / 2)
			context.scaleBy(x: u, y: u)
			context.translateBy(x: -0.5, y: -0.5)

			// The brackets are the crop, and they never move.
			//
			// They used to parallax against the face and take the whole mark with them,
			// which put it up to six points off centre across a prompt and sent it
			// visibly travelling on the return to rest — up and to the right, because
			// that is the direction a left turn and a nod unwind in. The frame is what
			// says where the face is supposed to be; it has to stay where it was put for
			// that to mean anything.
			for bracket in Self.brackets {
				context.stroke(bracket, with: .color(tint), style: stroke)
			}

			// The face turns inside the frame: foreshortened and tipped, which is what
			// sells a flat drawing as a head moving in space. Scaling the context scales
			// the strokes with it, so the far side of the turn is genuinely heavier.
			context.translateBy(x: 0.5, y: 0.5)
			context.rotate(by: .degrees(face.nod * -2.5))
			context.scaleBy(x: 1 - abs(face.turn) * 0.30,
				y: 1 - abs(face.turn) * 0.05 - face.nod * 0.10)
			context.translateBy(x: -0.5, y: -0.5)
			context.translateBy(x: face.turn * 0.02, y: face.nod * 0.06)

			// Features move further than the head does, and the gaze further again.
			let featureShift = CGAffineTransform(translationX: face.turn * 0.055 + face.gaze * 0.012,
				y: face.nod * 0.03)
			drawNose(context: context, shift: featureShift, stroke: stroke)
			drawMouth(context: context, shift: featureShift, stroke: stroke)
			drawEyes(context: context, shift: featureShift)
		}
		.aspectRatio(1, contentMode: .fit)
		.blendMode(.screen)
		.accessibilityHidden(true)
	}

	// MARK: - Features

	private func drawEyes(context: GraphicsContext, shift: CGAffineTransform) {
		// A capsule is a round-capped line, so closing the eye is shortening it — at zero
		// it collapses to a dot and then, as the opacity goes with it, to nothing, which
		// is a blink rather than a squint.
		let closed = 1 - min(1, max(0, face.eyesOpen))
		let half = (0.145 - Self.eyeWidth) / 2
		for centre in [CGFloat(0.3355), CGFloat(0.6795)] {
			// The gaze moves the eyes further than anything else moves, because it is the
			// only cue Follow the light has — the head is deliberately still for it.
			let x = centre + face.gaze * 0.045
			let reach = half * (1 - closed)
			var path = Path()
			path.move(to: CGPoint(x: x, y: 0.3715 - reach))
			path.addLine(to: CGPoint(x: x, y: 0.3715 + reach))
			context.stroke(path.applying(shift), with: .color(tint.opacity(1 - closed * 0.9)),
				style: StrokeStyle(lineWidth: Self.eyeWidth, lineCap: .round))
		}
	}

	private func drawNose(context: GraphicsContext, shift: CGAffineTransform, stroke: StrokeStyle) {
		var path = Path()
		path.move(to: CGPoint(x: 0.528, y: 0.332))
		path.addLine(to: CGPoint(x: 0.470, y: 0.500))
		path.addLine(to: CGPoint(x: 0.527, y: 0.534))
		context.stroke(path.applying(shift), with: .color(tint), style: stroke)
	}

	private func drawMouth(context: GraphicsContext, shift: CGAffineTransform, stroke: StrokeStyle) {
		let open = min(1, max(0, face.mouthOpen))
		// Open is a separate shape crossfaded in rather than a deformed smile: an "O" and a
		// curve are different shapes, and tweening between them passes through both.
		if open < 1 {
			var smile = Path()
			smile.move(to: CGPoint(x: 0.325, y: 0.635))
			smile.addQuadCurve(to: CGPoint(x: 0.675, y: 0.635), control: CGPoint(x: 0.5, y: 0.773))
			context.stroke(smile.applying(shift), with: .color(tint.opacity(1 - open)), style: stroke)
		}
		if open > 0.01 {
			let mouth = CGRect(x: 0.400, y: 0.600, width: 0.215, height: 0.115 + 0.10 * open)
			context.stroke(Ellipse().path(in: mouth).applying(shift),
				with: .color(tint.opacity(open)), style: stroke)
		}
	}

	// MARK: - Geometry

	/// The four viewfinder brackets, in unit space, before mirroring.
	///
	/// A single rounded right angle: along the top, round the corner, down the side.
	private static let brackets: [Path] = {
		func corner(mirrorX: Bool, mirrorY: Bool) -> Path {
			// Mirroring every point rather than mirroring the finished path, so the round
			// caps and joins come out the same way round at each corner.
			func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
				CGPoint(x: (mirrorX ? 1 - x : x), y: (mirrorY ? 1 - y : y))
			}
			var path = Path()
			path.move(to: pt(0.279, 0.146))
			path.addLine(to: pt(0.232, 0.146))
			// A generous corner: the arc is a full 0.099 across, a fifth of the mark.
			// Tighter than this and it reads as an L-bracket rather than a viewfinder.
			path.addQuadCurve(to: pt(0.133, 0.245), control: pt(0.133, 0.146))
			path.addLine(to: pt(0.133, 0.293))
			return path
		}
		return [
			corner(mirrorX: false, mirrorY: false),
			corner(mirrorX: true, mirrorY: false),
			corner(mirrorX: false, mirrorY: true),
			corner(mirrorX: true, mirrorY: true),
		]
	}()
}

/// The animated movement prompt.
///
/// Driven the same way `GazeCompanionView` drives the drawn head — the same playback
/// object, retargeted when the action changes, so a prompt that moves from turning to
/// blinking blends between them instead of cutting.
struct NativeMovementMark: View {

	let phase: NotchCapsuleModel.Phase
	let colour: Preferences.UnlockAnimationColour
	var active = true

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var playback: GazeCompanionPlayback?

	/// The drawn head overscales itself, so this does too — swapping one mark for the
	/// other should not change how large it reads in the panel.
	private static let overscale = 1.18

	private struct PlaybackKey: Equatable {
		let motion: GazeFaceMotion
		let look: CGFloat?
	}

	var body: some View {
		let key = PlaybackKey(motion: motion, look: look)
		TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !canAnimate)) { context in
			NativeGlyph(face: pose(at: context.date.timeIntervalSinceReferenceDate).face, tint: colour.glyphTint)
		}
		.scaleEffect(Self.overscale)
		.task(id: key) {
			let time = Date.timeIntervalSinceReferenceDate
			if playback != nil { playback?.retarget(to: motion, at: time) }
			else { playback = GazeCompanionPlayback(motion: motion, at: time, presentation: .notch) }
		}
		.accessibilityElement(children: .ignore)
		.accessibilityHidden(false)
		.accessibilityLabel(phase.markAccessibilityLabel)
	}

	/// Follow the light keeps its head still, so it needs a pose of its own: the eyes
	/// sweep one way and back on the same 3.2 second loop the other actions use.
	///
	/// Timed from when the prompt appeared rather than from the clock, so the sweep
	/// starts where a turn or a nod would start instead of joining the loop at whatever
	/// point it happens to have reached.
	private func pose(at time: TimeInterval) -> GazeCompanionPose {
		guard let look else { return playback?.pose(at: time, reducedMotion: reduceMotion) ?? GazeCompanionPose() }
		if reduceMotion { return GazeCompanionPose(face: motion.stillPose) }
		let elapsed = max(0, time - (playback?.startedAt ?? time))
		var pose = GazeCompanionPose()
		pose.face.gaze = look * 0.62 * GazeCompanionTiming.pulse(elapsed, 0.28, 1.05, 1.65, 2.55)
		return pose
	}

	private var motion: GazeFaceMotion { GazeFaceMotion(phase: phase) }
	private var look: CGFloat? { NativeMovementAssets.lookDirection(for: phase) }
	/// Paused rather than torn down when the panel blinks between phases.
	private var canAnimate: Bool { active && !reduceMotion }
}

extension Preferences.UnlockAnimationColour {
	/// The mark's stroke colour, matching the clips exactly rather than approximating them.
	///
	/// Sampled from the decoded frames: `#3398FD` and `#2FFB80`.
	var glyphTint: Color {
		switch self {
		case .blue: return Color(red: 0x33 / 255, green: 0x98 / 255, blue: 0xFD / 255)
		case .green: return Color(red: 0x2F / 255, green: 0xFB / 255, blue: 0x80 / 255)
		}
	}
}
