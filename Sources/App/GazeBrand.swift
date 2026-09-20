import AppKit

enum GazeBrand {

	private static let whiteBody = toolbarBody(named: "gaze-toolbar-white")
	private static let blackBody = toolbarBody(named: "gaze-toolbar-black")

	private static func toolbarBody(named name: String) -> NSImage? {
		guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art") else { return nil }
		return NSImage(contentsOf: url)
	}

	static func toolbarIcon(dark: Bool, gaze: CGPoint = .zero, opaque: Bool = false) -> NSImage {
		let body = dark ? whiteBody : blackBody
		let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
			NSGraphicsContext.saveGraphicsState()
			defer { NSGraphicsContext.restoreGraphicsState() }
			let alpha = opaque ? 1.0 : (dark ? 0.82 : 0.92)
			if let body {
				body.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
			} else {
				(dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()
				NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5).fill()
			}
			let transform = AffineTransform(translationByX: 11 + gaze.x * 1.2, byY: 9.5 - gaze.y * 0.8)
			var tilt = transform
			tilt.rotate(byDegrees: -3)
			(dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
			for center in [-2.4, 2.4] {
				let eye = NSBezierPath(roundedRect: NSRect(x: center - 1.05, y: -2.1, width: 2.1, height: 4.2), xRadius: 1.05, yRadius: 1.05)
				eye.transform(using: tilt)
				eye.fill()
			}
			return true
		}
		image.isTemplate = false
		image.accessibilityDescription = "Gaze"
		return image
	}

	static let menuBarIcon: NSImage = {
		let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
			let outline = NSBezierPath()
			outline.move(to: NSPoint(x: 9, y: 16.25))
			outline.curve(to: NSPoint(x: 16.25, y: 9), controlPoint1: NSPoint(x: 14.5, y: 16.25), controlPoint2: NSPoint(x: 16.25, y: 14))
			outline.curve(to: NSPoint(x: 9, y: 1.75), controlPoint1: NSPoint(x: 16.25, y: 4), controlPoint2: NSPoint(x: 14.5, y: 1.75))
			outline.curve(to: NSPoint(x: 1.75, y: 9), controlPoint1: NSPoint(x: 3.5, y: 1.75), controlPoint2: NSPoint(x: 1.75, y: 4))
			outline.curve(to: NSPoint(x: 9, y: 16.25), controlPoint1: NSPoint(x: 1.75, y: 14), controlPoint2: NSPoint(x: 3.5, y: 16.25))
			outline.close()
			outline.append(NSBezierPath(roundedRect: NSRect(x: 5.25, y: 5.75, width: 2.5, height: 4.25), xRadius: 1.25, yRadius: 1.25))
			outline.append(NSBezierPath(roundedRect: NSRect(x: 10.25, y: 5.75, width: 2.5, height: 4.25), xRadius: 1.25, yRadius: 1.25))
			var tilt = AffineTransform(translationByX: 9, byY: 9)
			tilt.rotate(byDegrees: -4)
			tilt.translate(x: -9, y: -9)
			outline.transform(using: tilt)
			outline.windingRule = .evenOdd
			NSColor.black.setFill()
			outline.fill()
			return true
		}
		image.isTemplate = true
		image.accessibilityDescription = "Gaze"
		return image
	}()
}
