import Foundation
import OSLog

/// Opt-in callback/submission timing. These are not display presentation timestamps.
struct GazeRenderDiagnostics {
	enum Outcome { case submitted, busy, unavailable, failed }

	struct Summary {
		let callbacks: Int
		let submitted: Int
		let busy: Int
		let unavailable: Int
		let failed: Int
		let intervalP95Milliseconds: Double
		let intervalMaxMilliseconds: Double
		let drawMaxMilliseconds: Double
		let drawableMaxMilliseconds: Double
	}

	static let enabled = ProcessInfo.processInfo.environment["GAZE_RENDER_DIAGNOSTICS"] == "1"
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "RenderTiming")
	private var beganAt: Double?
	private var previousCallback: Double?
	private var intervals: [Double] = []
	private var callbacks = 0
	private var submitted = 0
	private var busy = 0
	private var unavailable = 0
	private var failed = 0
	private var drawMax = 0.0
	private var drawableMax = 0.0
	private var intervalMax = 0.0

	mutating func record(start: Double, end: Double, outcome: Outcome, drawableSeconds: Double = 0) -> Summary? {
		guard start.isFinite, end.isFinite, end >= start else { return nil }
		if let previousCallback, start < previousCallback { self = Self() }
		if beganAt == nil { beganAt = start }
		if let previousCallback {
			let interval = start - previousCallback
			intervalMax = max(intervalMax, interval)
			if intervals.count < 512 { intervals.append(interval) }
		}
		previousCallback = start
		callbacks += 1
		drawMax = max(drawMax, end - start)
		if drawableSeconds.isFinite && drawableSeconds >= 0 { drawableMax = max(drawableMax, drawableSeconds) }
		switch outcome {
		case .submitted: submitted += 1
		case .busy: busy += 1
		case .unavailable: unavailable += 1
		case .failed: failed += 1
		}
		guard let beganAt, end - beganAt >= 2 else { return nil }
		let summary = finish()
		previousCallback = start
		self.beganAt = end
		return summary
	}

	mutating func finish() -> Summary? {
		guard callbacks > 0 else { return nil }
		let sorted = intervals.sorted()
		let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
		let summary = Summary(callbacks: callbacks, submitted: submitted, busy: busy,
			unavailable: unavailable, failed: failed, intervalP95Milliseconds: p95 * 1000,
			intervalMaxMilliseconds: intervalMax * 1000, drawMaxMilliseconds: drawMax * 1000,
			drawableMaxMilliseconds: drawableMax * 1000)
		self = Self()
		return summary
	}

	static func log(_ summary: Summary, context: String, windowVisible: Bool, reason: String = "interval") {
		logger.notice("Render callbacks; context=\(context, privacy: .public) reason=\(reason, privacy: .public) windowVisible=\(windowVisible) callbacks=\(summary.callbacks) submitted=\(summary.submitted) busy=\(summary.busy) unavailable=\(summary.unavailable) failed=\(summary.failed) intervalP95Ms=\(summary.intervalP95Milliseconds) intervalMaxMs=\(summary.intervalMaxMilliseconds) drawMaxMs=\(summary.drawMaxMilliseconds) drawableMaxMs=\(summary.drawableMaxMilliseconds). Not presented-frame timing.")
	}
}
