import Foundation

private enum TestError: Error { case failed(String) }

/// Deterministic regression tests for walk-away absence proof.
///
/// Exercises the real production policy types (`PresenceAbsenceGate`,
/// `PresenceLockDecision`) with a synthetic clock (plain `Double` seconds) and
/// fake observations. No camera is opened, `walkAwayLock` is never enabled,
/// no enrollment or credentials are read, and `ScreenLock` is never touched.
@main
enum PresenceRegression {
	static var checks = 0
	static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
		guard condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	typealias Gate = PresenceAbsenceGate
	typealias Observation = PresenceAbsenceGate.Observation
	typealias Verdict = PresenceAbsenceGate.Verdict

	static func noFace(_ id: UInt64, captured: Double, observed: Double? = nil, age: Double = 0.1) -> Observation {
		Observation(sample: .noFace, frameID: id, capturedAt: captured, observedAt: observed ?? captured + age)
	}

	static func face(_ id: UInt64, captured: Double, age: Double = 0.1) -> Observation {
		Observation(sample: .facePresent, frameID: id, capturedAt: captured, observedAt: captured + age)
	}

	static func unknown(_ id: UInt64, captured: Double, age: Double = 0.1) -> Observation {
		Observation(sample: .indeterminate, frameID: id, capturedAt: captured, observedAt: captured + age)
	}

	static func main() throws {
		// Production policy constants, pinned so a quiet default change fails loudly.
		try expect(Gate().requiredAbsence == 4, "absence proof requires 4 seconds of no-face")
		try expect(Gate().maximumAge == 0.5, "freshness matches the 500ms frame lease")
		try expect(Gate().maximumGap == 1, "gap tolerates a couple of missed 400ms polls")

		// Startup-only delay: silence, or a single frame, never proves absence.
		var gate = Gate()
		try expect(!gate.hasEvidence, "fresh gate holds no absence evidence")
		try expect(gate.provenSpan == nil, "fresh gate proves no span")
		try expect(gate.update(noFace(1, captured: 0)) == .needMore, "first frame alone is not absence")
		try expect(gate.hasEvidence, "first frame starts — but does not complete — proof")

		// Sustained distinct fresh no-face proves absence at exactly the span.
		gate = Gate()
		var verdicts: [Verdict] = []
		for i in 0..<9 {
			verdicts.append(gate.update(noFace(UInt64(i + 1), captured: Double(i) * 0.5)))
		}
		try expect(verdicts.prefix(8).allSatisfy { $0 == .needMore }, "3.5s of no-face is not yet absence")
		try expect(verdicts.last == .absent, "distinct fresh no-face spanning 4s proves absence")
		try expect(gate.provenSpan == 4.0, "proven span measures capture times, not poll delay")

		// Production-rate polling (every 400ms) also completes, on capture span.
		gate = Gate()
		var last: Verdict = .needMore
		for i in 0..<11 {
			last = gate.update(noFace(UInt64(i + 1), captured: Double(i) * 0.4))
		}
		try expect(last == .absent, "400ms polls complete once captures span 4s")

		// A returning face cancels, and proof restarts from zero afterwards.
		gate = Gate()
		for i in 0..<5 {
			try expect(gate.update(noFace(UInt64(i + 1), captured: Double(i) * 0.5)) == .needMore, "pre-face polls stay needMore")
		}
		try expect(gate.update(face(6, captured: 2.5)) == .present, "returning face cancels confirmation")
		try expect(!gate.hasEvidence, "face wipes the accumulated window")
		for i in 0..<8 {
			try expect(gate.update(noFace(UInt64(7 + i), captured: 3.0 + Double(i) * 0.5)) == .needMore, "restarted proof needs a full fresh 4s")
		}
		try expect(gate.update(noFace(15, captured: 7.0)) == .absent, "fresh 4s after the face proves absence again")

		// A face immediately after proof still cancels (the watcher's final
		// camera recheck is the second net for this race).
		gate = Gate()
		for i in 0..<9 {
			_ = gate.update(noFace(UInt64(i + 1), captured: Double(i) * 0.5))
		}
		try expect(gate.update(face(10, captured: 4.5)) == .present, "face after proof cancels")

		// Unknown analysis output restarts the window without cancelling the check.
		gate = Gate()
		for i in 0..<3 {
			_ = gate.update(noFace(UInt64(i + 1), captured: Double(i) * 0.5))
		}
		try expect(gate.update(unknown(4, captured: 1.5)) == .needMore, "analysis failure is not presence")
		try expect(!gate.hasEvidence, "unknown interval wipes the window it interrupts")
		for i in 0..<8 {
			try expect(gate.update(noFace(UInt64(5 + i), captured: 2.0 + Double(i) * 0.5)) == .needMore, "proof after interruption needs a full fresh 4s")
		}
		try expect(gate.update(noFace(13, captured: 6.0)) == .absent, "absence after interruption completes on its own span")

		// Stale captures restart the window.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		try expect(gate.update(noFace(2, captured: 0.5, observed: 5.0)) == .needMore, "stale capture does not extend proof")
		try expect(!gate.hasEvidence, "stale capture wipes the window")
		for i in 0..<8 {
			_ = gate.update(noFace(UInt64(3 + i), captured: 5.0 + Double(i) * 0.5))
		}
		try expect(gate.update(noFace(11, captured: 9.0)) == .absent, "re-proof after staleness needs a full fresh 4s")

		// Repeated samples never extend proof.
		gate = Gate()
		try expect(gate.update(noFace(1, captured: 0)) == .needMore, "first distinct frame starts proof")
		for k in 0..<10 {
			try expect(
				gate.update(noFace(1, captured: 0, observed: 0.5 + Double(k) * 0.5)) == .needMore,
				"re-reading the same frame never advances proof")
		}
		try expect(gate.provenSpan == nil, "a repeated frame that becomes stale clears proof")
		for i in 1..<9 {
			_ = gate.update(noFace(UInt64(i + 1), captured: 6.0 + Double(i) * 0.5))
		}
		try expect(gate.update(noFace(10, captured: 10.5)) == .absent, "only distinct fresh frames complete new proof")

		// Future timestamps restart the window.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		try expect(gate.update(noFace(2, captured: 10.0, observed: 9.0)) == .needMore, "future capture is rejected")
		try expect(!gate.hasEvidence, "future capture wipes the window")

		// Reordered captures restart the window.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 2.0))
		try expect(gate.update(noFace(2, captured: 1.0, observed: 2.5)) == .needMore, "out-of-order capture is rejected")
		try expect(!gate.hasEvidence, "reordered capture wipes the window")

		// A gap beyond the allowance restarts the window instead of bridging it.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		try expect(gate.update(noFace(2, captured: 5.0)) == .needMore, "5s gap does not bridge proof")
		try expect(gate.provenSpan == 0, "gapped window restarts from the fresh capture")
		for i in 1..<9 {
			_ = gate.update(noFace(UInt64(2 + i), captured: 5.0 + Double(i) * 0.5))
		}
		try expect(gate.update(noFace(11, captured: 9.5)) == .absent, "post-gap proof completes on its own span")

		// A short gap within the allowance is tolerated.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		try expect(gate.update(noFace(2, captured: 0.9)) == .needMore, "sub-second gap keeps the window")

		// The final pre-lock conjunction: everything held allows the lock.
		let allowing = PresenceLockDecision(
			executionPermitsLocking: true, permissionsGranted: true,
			walkAwayEnabled: true, paused: false, cancelled: false, generationCurrent: true,
			sessionUnlockedAndActive: true, inputIdle: true, displayAssertionHeld: false,
			absenceProven: true)
		try expect(allowing.allowsLock, "proven absence with everything held locks")
		var decision = allowing
		decision.executionPermitsLocking = false
		try expect(!decision.allowsLock, "diagnostic execution policy refuses automatic locking")
		decision = allowing
		decision.permissionsGranted = false
		try expect(!decision.allowsLock, "missing camera or Accessibility permission prevents the check")
		decision = allowing
		decision.walkAwayEnabled = false
		try expect(!decision.allowsLock, "disabling walk-away stops the lock")
		decision = allowing
		decision.paused = true
		try expect(!decision.allowsLock, "pausing stops the lock")
		decision = allowing
		decision.cancelled = true
		try expect(!decision.allowsLock, "cancellation stops a stale confirmation")
		decision = allowing
		decision.generationCurrent = false
		try expect(!decision.allowsLock, "a task superseded by stop/restart cannot lock")
		decision = allowing
		decision.sessionUnlockedAndActive = false
		try expect(!decision.allowsLock, "unknown or locked session never locks")
		decision = allowing
		decision.inputIdle = false
		try expect(!decision.allowsLock, "resumed input stops the lock")
		decision = allowing
		decision.displayAssertionHeld = true
		try expect(!decision.allowsLock, "a held display assertion stops the lock")
		decision = allowing
		decision.absenceProven = false
		try expect(!decision.allowsLock, "unproven absence never locks")

		try checkInterruptedFrames()
		try checkRetrySchedule()
		print("\(checks) presence checks passed; synthetic clock and fake observations only")
	}

	static func checkInterruptedFrames() throws {
		var gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		_ = gate.update(unknown(1, captured: 0.1))
		try expect(!gate.hasEvidence, "indeterminate repeat clears evidence")
		_ = gate.update(noFace(3, captured: 0.2))
		_ = gate.update(noFace(2, captured: 0.3))
		try expect(!gate.hasEvidence, "regressed frame sequence clears evidence")
		for badTime in [Double.nan, .infinity, -.infinity] {
			gate = Gate()
			_ = gate.update(noFace(1, captured: 0))
			_ = gate.update(noFace(2, captured: badTime))
			try expect(!gate.hasEvidence, "nonfinite capture cannot preserve proof")
		}
		for duration in [0.0, -1, .nan, .infinity] {
			gate = Gate(requiredAbsence: duration)
			try expect(gate.update(noFace(1, captured: 0)) == .needMore && !gate.hasEvidence,
				"invalid confirmation duration cannot yield instant absence")
		}
		// A short sighting at 50 ms falls between the watcher's 400 ms polls.
		// Delivering every analyzed frame must expose it to the production gate.
		gate = Gate()
		_ = gate.update(noFace(1, captured: 0))
		try expect(gate.update(face(2, captured: 0.05)) == .present, "brief inter-poll face cancels")
		_ = gate.update(noFace(3, captured: 0.1))
		try expect(gate.provenSpan == 0, "following no-face cannot restore the old proof")
	}

	static func checkRetrySchedule() throws {
		var schedule = PresenceCheckSchedule()
		let start = ContinuousClock.now
		try expect(!schedule.permits(idleSeconds: 19.999, at: start), "active input never opens the camera")
		try expect(schedule.permits(idleSeconds: 20, at: start), "twenty seconds idle arms the first check")
		schedule.finished(at: start)
		for elapsed in [0, 5, 10, 20, 29] {
			try expect(!schedule.permits(idleSeconds: 100, at: start.advanced(by: .seconds(elapsed))),
				"idle reading does not restart camera within thirty seconds")
		}
		try expect(schedule.permits(idleSeconds: 100, at: start.advanced(by: .seconds(30))), "retry opens after thirty seconds")
		schedule.finished(at: start.advanced(by: .seconds(30)))
		try expect(!schedule.permits(idleSeconds: 0, at: start.advanced(by: .seconds(31))), "new input suppresses and resets retry")
		try expect(!schedule.permits(idleSeconds: 19, at: start.advanced(by: .seconds(50))), "new input gets the full idle wait")
		try expect(schedule.permits(idleSeconds: 20, at: start.advanced(by: .seconds(51))), "fresh input restores normal arming after twenty seconds")
		for invalid in [Double.nan, .infinity, -1] {
			try expect(!schedule.permits(idleSeconds: invalid, at: start), "unknown input state refuses a camera check")
		}
	}
}
