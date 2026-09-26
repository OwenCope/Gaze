import AppKit
import SwiftUI

final class IsolatedToolbarWindow: NSWindow {
	var testKey = true
	var testPointer = CGPoint.zero
	override var isKeyWindow: Bool { testKey }
	override var mouseLocationOutsideOfEventStream: NSPoint { testPointer }
}

@Observable @MainActor final class ToolbarSelection {
	var pane = SettingsPane.face
}

@main
struct ToolbarTests {
	@MainActor static func main() throws {
		let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
		var motion = GazeToolbarGaze()
		motion.retarget(CGPoint(x: 1, y: -1), at: 1)
		let interrupted = motion.value(at: 1.08)
		motion.retarget(CGPoint(x: -1, y: 0.5), at: 1.08)
		precondition(motion.value(at: 1.08) == interrupted)
		precondition(motion.value(at: 2) == CGPoint(x: -1, y: 0.5))
		for frame in 0...120 {
			let point = motion.value(at: 1.08 + Double(frame) / 120)
			precondition(abs(point.x) <= 1 && abs(point.y) <= 1)
		}
		let bounds = CGRect(x: 0, y: 0, width: 240, height: 32)
		precondition(GazeToolbarGaze.target(at: CGPoint(x: 100, y: 33), in: bounds, eyeCenter: .zero) == .zero)
		precondition(GazeToolbarGaze.target(at: CGPoint(x: 100, y: -1), in: bounds, eyeCenter: .zero) == .zero)
		print("PASS: bounded 220ms gaze, interruption continuity, no overshoot, outside-strip neutral")

		for dark in [false, true] {
			let selection = ToolbarSelection()
			let host = NSHostingView(rootView: GazeSettingsPicker(selection: Binding(get: { selection.pane }, set: { selection.pane = $0 }))
				.fixedSize().padding(24).frame(width: 460, height: 100)
				.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
			host.frame = CGRect(x: 0, y: 0, width: 460, height: 100)
			let window = IsolatedToolbarWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
			window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
			window.contentView = host
			host.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
			func findControl(_ view: NSView) -> GazeToolbarControl? {
				if let control = view as? GazeToolbarControl { return control }
				return view.subviews.compactMap(findControl).first
			}
			guard let control = findControl(host) else { fatalError("Missing toolbar") }
			precondition(SettingsPane.toolbarPanes == [.face, .notch, .general, .about])
			precondition(control.segmentCount == SettingsPane.toolbarPanes.count && control.trackingMode == .selectOne)
			precondition(control.selectedSegment == 0 && control.image(forSegment: 0)?.accessibilityDescription == "Unlock")
			let initialSize = control.intrinsicContentSize
			for index in SettingsPane.toolbarPanes.indices {
				precondition(control.toolTip(forSegment: index) == SettingsPane.toolbarPanes[index].title)
				control.selectedSegment = index
				control.sendAction(control.action, to: control.target)
				precondition(selection.pane == SettingsPane.toolbarPanes[index])
			}
			control.selectedSegment = 0
			control.sendAction(control.action, to: control.target)
			func event(_ type: NSEvent.EventType, point: CGPoint, in eventWindow: NSWindow? = nil) -> NSEvent {
				if type == .mouseExited {
					return NSEvent.enterExitEvent(with: type, location: control.convert(point, to: nil), modifierFlags: [],
						timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
						eventNumber: 0, trackingNumber: 0, userData: nil)!
				}
				return NSEvent.mouseEvent(with: type, location: control.convert(point, to: nil), modifierFlags: [],
					timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: (eventWindow ?? window).windowNumber,
					context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
			}
			control.mouseMoved(with: event(.mouseMoved, point: CGPoint(x: control.bounds.maxX - 2, y: control.bounds.midY)))
			precondition(control.gaze.target.x > 0.9 && control.animationTimer != nil)
			control.advance(at: control.gaze.started + 1)
			precondition(control.animationTimer == nil)
			try snapshot(host, to: output.appendingPathComponent(dark ? "dark-right.png" : "light-right.png"))
			let target = control.gaze.target
			window.testKey = false
			control.mouseMoved(with: event(.mouseMoved, point: .zero))
			precondition(control.gaze.target == target)
			window.testKey = true
			let other = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
			control.follow(event(.mouseMoved, point: .zero, in: other))
			precondition(control.gaze.target == target)
			control.follow(event(.leftMouseDragged, point: CGPoint(x: control.bounds.maxX - 2, y: control.bounds.maxY + 10)))
			precondition(control.gaze.target == .zero)
			control.advance(at: control.gaze.started + 1)
			precondition(control.animationTimer == nil)
			try snapshot(host, to: output.appendingPathComponent(dark ? "dark-neutral.png" : "light-neutral.png"))
			window.testPointer = control.convert(CGPoint(x: control.bounds.maxX - 2, y: control.bounds.midY), to: nil)
			control.beginFollowingDrag()
			control.advance()
			precondition(control.isTrackingDrag && control.gaze.target.x > 0.9)
			window.testPointer = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.maxY + 10), to: nil)
			control.advance()
			precondition(control.gaze.target == .zero)
			control.endFollowingDrag()
			control.advance(at: control.gaze.started + 1)
			precondition(!control.isTrackingDrag && control.animationTimer == nil)
			control.configure(dark: dark, reducedMotion: true, opaque: false)
			control.mouseMoved(with: event(.mouseMoved, point: CGPoint(x: control.bounds.maxX - 2, y: control.bounds.midY)))
			precondition(control.gaze.target == .zero && control.animationTimer == nil)
			control.configure(dark: dark, reducedMotion: false, opaque: false)
			control.retarget(CGPoint(x: 1, y: 1))
			NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
			precondition(control.gaze.target == .zero && control.animationTimer == nil)
			control.retarget(CGPoint(x: -1, y: 0))
			control.mouseExited(with: event(.mouseExited, point: .zero))
			precondition(control.gaze.target == .zero)
			control.advance(at: control.gaze.started + 1)
			precondition(control.intrinsicContentSize == initialSize)
			let image = GazeBrand.toolbarIcon(dark: dark)
			let opaque = GazeBrand.toolbarIcon(dark: dark, opaque: true)
			let imageBitmap = try bitmap(image)
			let body = imageBitmap.colorAt(x: 11, y: 6)!.usingColorSpace(.deviceRGB)!
			let opaqueBody = try bitmap(opaque).colorAt(x: 11, y: 6)!.usingColorSpace(.deviceRGB)!
			precondition(body.alphaComponent < 0.96 && body.alphaComponent > 0.75)
			precondition(opaqueBody.alphaComponent > 0.99)
			precondition(dark ? body.redComponent > 0.75 : body.redComponent < 0.4)
			let neutralEyes = eyeCenter(imageBitmap, dark: dark)
			let rightEyes = eyeCenter(try bitmap(GazeBrand.toolbarIcon(dark: dark, gaze: CGPoint(x: 1, y: 0))), dark: dark)
			let upEyes = eyeCenter(try bitmap(GazeBrand.toolbarIcon(dark: dark, gaze: CGPoint(x: 0, y: -1))), dark: dark)
			precondition(rightEyes.x - neutralEyes.x > 0.65, "Eyes must move toward the pointer: \(neutralEyes) → \(rightEyes), bitmap \(imageBitmap.pixelsWide)")
			precondition(neutralEyes.y - upEyes.y > 0.4, "Pointer above must move eyes up")
			control.retarget(CGPoint(x: 1, y: 1))
			control.removeFromSuperview()
			precondition(control.animationTimer == nil && control.gaze.target == .zero)
			print("PASS: \(dark ? "dark/white" : "light/black") body, translucency, native selection, hover/drag-region bounds, inactive/other window isolation, exit, Reduce Motion, Reduce Transparency, teardown, stable layout")
		}
		precondition(GazeBrand.menuBarIcon.isTemplate)
		print("PASS: status icon unchanged; no authentication, camera, credentials, event monitor, or visible app window")
	}

	@MainActor static func eyeCenter(_ bitmap: NSBitmapImageRep, dark: Bool) -> CGPoint {
		var horizontal = 0.0
		var vertical = 0.0
		var count = 0.0
		for row in 5..<18 {
			for column in 5..<18 {
				let color = bitmap.colorAt(x: column, y: row)!.usingColorSpace(.deviceRGB)!
				let weight = color.alphaComponent * max(0, dark ? 0.65 - color.redComponent : color.redComponent - 0.5)
				horizontal += Double(column) * weight
				vertical += Double(row) * weight
				count += weight
			}
		}
		precondition(count > 2, "Both thick eyes must remain legible")
		return CGPoint(x: horizontal / count, y: vertical / count)
	}

	@MainActor static func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
		guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
			throw NSError(domain: "Gaze.ToolbarTests", code: 1)
		}
		return bitmap
	}

	@MainActor static func snapshot(_ view: NSView, to destination: URL) throws {
		view.layoutSubtreeIfNeeded()
		guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
			throw NSError(domain: "Gaze.ToolbarTests", code: 2)
		}
		view.cacheDisplay(in: view.bounds, to: bitmap)
		try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
	}
}
