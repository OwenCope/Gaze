import CoreGraphics

struct LockScreenInputSnapshot: Equatable {
	let keys: UInt32
	let leftClicks: UInt32
	let rightClicks: UInt32

	static func current() -> Self {
		Self(
			keys: CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown),
			leftClicks: CGEventSource.counterForEventType(.hidSystemState, eventType: .leftMouseDown),
			rightClicks: CGEventSource.counterForEventType(.hidSystemState, eventType: .rightMouseDown))
	}
}

struct LockScreenInputGuard {
	private let initial: LockScreenInputSnapshot
	private(set) var wasInterrupted = false

	init(initial: LockScreenInputSnapshot) { self.initial = initial }

	mutating func permits(_ current: LockScreenInputSnapshot) -> Bool {
		if current != initial { wasInterrupted = true }
		return !wasInterrupted
	}
}
