import AppKit

@MainActor final class LockScreenSpace {
	static let shared = LockScreenSpace()
	var isAvailable = true
	func adopt(_ window: NSWindow) {}
	func release(_ window: NSWindow) {}
}

@MainActor final class LookTargetOverlay {
	enum Side { case leading, trailing }
	static let shared = LookTargetOverlay()
	func show(side: Side) {}
	func hide() {}
}
