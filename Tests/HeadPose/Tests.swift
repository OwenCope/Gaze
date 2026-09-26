import CoreImage
import CoreVideo
import Foundation
import Vision

struct FaceSample {
	let pose: FacePose
	let landmarks: VNFaceLandmarks2D
}

@main
@MainActor
enum HeadPoseTests {
	static func main() throws {
		// Scalar samples from the recorded readout. Both excursions still matched;
		// these are not a replay of camera frames or an authentication result.
		for (action, baseline, excursion, returned) in [
			(LivenessChallenge.Action.turnLeft, [-0.08, -0.11, -0.10], [0.26, 0.41], -0.02),
			(.turnRight, [-0.02, -0.02, -0.02], [-0.54, -0.65], -0.11)
		] {
			let challenge = LivenessChallenge(action: action)
			for yaw in baseline { challenge.prepareBaseline(yaw: yaw, pitch: 0, eyes: 0.3, mouth: 0.1) }
			precondition(challenge.isBaselineReady)
			challenge.consume(yaw: excursion[0], pitch: 0, eyes: 0.3, mouth: 0.1)
			precondition(!challenge.isReturningToRest && !challenge.isComplete)
			challenge.consume(yaw: excursion[1], pitch: 0, eyes: 0.3, mouth: 0.1)
			precondition(challenge.isReturningToRest && !challenge.isComplete,
				"The recorded movement must agree with the mirrored demonstration")
			challenge.consume(yaw: returned, pitch: 0, eyes: 0.3, mouth: 0.1)
			precondition(challenge.isComplete)
			challenge.reset()
			precondition(!challenge.isComplete && !challenge.isBaselineReady)
		}
		precondition(sin(FacePose(yaw: 0.4, pitch: 0, roll: 0).ringAngle) < -0.99)
		precondition(sin(FacePose(yaw: -0.4, pitch: 0, roll: 0).ringAngle) > 0.99)
		precondition(cos(FacePose(yaw: 0, pitch: 0.4, roll: 0).ringAngle) < -0.99)
		print("PASS: recorded scalar left/right excursions, return and reset; mirrored ring directions")
		if let directory = CommandLine.arguments.dropFirst().first {
			try verifyImages(in: URL(fileURLWithPath: directory, isDirectory: true))
		} else {
			print("Image audit not requested; pass the local extracted-camera directory to verify Vision/fallback signs.")
		}
	}

	private static func verifyImages(in directory: URL) throws {
		let displayedYaw = [-0.08, 0.41, 0.80, 1.11, 0.74, -0.31, -0.88, -1.15, -0.73, -0.11]
		let context = CIContext()
		var comparisons = 0
		for (index, rawYaw) in displayedYaw.enumerated() {
			let url = directory.appendingPathComponent("camera-\(index).png")
			guard let image = CIImage(contentsOf: url) else { throw CocoaError(.fileReadCorruptFile) }
			var buffer: CVPixelBuffer?
			precondition(CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height),
				kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
			context.render(image, to: buffer!)
			let handler = VNImageRequestHandler(cvPixelBuffer: buffer!, orientation: .up)
			let rectangles = VNDetectFaceRectanglesRequest()
			rectangles.revision = VNDetectFaceRectanglesRequestRevision3
			try handler.perform([rectangles])
			precondition(rectangles.results?.count == 1)
			let face = rectangles.results![0]
			guard let yaw = face.yaw?.doubleValue else { throw CocoaError(.coderValueNotFound) }
			let landmarks = VNDetectFaceLandmarksRequest()
			landmarks.inputFaceObservations = [face]
			try handler.perform([landmarks])
			guard let points = landmarks.results?.first?.landmarks else { throw CocoaError(.coderValueNotFound) }
			let estimated = FacePose.estimate(from: points)
			if abs(rawYaw) >= 0.3 {
				precondition(rawYaw * yaw < 0, "Preview mirror must reverse the camera readout sign")
				precondition(estimated.yaw * yaw > 0, "Fallback must agree with Vision on the same pixels")
				precondition(sin(FacePose(yaw: rawYaw, pitch: 0, roll: 0).ringAngle) * yaw > 0,
					"Enrollment guidance must point toward the mirrored face")
				let challenge = LivenessChallenge(action: yaw < 0 ? .turnLeft : .turnRight)
				for _ in 0..<3 { challenge.prepareBaseline(yaw: 0, pitch: 0, eyes: 0.3, mouth: 0.1) }
				for _ in 0..<2 { challenge.consume(yaw: rawYaw, pitch: 0, eyes: 0.3, mouth: 0.1) }
				precondition(challenge.isReturningToRest && !challenge.isComplete)
				comparisons += 1
			}
		}
		precondition(comparisons == 8)
		print("PASS: 8 nonfrontal image/readout pairs agree across Vision, fallback, challenge and mirrored ring; no enrollment or authentication used")
	}
}
