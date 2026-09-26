import CoreGraphics
import CoreVideo
import Foundation

// Synthetic checks for the two passive deny cues. No camera, no models: buffers are
// painted by hand (achromatic fills, so the BGRA/RGBA channel order is irrelevant)
// and the face rect is centred, so the top-left Core Graphics origin and Vision's
// lower-left origin agree.

func denyBuffer(width: Int, height: Int, grey: CGFloat) -> CVPixelBuffer {
	var buffer: CVPixelBuffer?
	precondition(
		CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
			== kCVReturnSuccess && buffer != nil, "synthetic buffer must allocate")
	let locked = buffer!
	CVPixelBufferLockBaseAddress(locked, [])
	defer { CVPixelBufferUnlockBaseAddress(locked, []) }
	guard
		let context = CGContext(
			data: CVPixelBufferGetBaseAddress(locked), width: width, height: height,
			bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(locked),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
				| CGBitmapInfo.byteOrder32Little.rawValue)
	else { preconditionFailure("synthetic bitmap must allocate") }
	context.setFillColor(red: grey, green: grey, blue: grey, alpha: 1)
	context.fill(CGRect(x: 0, y: 0, width: width, height: height))
	return locked
}

func denyPaintRect(_ buffer: CVPixelBuffer, _ rect: CGRect, grey: CGFloat) {
	CVPixelBufferLockBaseAddress(buffer, [])
	defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
	guard
		let context = CGContext(
			data: CVPixelBufferGetBaseAddress(buffer),
			width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
			bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
				| CGBitmapInfo.byteOrder32Little.rawValue)
	else { preconditionFailure("synthetic bitmap must allocate") }
	context.setFillColor(red: grey, green: grey, blue: grey, alpha: 1)
	context.fill(rect)
}

@main
enum CueDenyTests {
	static func main() {
		var checks = 0
		// A large bright rectangle enclosing the face covers the whole face box and
		// fires the bezel cue after 3 cumulative frames.
		var bezel = DeviceBezelGate()
		let spoof = denyBuffer(width: 224, height: 224, grey: 0.5)
		denyPaintRect(spoof, CGRect(x: 20, y: 20, width: 184, height: 184), grey: 1)
		let face = CGRect(x: 70, y: 70, width: 84, height: 84)
		precondition(DeviceBezelGate.measure(crop: spoof, faceRect: face) >= DeviceBezelGate.fireLevel,
			"enclosing rectangle must cover the face box")
		precondition(!bezel.record(frame: spoof, faceRect: face), "first cue frame must not fire")
		precondition(!bezel.record(frame: spoof, faceRect: face), "second cue frame must not fire")
		precondition(bezel.record(frame: spoof, faceRect: face), "bezel cue must fire on the third frame")
		checks += 4
		// A rectangle beside the face (a second person, a door frame) that clips a
		// corner of the face box never counts, however many frames it stays.
		var besideBezel = DeviceBezelGate()
		let beside = denyBuffer(width: 224, height: 224, grey: 0.5)
		denyPaintRect(beside, CGRect(x: 124, y: 10, width: 96, height: 150), grey: 1)
		for _ in 0..<5 {
			precondition(!besideBezel.record(frame: beside, faceRect: face), "a rectangle beside the face must not fire the bezel cue")
		}
		checks += 1
		// A flat mid-grey face fires neither cue.
		var quietBezel = DeviceBezelGate()
		var quietGlare = GlareCue()
		let flat = denyBuffer(width: 224, height: 224, grey: 0.5)
		for _ in 0..<3 {
			precondition(!quietBezel.record(frame: flat, faceRect: face), "flat grey must not count a bezel frame")
			precondition(!quietGlare.record(frame: flat, faceRect: face), "flat grey must not count a glare frame")
			checks += 2
		}
		precondition(!quietBezel.fired && !quietGlare.fired, "flat grey must fire neither cue")
		checks += 1
		// Below 50 px of face the glare cue abstains, however bright the face is.
		var small = GlareCue()
		let bright = denyBuffer(width: 224, height: 224, grey: 1)
		let tinyFace = CGRect(x: 92, y: 92, width: 40, height: 40)
		for _ in 0..<3 {
			precondition(!small.record(frame: bright, faceRect: tinyFace), "sub-50px face must abstain")
			checks += 1
		}
		precondition(!small.fired && small.confidence == 0, "sub-50px face must leave the cue unfired at zero confidence")
		checks += 1
		print("PASS: \(checks) deny-cue checks; synthetic inputs only.")
	}
}
