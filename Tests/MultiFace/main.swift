// Multi-face still-image check: runs Gaze's real detection, embedding and
// matcher on photos containing more than one face.
//
// Compiled together with the real Sources/Recognition/FaceEmbedder.swift and
// Sources/Recognition/FaceAligner.swift (see run.sh). Everything else here is
// a stub or a mirror of app logic:
//   - `FaceSample` is the same minimal stub Tests/RecognitionMath
//     uses: the only fields the embedder and aligner touch.
//   - `detectFaces` mirrors SampleProxy.analyse in
//     Sources/Camera/CameraController.swift (rectangles rev3, then landmarks
//     on the same handler, largest-first, up to 3 candidates).
//   - `bestScore` mirrors the match core shared by
//     FaceEnrollmentStore.matches (Sources/Recognition/FaceEnrollment.swift)
//     and UnlockFrameEvaluator.evaluate
//     (Sources/Recognition/UnlockFrameEvaluator.swift): best similarity over
//     the enrolled prints, matched when >= embedder.matchThreshold. The store
//     and evaluator themselves are not compiled: the store drags in Keychain
//     and @MainActor state, the evaluator drags in the anti-spoof gate.
import AppKit
import CoreImage
import CoreVideo
import Foundation
import Vision

struct FaceSample {
	let landmarks: VNFaceLandmarks2D
	let boundingBox: CGRect
	let pixelBuffer: CVPixelBuffer
}

// MARK: - Still-image detection

func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
	var buffer: CVPixelBuffer?
	let status = CVPixelBufferCreate(
		kCFAllocatorDefault, image.width, image.height,
		kCVPixelFormatType_32BGRA, nil, &buffer)
	guard status == kCVReturnSuccess, let buffer else { return nil }
	CVPixelBufferLockBaseAddress(buffer, [])
	defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
	guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
	// Buffer row 0 is the image top, CG bitmap row 0 is the bottom, hence the flip.
	guard
		let context = CGContext(
			data: base, width: image.width, height: image.height,
			bitsPerComponent: 8,
			bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
				| CGBitmapInfo.byteOrder32Little.rawValue)
	else { return nil }
	context.translateBy(x: 0, y: CGFloat(image.height))
	context.scaleBy(x: 1, y: -1)
	context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
	return buffer
}

func loadBuffer(_ url: URL) -> CVPixelBuffer? {
	guard
		let source = CGImageSourceCreateWithURL(url as CFURL, nil),
		let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
	else { return nil }
	return pixelBuffer(from: image)
}

func detectFaces(in buffer: CVPixelBuffer) -> [FaceSample] {
	let rectangles = VNDetectFaceRectanglesRequest()
	if VNDetectFaceRectanglesRequest.supportedRevisions.contains(
		VNDetectFaceRectanglesRequestRevision3)
	{
		rectangles.revision = VNDetectFaceRectanglesRequestRevision3
	}
	let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
	guard (try? handler.perform([rectangles])) != nil else { return [] }
	let found = (rectangles.results ?? [])
		.sorted { $0.boundingBox.area > $1.boundingBox.area }.prefix(3)
	let landmarksRequest = VNDetectFaceLandmarksRequest()
	var samples: [FaceSample] = []
	for face in found {
		landmarksRequest.inputFaceObservations = [face]
		guard (try? handler.perform([landmarksRequest])) != nil,
			let landmarks = landmarksRequest.results?.first?.landmarks
		else { continue }
		samples.append(
			FaceSample(landmarks: landmarks, boundingBox: face.boundingBox, pixelBuffer: buffer))
	}
	return samples
}

private extension CGRect {
	var area: CGFloat { width * height }
}

// MARK: - Fixture compositing

func loadImage(_ url: URL) -> NSImage? {
	guard
		let source = CGImageSourceCreateWithURL(url as CFURL, nil),
		let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
	else { return nil }
	return NSImage(
		cgImage: cg,
		size: NSSize(width: cg.width, height: cg.height))
}

/// Written at camera resolution: `NSImage` drawing happens at the screen's backing
/// scale, which doubled the composites to 4096 pixels wide, far larger than any frame
/// the camera delivers.
func writeJPEG(_ image: NSImage, to url: URL, longestSide: CGFloat = 1920) -> Bool {
	let scale = min(1, longestSide / max(image.size.width, image.size.height))
	let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
	guard
		let rep = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
	else { return false }
	rep.size = NSSize(width: width, height: height)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
	NSGraphicsContext.restoreGraphicsState()
	guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
	else { return false }
	do {
		try data.write(to: url)
		return true
	} catch { return false }
}

func scaledSize(of image: NSImage, height: CGFloat) -> NSSize {
	NSSize(width: image.size.width * height / image.size.height, height: height)
}

/// Two faces side by side on white, heights normalised; `leftFraction`
/// shrinks the left face (the small-face case).
func sideBySide(left: NSImage, right: NSImage, leftFraction: CGFloat) -> NSImage? {
	guard left.size.height > 0, right.size.height > 0 else { return nil }
	let height = max(left.size.height, right.size.height)
	let leftSize = scaledSize(of: left, height: height * leftFraction)
	let rightSize = scaledSize(of: right, height: height)
	let canvas = NSSize(width: leftSize.width + rightSize.width, height: height)
	let composed = NSImage(size: canvas)
	composed.lockFocus()
	NSColor.white.setFill()
	NSRect(origin: .zero, size: canvas).fill()
	left.draw(
		in: NSRect(x: 0, y: (height - leftSize.height) / 2, width: leftSize.width, height: leftSize.height),
		from: NSRect(origin: .zero, size: left.size), operation: .copy, fraction: 1)
	right.draw(
		in: NSRect(x: leftSize.width, y: (height - rightSize.height) / 2, width: rightSize.width, height: rightSize.height),
		from: NSRect(origin: .zero, size: right.size), operation: .copy, fraction: 1)
	composed.unlockFocus()
	return composed
}

/// Mirrored and slightly smaller on the original canvas, so enrolment is
/// recognisably the same face but not the identical image.
func mirroredScaled(_ image: NSImage, scale: CGFloat) -> NSImage? {
	let size = image.size
	guard size.width > 0, size.height > 0 else { return nil }
	let width = size.width * scale, height = size.height * scale
	let dst = NSRect(
		x: (size.width - width) / 2, y: (size.height - height) / 2,
		width: width, height: height)
	let out = NSImage(size: size)
	out.lockFocus()
	NSColor.white.setFill()
	NSRect(origin: .zero, size: size).fill()
	NSGraphicsContext.saveGraphicsState()
	let mirror = NSAffineTransform()
	mirror.translateX(by: dst.midX, yBy: 0)
	mirror.scaleX(by: -1, yBy: 1)
	mirror.translateX(by: -dst.midX, yBy: 0)
	mirror.concat()
	image.draw(
		in: dst, from: NSRect(origin: .zero, size: size),
		operation: .copy, fraction: 1)
	NSGraphicsContext.restoreGraphicsState()
	out.unlockFocus()
	return out
}

func ensureComposites(in dir: URL) -> Bool {
	let names = ["AB.jpg", "BA.jpg", "A_small_B.jpg", "A_enroll.jpg"]
	if names.allSatisfy({ FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) {
		return true
	}
	guard
		let a = loadImage(dir.appendingPathComponent("A.jpg")),
		let b = loadImage(dir.appendingPathComponent("B.jpg"))
	else {
		fputs("missing A.jpg or B.jpg in \(dir.path)\n", stderr)
		return false
	}
	guard
		let ab = sideBySide(left: a, right: b, leftFraction: 1),
		let ba = sideBySide(left: b, right: a, leftFraction: 1),
		let small = sideBySide(left: a, right: b, leftFraction: 0.6),
		let enroll = mirroredScaled(a, scale: 0.95),
		writeJPEG(ab, to: dir.appendingPathComponent("AB.jpg")),
		writeJPEG(ba, to: dir.appendingPathComponent("BA.jpg")),
		writeJPEG(small, to: dir.appendingPathComponent("A_small_B.jpg")),
		writeJPEG(enroll, to: dir.appendingPathComponent("A_enroll.jpg"))
	else {
		fputs("could not write composite fixtures\n", stderr)
		return false
	}
	return true
}

// MARK: - Check

var embedCount = 0
var embedSeconds = 0.0

func bestScore(
	_ sample: FaceSample, prints: [Faceprint], embedder: any FaceEmbedder
) -> Float? {
	let start = ContinuousClock.now
	guard let candidate = embedder.embed(sample) else { return nil }
	let elapsed = ContinuousClock.now - start
	embedCount += 1
	embedSeconds += Double(elapsed.components.seconds)
		+ Double(elapsed.components.attoseconds) / 1e18
	return prints.reduce(Float(0)) { max($0, embedder.similarity($1, candidate)) }
}

func boxString(_ box: CGRect) -> String {
	String(format: "x=%.2f y=%.2f w=%.2f h=%.2f", box.minX, box.minY, box.width, box.height)
}

func run() -> Int {
	let dir: URL = CommandLine.arguments.count > 1
		? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
	guard ensureComposites(in: dir) else { return 2 }

	let embedder = Embedders.best()
	print("embedder: \(embedder.identifier) threshold: \(embedder.matchThreshold)")
	if embedder.identifier.hasPrefix("landmark") {
		print("WARNING: Core ML model not found, using landmark-geometry fallback; expectations assume the model.")
	}

	// Enrol from the mirrored copy of A.
	guard let enrollBuffer = loadBuffer(dir.appendingPathComponent("A_enroll.jpg")) else {
		print("FAIL: no face detected in A_enroll.jpg")
		return 1
	}
	let enrollFaces = detectFaces(in: enrollBuffer)
	guard enrollFaces.count == 1, let enrolled = embedder.embed(enrollFaces[0]) else {
		print("FAIL: enrolment needs exactly one embeddable face, found \(enrollFaces.count)")
		return 1
	}
	let prints = [enrolled]
	print("enrolled 1 print from A_enroll.jpg")

	var failures = 0

	func scoreFaces(_ name: String) -> [(box: CGRect, score: Float?)]? {
		guard let buffer = loadBuffer(dir.appendingPathComponent(name)) else {
			print("FAIL: \(name): could not load image")
			failures += 1
			return nil
		}
		let faces = detectFaces(in: buffer)
			.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
		if faces.isEmpty {
			print("FAIL: \(name): no faces detected")
			failures += 1
			return nil
		}
		return faces.map { (box: $0.boundingBox, score: bestScore($0, prints: prints, embedder: embedder)) }
	}

	func report(_ name: String, faces: [(box: CGRect, score: Float?)]) {
		for (i, face) in faces.enumerated() {
			let scoreText = face.score.map { String(format: "%.3f", $0) } ?? "no-embedding"
			let decision: String
			if let score = face.score {
				decision = score >= embedder.matchThreshold ? "MATCH" : "no-match"
			} else {
				decision = "no-match"
			}
			print("\(name) face \(i) box=(\(boxString(face.box))) similarity=\(scoreText) \(decision)")
		}
	}

	func checkSingle(_ name: String, expectMatch: Bool, faceLabel: String) {
		guard let faces = scoreFaces(name) else { return }
		report(name, faces: faces)
		guard faces.count == 1 else {
			print("FAIL: \(name): expected 1 face (\(faceLabel)), found \(faces.count)")
			failures += 1
			return
		}
		let matched = (faces[0].score ?? -1) >= embedder.matchThreshold
		if matched == expectMatch {
			print("PASS: \(name)")
		} else {
			print("FAIL: \(name): expected \(expectMatch ? "a match" : "no match") (\(faceLabel))")
			failures += 1
		}
	}

	func checkPair(_ name: String, matchIndex: Int, matchLabel: String) {
		guard let faces = scoreFaces(name) else { return }
		report(name, faces: faces)
		guard faces.count == 2 else {
			print("FAIL: \(name): expected 2 faces, found \(faces.count)")
			failures += 1
			return
		}
		let matched = faces.map { ($0.score ?? -1) >= embedder.matchThreshold }
		if matched[matchIndex], !matched[1 - matchIndex] {
			print("PASS: \(name) (matched face is \(matchLabel))")
		} else {
			print("FAIL: \(name): expected exactly one match on \(matchLabel), got \(matched)")
			failures += 1
		}
	}

	checkSingle("A.jpg", expectMatch: true, faceLabel: "face A")
	checkSingle("B.jpg", expectMatch: false, faceLabel: "face B")
	checkPair("AB.jpg", matchIndex: 0, matchLabel: "left face A")
	checkPair("BA.jpg", matchIndex: 1, matchLabel: "right face A")
	checkPair("A_small_B.jpg", matchIndex: 0, matchLabel: "left small face A")

	if embedCount > 0 {
		print(String(format: "average %.1f ms per embedding over %d embeddings",
			embedSeconds / Double(embedCount) * 1000, embedCount))
	}
	if failures > 0 {
		print("FAIL: \(failures) case(s) failed")
		return 1
	}
	print("PASS: all multi-face cases passed")
	return 0
}

exit(Int32(run()))
