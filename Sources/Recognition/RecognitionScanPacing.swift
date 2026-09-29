import Foundation

/// Opt-in per-tick timing for the lock-screen unlock loop.
///
/// Enabled only with `GAZE_RENDER_DIAGNOSTICS=1` (the same flag as the companion
/// renderer diagnostics) and logged under the same `RenderTiming` category so the two
/// correlate by wall-clock time. Timing and state names only: attempt ID, tick and
/// frame counters, capsule phase, and millisecond durations. No face data, embeddings,
/// landmarks, images, or credentials.
struct RenderTiming {
	static let enabled = ProcessInfo.processInfo.environment["GAZE_RENDER_DIAGNOSTICS"] == "1"
	static let windowMilliseconds: Double = 2_000

	struct Sample {
		let attemptID: String
		let tick: Int
		let frameID: UInt64
		let phase: String
		let tickStartMs: Double
		let capsuleUpdateMs: Double
		let callbackGapMs: Double
		let drawableWaitMs: Double
		let inferenceMs: Double
	}

	let attemptID: String
	var lastPrompt = "none"
	var lastIdentity = "none"
	private var samples: [Sample] = []
	private var windowStartMs: Double?

	init(attemptID: String) {
		self.attemptID = attemptID
	}

	/// Records one tick. Returns a one-line window summary once 2 seconds have elapsed,
	/// otherwise nil. The caller logs the returned string; nothing here touches the log.
	mutating func record(tick: Int, frameID: UInt64, phase: String, tickStartMs: Double,
		capsuleUpdateMs: Double, callbackGapMs: Double, drawableWaitMs: Double,
		inferenceMs: Double) -> String? {
		if windowStartMs == nil { windowStartMs = tickStartMs }
		samples.append(Sample(attemptID: attemptID, tick: tick, frameID: frameID, phase: phase,
			tickStartMs: tickStartMs, capsuleUpdateMs: capsuleUpdateMs, callbackGapMs: callbackGapMs,
			drawableWaitMs: drawableWaitMs, inferenceMs: inferenceMs))
		guard let start = windowStartMs, tickStartMs - start >= Self.windowMilliseconds else { return nil }
		let summary = describe()
		samples.removeAll(keepingCapacity: true)
		windowStartMs = tickStartMs
		return summary
	}

	private func describe() -> String {
		let gaps = samples.map(\.callbackGapMs).sorted()
		let gapP95 = gaps.isEmpty ? 0 : gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
		func maxOf(_ pick: (Sample) -> Double) -> Double { samples.map(pick).max() ?? 0 }
		let phases = Array(Set(samples.map(\.phase))).sorted().joined(separator: ",")
		let firstTick = samples.first?.tick ?? 0
		let lastTick = samples.last?.tick ?? 0
		let firstFrame = samples.first?.frameID ?? 0
		let lastFrame = samples.last?.frameID ?? 0
		return String(format: "Render window; attempt=%@ ticks=%d-%d n=%d frames=%llu-%llu phases=%@ callbackGapP95Ms=%.2f callbackGapMaxMs=%.2f capsuleUpdateMaxMs=%.2f drawableWaitMaxMs=%.2f inferenceMaxMs=%.2f prompt=%@ identity=%@. Not presented-frame timing.",
			attemptID, firstTick, lastTick, samples.count, firstFrame, lastFrame, phases, gapP95,
			maxOf { $0.callbackGapMs }, maxOf { $0.capsuleUpdateMs }, maxOf { $0.drawableWaitMs },
			maxOf { $0.inferenceMs }, lastPrompt, lastIdentity)
	}
}

enum RecognitionScanPacing {
	// About one camera frame at 30 fps, so no fresh frame waits a whole extra tick.
	static let minimumPollInterval: Duration = .milliseconds(33)

	/// Recognition work counts toward the interval instead of adding another sleep.
	static func delay(since previousPoll: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Duration {
		max(.zero, minimumPollInterval - previousPoll.duration(to: now))
	}
}
