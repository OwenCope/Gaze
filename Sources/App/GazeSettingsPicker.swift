import AppKit
import SwiftUI

struct GazeToolbarGaze {
	private(set) var origin = CGPoint.zero
	private(set) var target = CGPoint.zero
	private(set) var started = 0.0
	static let duration = 0.22

	func value(at time: Double) -> CGPoint {
		let progress = min(1, max(0, (time - started) / Self.duration))
		if progress >= 1 { return target }
		let eased = 1 - pow(1 - progress, 3)
		return CGPoint(x: origin.x + (target.x - origin.x) * eased, y: origin.y + (target.y - origin.y) * eased)
	}

	mutating func retarget(_ point: CGPoint, at time: Double) {
		origin = value(at: time)
		target = point
		started = time
	}

	static func target(at point: CGPoint, in bounds: CGRect, eyeCenter: CGPoint) -> CGPoint {
		guard bounds.contains(point) else { return .zero }
		return CGPoint(x: min(1, max(-1, (point.x - eyeCenter.x) / 55)),
			y: min(1, max(-1, (point.y - eyeCenter.y) / 18)))
	}
}

struct GazeSettingsPicker: NSViewRepresentable {
	@Binding var selection: SettingsPane
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

	func makeNSView(context: Context) -> GazeToolbarControl {
		let control = GazeToolbarControl()
		control.segmentCount = SettingsPane.toolbarPanes.count
		control.trackingMode = .selectOne
		control.segmentStyle = .automatic
		control.setAccessibilityLabel("Settings")
		for (index, pane) in SettingsPane.toolbarPanes.enumerated() {
			control.setLabel("", forSegment: index)
			control.setToolTip(pane.title, forSegment: index)
			control.setImageScaling(.scaleProportionallyDown, forSegment: index)
			if index != 0 {
				let image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)?
					.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
				control.setImage(image, forSegment: index)
			}
		}
		control.target = control
		control.action = #selector(GazeToolbarControl.choosePane)
		return control
	}

	func updateNSView(_ control: GazeToolbarControl, context: Context) {
		control.onSelection = { selection = SettingsPane.toolbarPanes[$0] }
		control.selectedSegment = SettingsPane.toolbarPanes.firstIndex(of: selection)
			?? SettingsPane.toolbarPanes.firstIndex(of: .about) ?? -1
		control.configure(dark: colorScheme == .dark, reducedMotion: reduceMotion, opaque: reduceTransparency)
	}

	static func dismantleNSView(_ control: GazeToolbarControl, coordinator: ()) {
		control.stopFollowing()
		control.onSelection = nil
	}
}

final class GazeToolbarControl: NSSegmentedControl {
	var onSelection: ((Int) -> Void)?
	private(set) var gaze = GazeToolbarGaze()
	private(set) var animationTimer: Timer?
	private(set) var isTrackingDrag = false
	private var gazeTracking: NSTrackingArea?
	private var resignation: NSObjectProtocol?
	private var dark = false
	private var reducedMotion = false
	private var opaqueBody = false

	@objc func choosePane() {
		guard selectedSegment >= 0, selectedSegment < segmentCount else { return }
		onSelection?(selectedSegment)
	}

	func configure(dark: Bool, reducedMotion: Bool, opaque: Bool) {
		guard self.dark != dark || self.reducedMotion != reducedMotion || opaqueBody != opaque || image(forSegment: 0) == nil else { return }
		self.dark = dark
		self.reducedMotion = reducedMotion
		opaqueBody = opaque
		if reducedMotion { stopFollowing() }
		drawGaze(at: ProcessInfo.processInfo.systemUptime)
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let gazeTracking { removeTrackingArea(gazeTracking) }
		let area = NSTrackingArea(rect: .zero,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
			owner: self, userInfo: nil)
		addTrackingArea(area)
		gazeTracking = area
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		stopFollowing()
		if let resignation { NotificationCenter.default.removeObserver(resignation) }
		resignation = nil
		if let window {
			resignation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.stopFollowing() }
			}
		}
	}

	override func mouseEntered(with event: NSEvent) { follow(event) }
	override func mouseMoved(with event: NSEvent) { follow(event) }
	override func mouseExited(with event: NSEvent) { retarget(.zero) }

	override func mouseDown(with event: NSEvent) {
		follow(event)
		beginFollowingDrag()
		defer { endFollowingDrag() }
		super.mouseDown(with: event)
	}

	func beginFollowingDrag() {
		guard !reducedMotion else { return }
		isTrackingDrag = true
		startTimer()
	}

	func endFollowingDrag() {
		isTrackingDrag = false
		advance()
	}

	func follow(_ event: NSEvent) {
		guard !reducedMotion, let window, event.window === window, window.isKeyWindow else { return }
		follow(at: convert(event.locationInWindow, from: nil))
	}

	private func follow(at point: CGPoint) {
		let firstWidth = width(forSegment: 0)
		let center = CGPoint(x: firstWidth > 0 ? firstWidth / 2 : bounds.width / CGFloat(max(1, segmentCount)) / 2, y: bounds.midY)
		var target = GazeToolbarGaze.target(at: point, in: bounds, eyeCenter: center)
		if !isFlipped { target.y = -target.y }
		retarget(target)
	}

	func retarget(_ point: CGPoint) {
		guard !reducedMotion, point != gaze.target else { return }
		gaze.retarget(point, at: ProcessInfo.processInfo.systemUptime)
		startTimer()
	}

	private func startTimer() {
		guard animationTimer == nil else { return }
		let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.advance() }
		}
		animationTimer = timer
		RunLoop.main.add(timer, forMode: .common)
		RunLoop.main.add(timer, forMode: .eventTracking)
	}

	func advance(at time: Double = ProcessInfo.processInfo.systemUptime) {
		if isTrackingDrag {
			guard let window, window.isKeyWindow, !reducedMotion else { stopFollowing(); return }
			follow(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
		}
		drawGaze(at: time)
		if !isTrackingDrag && time - gaze.started >= GazeToolbarGaze.duration {
			animationTimer?.invalidate()
			animationTimer = nil
		}
	}

	private func drawGaze(at time: Double) {
		guard segmentCount > 0 else { return }
		let image = GazeBrand.toolbarIcon(dark: dark, gaze: gaze.value(at: time), opaque: opaqueBody)
		image.accessibilityDescription = "Unlock"
		setImage(image, forSegment: 0)
	}

	func stopFollowing() {
		animationTimer?.invalidate()
		animationTimer = nil
		isTrackingDrag = false
		gaze = GazeToolbarGaze()
		drawGaze(at: ProcessInfo.processInfo.systemUptime)
	}

	deinit {
		animationTimer?.invalidate()
		if let resignation { NotificationCenter.default.removeObserver(resignation) }
	}
}
