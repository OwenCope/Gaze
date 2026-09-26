import Foundation

struct RecognitionMatchHold {
	private(set) var faceID: UUID?
	private var since: ContinuousClock.Instant?

	mutating func reset() {
		faceID = nil
		since = nil
	}

	mutating func consume(faceID: UUID, now: ContinuousClock.Instant, required: Duration) -> Bool {
		if self.faceID != faceID || since.map({ now < $0 }) == true {
			self.faceID = faceID
			since = now
		}
		guard let since else { return false }
		return since.duration(to: now) >= required
	}
}

struct RecognitionRejectionHold {
	private var since: ContinuousClock.Instant?
	private var lastCapture: ContinuousClock.Instant?

	mutating func reset() {
		since = nil
		lastCapture = nil
	}

	mutating func consume(capturedAt: ContinuousClock.Instant, required: Duration) -> Bool {
		guard required > .zero else { reset(); return false }
		if let previous = lastCapture,
			capturedAt <= previous || previous.duration(to: capturedAt) > CameraEvidenceContinuity.maximumGap {
			reset()
		}
		if since == nil { since = capturedAt }
		lastCapture = capturedAt
		guard let since else { return false }
		return since.duration(to: capturedAt) >= required
	}
}

struct RecognitionFrameGate {
	/// The lock-screen camera is cold after sleep and regularly took 3.6 s or more to
	/// deliver its first frame, so 4 s ended real attempts before a frame arrived.
	/// Waiting longer releases nothing: no frame, no evidence, no password.
	static let firstFrameTimeout: Duration = .seconds(8)
	static let runningFrameTimeout: Duration = .seconds(1)

	enum Result: Equatable {
		case waiting
		case fresh(continuous: Bool)
		case stalled
	}

	private var lastID: UInt64?
	private var lastCapture: ContinuousClock.Instant?
	private var lastAdvance: ContinuousClock.Instant
	private var didStall = false
	var hasReceivedFrame: Bool { lastCapture != nil }

	init(now: ContinuousClock.Instant = .now) { lastAdvance = now }

	mutating func observe(id: UInt64, capturedAt: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Result {
		let timeout = hasReceivedFrame ? Self.runningFrameTimeout : Self.firstFrameTimeout
		guard !didStall, now >= lastAdvance, lastAdvance.duration(to: now) <= timeout else {
			didStall = true
			return .stalled
		}
		guard let capturedAt, capturedAt <= now,
			capturedAt.duration(to: now) <= CameraFrameLease.maximumAge,
			lastID != id, lastCapture.map({ capturedAt > $0 }) ?? true else {
			return .waiting
		}
		let continuous = lastCapture.map { $0.duration(to: capturedAt) <= CameraEvidenceContinuity.maximumGap } ?? false
		lastID = id
		lastCapture = capturedAt
		lastAdvance = now
		return .fresh(continuous: continuous)
	}
}
