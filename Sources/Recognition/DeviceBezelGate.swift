// Adapted from Glance by Jonathan Zhou (MIT License), https://github.com/jonnyoo/glance
// Catches a phone or tablet held up to the camera via its rectangular bezel enclosing
// the face. False-reject risk: a rectangle directly behind and around the face (a
// picture frame or window framing the head).

import CoreVideo
import Foundation
import Vision

/// Passive device-bezel deny cue.
///
/// Runs `VNDetectRectanglesRequest` over the same context crop the learned spoof
/// detector sees and measures how much of the face box the largest overlapping
/// rectangle covers. Deny-only: a fired cue rejects the frame, and the cue can never
/// contribute to a pass — absence of a rectangle is not evidence of liveness.
///
/// Counting is cumulative, not consecutive: 3 qualifying frames anywhere within the
/// scan fire the cue, forgiving the single-frame dropouts Vision produces mid-scan.
/// Once fired it latches for the rest of the scan; the owner resets per attempt.
///
/// Deliberately free of `FaceSample`: the cue measures a crop plus a face rect so the
/// regression suite can drive it with synthetic buffers.
struct DeviceBezelGate: Sendable {

	/// Fraction of the face box a rectangle must cover to count the frame. A phone or
	/// tablet showing a face encloses it, so it reads close to 1. Glance's 0.15 counted
	/// anything that clipped the face box: a second person's head or shoulders beside
	/// the owner, a door frame or a monitor edge, and it rejected real owners that way.
	static let fireLevel: Float = 0.6
	/// Qualifying frames within the scan that fire the cue (Glance `deviceFrames`).
	static let fireFrames = 3

	private(set) var framesCounted = 0
	private(set) var fired = false
	/// Latest reading, 0…1. Reported as the spoof score on the log line.
	private(set) var level: Float = 0

	mutating func reset() {
		framesCounted = 0
		fired = false
		level = 0
	}

	/// Measure one frame and count it toward firing. `crop` is the anti-spoof context
	/// crop; `faceRect` is the face box in crop pixels, lower-left origin to match
	/// Vision's normalized coordinates. Returns whether the cue has fired (latched).
	mutating func record(frame crop: CVPixelBuffer, faceRect: CGRect) -> Bool {
		level = Self.measure(crop: crop, faceRect: faceRect)
		if level >= Self.fireLevel {
			framesCounted += 1
			if framesCounted >= Self.fireFrames { fired = true }
		}
		return fired
	}

	/// Coverage fraction for one crop, without touching per-scan state.
	static func measure(crop: CVPixelBuffer, faceRect: CGRect) -> Float {
		let request = VNDetectRectanglesRequest()
		request.minimumConfidence = 0.6
		// Fraction of image area, not width/height.
		request.minimumSize = 0.15
		// Phone-in-portrait through near-square tablet crop.
		request.minimumAspectRatio = 0.35
		request.maximumAspectRatio = 1.0
		// Generous so a phone held at a slight angle still registers.
		request.quadratureTolerance = 30
		request.maximumObservations = 4
		let handler = VNImageRequestHandler(cvPixelBuffer: crop, options: [:])
		guard (try? handler.perform([request])) != nil,
			let observations = request.results, !observations.isEmpty
		else { return 0 }
		let width = CGFloat(CVPixelBufferGetWidth(crop))
		let height = CGFloat(CVPixelBufferGetHeight(crop))
		let faceArea = faceRect.width * faceRect.height
		guard width > 0, height > 0, faceArea > 0 else { return 0 }
		// Only a rectangle around the face can be a screen showing it: it must contain
		// the face's centre. Coverage is the intersection over the face box, so an
		// enclosing bezel reads 1.
		let centre = CGPoint(x: faceRect.midX, y: faceRect.midY)
		var bestCoverage: CGFloat = 0
		for observation in observations {
			let box = observation.boundingBox
			let rect = CGRect(
				x: box.minX * width, y: box.minY * height,
				width: box.width * width, height: box.height * height)
			guard rect.contains(centre) else { continue }
			let intersection = rect.intersection(faceRect)
			guard !intersection.isNull, !intersection.isEmpty else { continue }
			bestCoverage = max(bestCoverage, (intersection.width * intersection.height) / faceArea)
		}
		guard bestCoverage.isFinite else { return 0 }
		return Float(min(max(bestCoverage, 0), 1))
	}
}
