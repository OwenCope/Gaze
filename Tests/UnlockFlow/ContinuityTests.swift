import Foundation

struct FaceSample {
	struct Pose {
		var yaw: Double = 0
		var pitch: Double = 0
		var roll: Double = 0
	}
	var boundingBox = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
	var quality: Float = 0.7
	var pose = Pose()
}

@main
enum ContinuityTests {
	static func main() {
		var checks = 0
		func check(_ condition: @autoclosure () -> Bool, _ message: String) {
			precondition(condition(), message)
			checks += 1
		}
		let now = ContinuousClock.now
		var evidence = CameraEvidenceContinuity()
		check(!evidence.permits(evidence.revision, at: now), "No camera evidence fails closed")
		evidence.record(usable: true, capturedAt: now)
		let token = evidence.revision
		check(evidence.permits(token, at: now), "Fresh usable sample is current")
		evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(100)))
		check(evidence.permits(token, at: now.advanced(by: .milliseconds(110))), "Continuous camera preserves in-flight proof")
		evidence.record(usable: false, capturedAt: now.advanced(by: .milliseconds(150)))
		check(!evidence.permits(token, at: now.advanced(by: .milliseconds(150))), "Bad frame invalidates inference")
		evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(200)))
		check(!evidence.permits(token, at: now.advanced(by: .milliseconds(200))), "Recovery never restores previous proof")
		let recovered = evidence.revision
		check(evidence.permits(recovered, at: now.advanced(by: .milliseconds(200))), "Recovered stream can start fresh verification")
		evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(441)))
		check(!evidence.permits(recovered, at: now.advanced(by: .milliseconds(441))), "Camera gap breaks continuity")
		let afterGap = evidence.revision
		check(!evidence.permits(afterGap, at: now.advanced(by: .milliseconds(400))), "Future capture is denied")
		check(!evidence.permits(afterGap, at: now.advanced(by: .milliseconds(942))), "Old capture is denied")
		check(!evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(440))), "Out-of-order callback rejected")
		check(!evidence.permits(evidence.revision, at: now.advanced(by: .milliseconds(450))), "Rejected callback cannot leave usable evidence")
		evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(500)))
		let beforeStop = evidence.revision
		evidence.invalidate()
		evidence.record(usable: true, capturedAt: now.advanced(by: .milliseconds(550)))
		check(!evidence.permits(beforeStop, at: now.advanced(by: .milliseconds(550))), "Stop/restart invalidates old results")
		var boundary = CameraEvidenceContinuity()
		boundary.record(usable: true, capturedAt: now)
		let boundaryToken = boundary.revision
		check(boundary.permits(boundaryToken, at: now.advanced(by: .milliseconds(500))), "Evidence remains usable at the exact lease boundary")
		check(!boundary.permits(boundaryToken, at: now.advanced(by: .nanoseconds(500_000_001))), "One nanosecond beyond the lease expires evidence")
		check(!boundary.permits(boundaryToken, at: now.advanced(by: .nanoseconds(-1))), "Evidence cannot be used before its capture time")
		let gapBoundary = now.advanced(by: .milliseconds(240))
		check(boundary.record(usable: true, capturedAt: gapBoundary), "Ordered delivery at the maximum gap is accepted")
		check(boundary.revision == boundaryToken, "Exact maximum gap preserves continuity")
		check(boundary.permits(boundaryToken, at: gapBoundary), "Original revision remains valid across an exact maximum gap")
		check(!boundary.record(usable: true, capturedAt: gapBoundary), "Duplicate delivery timestamps are rejected")
		check(!boundary.permits(boundary.revision, at: gapBoundary), "Duplicate delivery clears usable evidence even for the new revision")
		let recoveryTime = now.advanced(by: .milliseconds(241))
		boundary.record(usable: true, capturedAt: recoveryTime)
		let recoveryToken = boundary.revision
		check(boundary.permits(recoveryToken, at: recoveryTime), "New delivery can recover after a duplicate")
		check(!boundary.permits(boundaryToken, at: recoveryTime), "Duplicate recovery never revives an earlier proof")
		boundary.record(usable: true, capturedAt: now.advanced(by: .milliseconds(481)))
		check(boundary.revision == recoveryToken, "Recovered stream retains the exact gap boundary")
		let excessiveGap = now.advanced(by: .nanoseconds(721_000_001))
		boundary.record(usable: true, capturedAt: excessiveGap)
		check(!boundary.permits(recoveryToken, at: excessiveGap), "One nanosecond over the gap invalidates an in-flight proof")
		check(boundary.permits(boundary.revision, at: excessiveGap), "Post-gap evidence can start only a new proof")
		check(FrameQuality.rejection(FaceSample()) == nil, "Normal fixture accepted")
		for quality: Float in [.nan, .infinity, -.infinity, -0.1, 1.1] {
			var sample = FaceSample()
			sample.quality = quality
			check(FrameQuality.rejection(sample) == .invalidMeasurements, "Malformed quality denied")
		}
		for value: Double in [.nan, .infinity, -.infinity] {
			for axis in 0..<3 {
				var sample = FaceSample()
				if axis == 0 { sample.pose.yaw = value }
				if axis == 1 { sample.pose.pitch = value }
				if axis == 2 { sample.pose.roll = value }
				// FacePose reports an unavailable axis as NaN, so a missing angle must not make
				// the frame unidentifiable; liveness refuses non-finite pose on its own.
				check(FrameQuality.rejection(sample) != .invalidMeasurements, "Unavailable pose axis leaves the frame identifiable")
			}
		}
		for bounds in [CGRect(x: -0.1, y: 0.2, width: 0.3, height: 0.3),
			CGRect(x: 0.2, y: 0.2, width: 0, height: 0.3),
			CGRect(x: 0.2, y: 0.2, width: 0.3, height: 2),
			CGRect(x: CGFloat.nan, y: 0.2, width: 0.3, height: 0.3)] {
			var sample = FaceSample()
			sample.boundingBox = bounds
			check(FrameQuality.rejection(sample) == .invalidMeasurements, "Invalid geometry denied")
		}
		var sample = FaceSample()
		sample.quality = 0
		check(FrameQuality.rejection(sample) == nil, "Existing missing-quality sentinel preserved")
		sample.quality = 0.09
		check(FrameQuality.rejection(sample) == .tooBlurred, "Quality floor unchanged")
		sample.quality = 0.7
		sample.boundingBox.size.height = 0.17
		check(FrameQuality.rejection(sample) == .tooSmall, "Size floor unchanged")
		print("PASS: \(checks) evidence continuity and frame validity checks; synthetic inputs only.")
	}
}
