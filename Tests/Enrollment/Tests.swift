import Foundation

typealias Faceprint = [Float]

struct FaceSample {
	var boundingBox = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
	var quality: Float = 0.8
	var pose = FacePose.zero
}

protocol FaceEmbedder {
	func embed(_ sample: FaceSample) -> Faceprint?
}

final class FixtureEmbedder: FaceEmbedder {
	var available = true
	var calls = 0
	func embed(_ sample: FaceSample) -> Faceprint? {
		calls += 1
		return available ? [1, 0] : nil
	}
}

@main
@MainActor
enum EnrollmentTests {
	static var checks = 0
	static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
		precondition(condition(), description)
		checks += 1
	}

	static func main() async {
		let embedder = FixtureEmbedder()
		let model = EnrollmentModel(embedder: embedder)
		let frontal = FaceSample()
		for _ in 0..<8 { model.consume(frontal) }
		check(model.phase == .positioning && embedder.calls == 0, "Require a stable run before embedding")
		var blurred = frontal
		blurred.quality = 0.34
		model.consume(blurred)
		model.consume(frontal)
		check(model.phase == .positioning, "Poor-quality frame breaks the positioning run")
		for _ in 0..<7 { model.consume(frontal) }
		embedder.available = false
		model.consume(frontal)
		check(model.phase == .positioning && model.prints.isEmpty, "Missing frontal embedding cannot start capture")
		embedder.available = true
		model.consume(frontal)
		check(model.phase == .capturing(pass: 1) && model.prints.count == 1, "Valid frontal sample starts capture")
		check(model.progress == 0, "Frontal pose does not invent directional coverage")
		var turned = frontal
		turned.pose.yaw = 0.3
		embedder.available = false
		model.consume(turned)
		check(model.progress == 0 && model.prints.count == 1, "Failed embedding cannot fill the ring")
		embedder.available = true
		model.consume(turned)
		check(model.progress > 0 && model.prints.count == 2, "Actual embedding fills a direction")
		let savedProgress = model.progress
		let savedCalls = embedder.calls
		model.consume(turned)
		check(model.progress == savedProgress && embedder.calls == savedCalls, "Repeated direction does not duplicate prints")
		for value: Double in [.nan, .infinity, -.infinity] {
			for axis in 0..<3 {
				var malformed = turned
				if axis == 0 { malformed.pose.yaw = value }
				if axis == 1 { malformed.pose.pitch = value }
				if axis == 2 { malformed.pose.roll = value }
				model.consume(malformed)
				check(model.currentAngle.isFinite && !model.isEngaged, "Malformed pose never reaches angle conversion")
				check(model.progress == savedProgress && embedder.calls == savedCalls, "Malformed pose cannot create enrollment evidence")
			}
		}
		for quality: Float in [.nan, .infinity, -1, 0, 0.34, 1.1] {
			var malformed = turned
			malformed.quality = quality
			model.consume(malformed)
			check(model.progress == savedProgress && embedder.calls == savedCalls, "Enrollment quality floor remains stricter than unlock")
		}
		var invalidBounds = turned
		invalidBounds.boundingBox.origin.x = -0.1
		model.consume(invalidBounds)
		check(model.progress == savedProgress && embedder.calls == savedCalls, "Invalid bounds never reach the embedder")
		model.consume(nil)
		check(model.phase == .capturing(pass: 1) && model.progress == savedProgress, "Brief absence preserves already captured directions")
		for pass in 1...2 {
			for segment in 0..<EnrollmentModel.segmentCount {
				let angle = Double(segment) * 2 * .pi / Double(EnrollmentModel.segmentCount)
				var sample = frontal
				sample.pose.yaw = -sin(angle) * 0.3
				sample.pose.pitch = -cos(angle) * 0.3
				model.consume(sample)
				if model.phase == .capturing(pass: 2) && pass == 1 { break }
			}
			check(pass == 1 ? model.phase == .capturing(pass: 2) : model.phase == .complete,
				"Both passes require captured directions")
		}
		check(model.prints.count >= 8, "Completed capture retains the existing print minimum")
		let completedPrints = model.prints
		model.consume(nil)
		model.consume(turned)
		check(model.phase == .complete && model.prints == completedPrints, "Completion cannot mutate after extra frames")
		model.reset()
		check(model.phase == .positioning && model.prints.isEmpty && model.progress == 0
			&& model.currentAngle == 0 && !model.isEngaged, "Reset clears all captured and visual state")
		let guidanceEmbedder = FixtureEmbedder()
		let guidance = EnrollmentModel(embedder: guidanceEmbedder)
		for _ in 0..<9 { guidance.consume(frontal) }
		check(guidance.captureStatus == .steady && guidance.instruction.contains("detected"), "Centered face is detected, not misreported as absent")
		for segment in 0..<48 where !(18...24).contains(segment) {
			let angle = (Double(segment) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.progress > 0.75 && guidance.progress < 1, "Near-complete fixture retains a real gap")
		check(guidance.targetSegment != nil && guidance.instruction.contains("bright tick"), "Remaining gap has actionable guidance")
		let gapProgress = guidance.progress
		let gapPrints = guidance.prints
		guidance.consume(blurred)
		check(guidance.captureStatus == .lowQuality && guidance.instruction.contains("is visible"), "Quality rejection explains detected face")
		check(!guidance.instruction.contains("Almost done"), "Quality rejection cannot hide behind almost done")
		guidance.consume(nil)
		check(guidance.captureStatus == .noFace, "Absence has distinct feedback")
		check(guidance.progress == gapProgress && guidance.prints == gapPrints, "Rejected samples preserve but never add evidence")
		var small = frontal
		small.boundingBox.size.height = 0.1
		guidance.consume(small)
		check(guidance.captureStatus == .tooSmall, "Small face gets its own guidance")
		guidanceEmbedder.available = false
		if let target = guidance.targetSegment {
			let angle = (Double(target) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.captureStatus == .embeddingUnavailable, "Embedding failure is not mistaken for missing face")
		check(guidance.progress == gapProgress, "Guidance does not auto-fill missing coverage")
		guidanceEmbedder.available = true
		for _ in 0..<48 {
			guard let target = guidance.targetSegment else { break }
			check(!guidance.covered[target], "Highlighted target is unfilled")
			let angle = (Double(target) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.phase == .capturing(pass: 2), "Following real missing directions completes first pass")
		check(guidance.progress == 0 && guidance.targetSegment == nil, "Second pass does not inherit stale gap guidance")
		print("PASS: \(checks) enrollment checks; generated poses and dummy vectors only, no camera, store, credentials or system authentication.")
		await SetupLifecycleTests.run()
	}
}
