import Foundation

enum RecognitionScanPacing {
	static let minimumPollInterval: Duration = .milliseconds(60)

	/// Recognition work counts toward the interval instead of adding another sleep.
	static func delay(since previousPoll: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Duration {
		max(.zero, minimumPollInterval - previousPoll.duration(to: now))
	}
}
