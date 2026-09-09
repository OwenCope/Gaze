// Generates Resources/AppIcon.icon/Assets/gaze-mark.png — the app icon's glyph.
//
// The mark is a keyhole. It is not a face, and that is deliberate twice over.
//
// The icon used to be a traced copy of Apple's `faceid`: brackets around a stylised face.
// Two problems. It was a specific mark attached to a registered trademark, and the first
// attempt to fix it — round eyes instead of bars, a centred smile instead of an offset one —
// changed nothing that mattered, because the composition Apple owns is *brackets around a
// face*, not the curve of the mouth. It also read as a cartoon smiley, which is the wrong
// register entirely for something that guards a login.
//
// A keyhole says "identity unlocks this" without drawing a face at all. It is the shape
// every credible security app reaches for, it belongs to nobody, and it survives being
// shrunk to the 16pt menu bar — which the old dot eyes did not.
//
// The one thing that makes or breaks it: the head must clearly overhang the waist. Draw the
// skirt too wide at the top and the two shapes merge into a featureless blob (a pawn, a
// lightbulb). The notches either side of the neck are what the eye reads as "keyhole", so
// the waist is deliberately far narrower than the head is round.
//
// Run: swift Scripts/make_icon_mark.swift
//
// The glyph is white on transparent. Icon Composer supplies the ground and the glass; the
// gradients live in AppIcon.icon/icon.json, not here.

import AppKit

let grid: CGFloat = 1024

/// Sized to fill the icon's optical square — 400×578 on the 1024 grid, centred on 511.
///
/// These exact numbers were picked by rendering the alternatives side by side at 512pt and
/// at 40pt and looking at them. The two that matter:
///
///   - **The foot is narrower than the head** (148 against a 200 radius). Flare it wider
///     than the head and the silhouette stops being a keyhole and becomes a chess pawn —
///     that is the single failure this shape is prone to.
///   - **The waist is roughly a third of the head radius.** It is measured at the circle's
///     widest point, so the head overhangs by 126 either side. Those two notches are the
///     whole tell; shallow them and the mark turns into an undifferentiated blob at any
///     size small enough to matter.
let headRadius: CGFloat = 200
let headCentreY: CGFloat = 600
let waistHalfWidth: CGFloat = 74
let footHalfWidth: CGFloat = 148
let footY: CGFloat = 222
let footCorner: CGFloat = 44

func keyhole() -> CGPath {
	let cx = grid / 2
	let path = CGMutablePath()
	path.addEllipse(
		in: CGRect(
			x: cx - headRadius, y: headCentreY - headRadius,
			width: headRadius * 2, height: headRadius * 2))

	// The skirt, flaring from the neck to a flat, round-cornered foot.
	let skirt = CGMutablePath()
	skirt.move(to: CGPoint(x: cx - waistHalfWidth, y: headCentreY))
	skirt.addLine(to: CGPoint(x: cx - footHalfWidth, y: footY + footCorner))
	skirt.addArc(
		tangent1End: CGPoint(x: cx - footHalfWidth, y: footY),
		tangent2End: CGPoint(x: cx, y: footY), radius: footCorner)
	skirt.addArc(
		tangent1End: CGPoint(x: cx + footHalfWidth, y: footY),
		tangent2End: CGPoint(x: cx + footHalfWidth, y: footY + footCorner), radius: footCorner)
	skirt.addLine(to: CGPoint(x: cx + waistHalfWidth, y: headCentreY))
	skirt.closeSubpath()
	path.addPath(skirt)
	return path
}

let image = NSImage(size: NSSize(width: grid, height: grid), flipped: false) { _ in
	guard let context = NSGraphicsContext.current?.cgContext else { return false }
	context.setFillColor(NSColor.white.cgColor)
	context.addPath(keyhole())
	context.fillPath()
	return true
}

let destination = URL(fileURLWithPath: "Resources/AppIcon.icon/Assets/gaze-mark.png")
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: destination)
print("wrote \(destination.path)")
