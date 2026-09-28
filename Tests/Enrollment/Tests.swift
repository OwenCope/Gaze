import Foundation

struct Faceprint: Equatable {
	var values: [Float]
	var source: String
	static func normalized(_ values: [Float], source: String) -> Faceprint? {
		let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
		guard !source.isEmpty, norm.isFinite, norm > 0 else { return nil }
		return Faceprint(values: values.map { $0 / norm }, source: source)
	}
}

struct FaceSample {
	var boundingBox = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
	var quality: Float = 0.8
	var hasQualityMeasurement = true
	var pose = FacePose.zero
}

protocol FaceEmbedder {
	var identifier: String { get }
	var usesCosineSimilarity: Bool { get }
	var matchThreshold: Float { get }
	func embed(_ sample: FaceSample) -> Faceprint?
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float
	func embedUpperFace(_ sample: FaceSample) -> Faceprint?
}

extension FaceEmbedder {
	/// Matches the production default: no upper-face print, so enrolment captures none.
	func embedUpperFace(_ sample: FaceSample) -> Faceprint? { nil }
}

final class FixtureEmbedder: FaceEmbedder {
	let identifier = "fixture-embedder"
	let usesCosineSimilarity = true
	let matchThreshold: Float = 0.5
	var available = true
	var calls = 0
	func embed(_ sample: FaceSample) -> Faceprint? {
		calls += 1
		return available ? Faceprint(values: [1, 0], source: identifier) : nil
	}
	func similarity(_ a: Faceprint, _ b: Faceprint) -> Float {
		zip(a.values, b.values).reduce(0) { $0 + $1.0 * $1.1 }
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
		for _ in 0..<5 { model.consume(frontal) }
		check(model.phase == .positioning && embedder.calls == 0, "Require a stable run before embedding")
		var blurred = frontal
		blurred.quality = 0.34
		model.consume(blurred)
		model.consume(frontal)
		check(model.phase == .positioning, "Poor-quality frame breaks the positioning run")
		for _ in 0..<4 { model.consume(frontal) }
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
		// Two passes, like Face ID: the first full ring starts the second.
		for lap in 0..<2 {
			if lap == 1 {
				check(model.phase != .complete, "The first full ring starts a second pass rather than finishing")
				for _ in 0..<8 where model.phase == .positioning { model.consume(frontal) }
			}
			for segment in 0..<EnrollmentModel.segmentCount {
				let angle = Double(segment) * 2 * .pi / Double(EnrollmentModel.segmentCount)
				var sample = frontal
				sample.pose.yaw = -sin(angle) * 0.3
				sample.pose.pitch = -cos(angle) * 0.3
				model.consume(sample)
				if model.phase == .complete { break }
			}
		}
		check(model.phase == .complete, "Two passes with frontal and both-side turns complete")
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
		let base = Date()
		guidance.now = { base }
		for _ in 0..<9 { guidance.consume(frontal) }
		check(guidance.captureStatus == .steady && guidance.instruction.contains("Gently turn"), "Centered face is detected, not misreported as absent")
		// The gap and stall rules apply on the second pass, so finish the first one.
		for segment in 0..<48 {
			let angle = (Double(segment) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.phase == .capturing(pass: 2), "A full first ring moves on to the second pass")
		for segment in 0..<48 where !(10...19).contains(segment) {
			let angle = (Double(segment) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.phase == .capturing(pass: 2) && guidance.progress > 0.75 && guidance.progress < 0.85, "Near-complete fixture retains a real gap below a full ring")
		check(guidance.targetSegment != nil && guidance.instruction.contains("fill the circle"), "Remaining gap has actionable guidance")
		let gapProgress = guidance.progress
		let gapPrints = guidance.prints
		guidance.consume(blurred)
		check(guidance.captureStatus == .lowQuality && guidance.instruction.contains("Face a light"), "Quality rejection explains detected face")
		check(!guidance.instruction.contains("toward the gap"), "Quality rejection cannot hide behind stall guidance")
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
		guidance.now = { base.addingTimeInterval(4) }
		guidance.consume(frontal)
		check(guidance.instruction.contains("toward the gap"), "Stalled scan names the gap")
		guidance.now = { base }
		for _ in 0..<2 {
			guard let target = guidance.targetSegment else { break }
			check(!guidance.covered[target], "Highlighted target is unfilled")
			let angle = (Double(target) + 0.5) * 2 * .pi / 48
			var pose = frontal
			pose.pose.yaw = -sin(angle) * 0.3
			pose.pose.pitch = -cos(angle) * 0.3
			guidance.consume(pose)
		}
		check(guidance.phase == .capturing(pass: 2) && guidance.progress < 1, "A remaining gap does not finish before the stall rule")
		guidance.now = { base.addingTimeInterval(10) }
		var repeatPose = frontal
		repeatPose.pose.yaw = -sin(0.5) * 0.3
		repeatPose.pose.pitch = -cos(0.5) * 0.3
		guidance.consume(repeatPose)
		check(guidance.phase == .complete, "Six-second stall with minimums met completes")
		check(guidance.targetSegment == nil, "Completion clears gap guidance")
		check(guidance.covered.allSatisfy { $0 }, "A finished scan shows a full ring")
		print("PASS: \(checks) enrollment checks; generated poses and dummy vectors only, no camera, store, credentials or system authentication.")
		await SetupLifecycleTests.run()
	}
}
