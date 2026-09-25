import Foundation

struct FaceSample {
	var boundingBox = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
	var quality: Float = 0.8
	var hasQualityMeasurement = true
}

@main
enum FrameGateTests {
	static var checks = 0
	static func check(_ value: @autoclosure () -> Bool, _ message: String) {
		precondition(value(), message)
		checks += 1
	}

	static func main() {
		let start = ContinuousClock.now
		var gate = RecognitionFrameGate(now: start)
		check(gate.observe(id: 0, capturedAt: nil, now: start) == .waiting, "Wait for first capture")
		check(gate.observe(id: 1, capturedAt: start, now: start) == .fresh(continuous: false), "First capture starts fresh")
		check(gate.observe(id: 1, capturedAt: start, now: start) == .waiting, "Duplicate capture ignored")
		let next = start.advanced(by: .milliseconds(100))
		check(gate.observe(id: 2, capturedAt: next, now: next) == .fresh(continuous: true), "Adjacent capture continues")
		check(gate.observe(id: 3, capturedAt: start, now: next) == .waiting, "Reversed capture ignored")
		check(gate.observe(id: 3, capturedAt: next.advanced(by: .seconds(1)), now: next) == .waiting, "Future capture ignored")
		let late = next.advanced(by: .seconds(2))
		check(gate.observe(id: 3, capturedAt: late, now: late) == .stalled, "Stopped stream expires")
		check(gate.observe(id: 4, capturedAt: late, now: late) == .stalled, "Stall remains terminal")
		var absent = RecognitionFrameGate(now: start)
		check(absent.observe(id: 0, capturedAt: nil, now: start.advanced(by: .seconds(5))) == .stalled, "Missing first frame expires")

		var evidence = CameraEvidenceContinuity()
		var sample = FaceSample()
		check(evidence.record(usable: FrameQuality.isUsable(sample), capturedAt: start), "Usable frame recorded")
		let revision = evidence.revision
		check(evidence.permits(revision, at: next), "Fresh evidence permitted")
		sample.quality = 0
		check(evidence.record(usable: FrameQuality.isUsable(sample), capturedAt: next), "Bad-quality frame recorded")
		check(!evidence.permits(revision, at: next), "Measured zero invalidates prior evidence")
		sample.hasQualityMeasurement = false
		let recovery = next.advanced(by: .milliseconds(100))
		check(evidence.record(usable: FrameQuality.isUsable(sample), capturedAt: recovery), "Unavailable quality permits fresh capture")
		check(evidence.permits(evidence.revision, at: recovery), "Recovered evidence permitted")
		check(!evidence.record(usable: true, capturedAt: start), "Old capture refused")
		check(!evidence.permits(evidence.revision, at: recovery), "Old capture invalidates proof")
		evidence.invalidate()
		check(!evidence.permits(evidence.revision, at: recovery), "Stopped camera invalidates proof")

		var hold = RecognitionMatchHold()
		let owner = UUID()
		check(!hold.consume(faceID: owner, now: start, required: .milliseconds(300)), "First match starts hold")
		check(hold.consume(faceID: owner, now: recovery.advanced(by: .milliseconds(100)), required: .milliseconds(300)), "Same face completes hold")
		check(!hold.consume(faceID: UUID(), now: recovery, required: .milliseconds(300)), "Different face resets hold")
		hold.reset()
		check(hold.faceID == nil, "Reset clears identity")
		print("PASS: \(checks) frame-gate and quality-continuity checks")
	}
}
