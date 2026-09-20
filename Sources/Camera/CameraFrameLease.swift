import Foundation

struct CameraFrameLease {
	private(set) var generation: UUID?
	static let maximumAge: Duration = .milliseconds(500)

	mutating func begin() -> UUID {
		let identifier = UUID()
		generation = identifier
		return identifier
	}

	mutating func stop() { generation = nil }

	func accepts(_ identifier: UUID, capturedAt: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Bool {
		generation == identifier && capturedAt <= now && capturedAt.duration(to: now) <= Self.maximumAge
	}
}
