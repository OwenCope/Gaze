import AVFoundation
import CoreImage
import Observation
import Vision

/// Head orientation, in radians, as reported by Vision.
struct FacePose: Sendable, Equatable {
	var yaw: Double    // negative = turned left, positive = turned right
	var pitch: Double  // negative = chin down, positive = chin up
	var roll: Double   // head tilt

	static let zero = FacePose(yaw: 0, pitch: 0, roll: 0)

	/// Where this pose sits on the enrolment ring, in radians clockwise from up.
	///
	/// Yaw drives the horizontal axis and pitch the vertical, so looking up-and-right
	/// lands between the 12 and 3 o'clock ticks.
	var ringAngle: Double { atan2(yaw, pitch) }

	/// How far off-centre the head is, roughly 0...1 over a comfortable range.
	var offCentre: Double { min(1, hypot(yaw, pitch) / 0.55) }
}

/// One usable look at a face: the geometry Vision found, plus the frame it came from.
struct FaceSample: @unchecked Sendable {
	let landmarks: VNFaceLandmarks2D
	let boundingBox: CGRect
	let pose: FacePose
	/// Vision's own view of whether this frame is good enough to identify from.
	let quality: Float
	let pixelBuffer: CVPixelBuffer
}

/// Owns the capture session and turns frames into `FaceSample`s.
///
/// The session only ever binds to the built-in camera — see `CameraDevice` for why
/// that is a security control and not just a convenience.
@Observable
@MainActor
final class CameraController {

	enum State: Equatable {
		case idle
		case denied
		case failed(String)
		case running
	}

	private(set) var state: State = .idle
	/// The most recent frame containing exactly one usable face.
	private(set) var sample: FaceSample?
	/// True when a face was expected but the frame had none, or had several.
	private(set) var faceMissing = true

	/// Increments on every delivered frame.
	///
	/// Observers must drive off this rather than off `sample`, because two consecutive
	/// frames can carry an identical pose — a perfectly still head, or a Vision revision
	/// that doesn't populate yaw/pitch at all — and an observer watching the pose alone
	/// would then simply stop being called.
	private(set) var frameID: UInt64 = 0

	/// `uniqueID` of the camera this session is bound to, recorded at enrolment.
	private(set) var boundDeviceID: String?

	private let session = AVCaptureSession()
	private let output = AVCaptureVideoDataOutput()
	private let queue = DispatchQueue(label: "app.faceid.capture", qos: .userInitiated)
	private var proxy: SampleProxy?

	// MARK: - Lifecycle

	func start(pinnedDeviceID: String? = nil) async {
		guard state != .running else { return }

		guard await requestAccess() else {
			state = .denied
			return
		}

		let device: AVCaptureDevice
		do {
			device = try CameraDevice.trusted(pinnedID: pinnedDeviceID)
		} catch {
			state = .failed(String(describing: error))
			return
		}

		do {
			try configure(with: device)
		} catch {
			state = .failed(error.localizedDescription)
			return
		}

		boundDeviceID = device.uniqueID
		let session = self.session
		await Task.detached { session.startRunning() }.value
		state = .running
	}

	func stop() {
		guard state == .running else { return }
		let session = self.session
		Task.detached { session.stopRunning() }
		state = .idle
		sample = nil
		faceMissing = true
	}

	private func requestAccess() async -> Bool {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .authorized: return true
		case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
		default: return false
		}
	}

	private func configure(with device: AVCaptureDevice) throws {
		session.beginConfiguration()
		defer { session.commitConfiguration() }

		session.sessionPreset = .high

		session.inputs.forEach(session.removeInput)
		let input = try AVCaptureDeviceInput(device: device)
		guard session.canAddInput(input) else {
			throw NSError(
				domain: "app.faceid", code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Could not read from the built-in camera."])
		}
		session.addInput(input)

		let proxy = SampleProxy { [weak self] sample, missing in
			Task { @MainActor in
				guard let self else { return }
				self.sample = sample
				self.faceMissing = missing
				self.frameID &+= 1
			}
		}
		self.proxy = proxy

		output.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
		]
		// Analysing stale frames just delays recognition, so drop rather than queue.
		output.alwaysDiscardsLateVideoFrames = true
		output.setSampleBufferDelegate(proxy, queue: queue)

		session.outputs.forEach(session.removeOutput)
		guard session.canAddOutput(output) else {
			throw NSError(
				domain: "app.faceid", code: 2,
				userInfo: [NSLocalizedDescriptionKey: "Could not attach the video output."])
		}
		session.addOutput(output)
	}

	/// A layer that renders the live feed, for the enrolment preview.
	func previewLayer() -> AVCaptureVideoPreviewLayer {
		let layer = AVCaptureVideoPreviewLayer(session: session)
		layer.videoGravity = .resizeAspectFill
		return layer
	}
}

// MARK: - Vision

/// Runs Vision off the main actor and hands finished samples back.
private final class SampleProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

	private let onSample: @Sendable (FaceSample?, Bool) -> Void
	private let rectanglesRequest = VNDetectFaceRectanglesRequest()
	private let landmarksRequest = VNDetectFaceLandmarksRequest()
	private let qualityRequest = VNDetectFaceCaptureQualityRequest()

	init(onSample: @escaping @Sendable (FaceSample?, Bool) -> Void) {
		self.onSample = onSample

		// Pose comes from the *rectangles* request, not the landmarks one, and only from
		// revision 3 onwards. Running landmarks alone returns observations whose yaw and
		// pitch are nil, which reads downstream as a head that never moves.
		if VNDetectFaceRectanglesRequest.supportedRevisions.contains(
			VNDetectFaceRectanglesRequestRevision3)
		{
			rectanglesRequest.revision = VNDetectFaceRectanglesRequestRevision3
		}
	}

	func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)

		// Detect once, then hand the same observation to the two follow-up requests
		// rather than letting each re-detect.
		do {
			try handler.perform([rectanglesRequest])
		} catch {
			onSample(nil, true)
			return
		}

		// Exactly one face, or we decline to guess which one is the user. Two faces in
		// frame is also the shoulder-surfing case, so refusing is the safe default.
		guard let detected = rectanglesRequest.results, detected.count == 1,
			let face = detected.first
		else {
			onSample(nil, true)
			return
		}

		landmarksRequest.inputFaceObservations = [face]
		qualityRequest.inputFaceObservations = [face]
		do {
			try handler.perform([landmarksRequest, qualityRequest])
		} catch {
			onSample(nil, true)
			return
		}

		guard let landmarks = landmarksRequest.results?.first?.landmarks else {
			onSample(nil, true)
			return
		}

		let quality = qualityRequest.results?.first?.faceCaptureQuality ?? 0

		// Vision's own estimate when it gives one, geometry when it doesn't. Some
		// revisions populate yaw but leave pitch nil, so the two are decided separately.
		let landmarkPose = SampleProxy.pose(from: landmarks)
		let pose = FacePose(
			yaw: face.yaw?.doubleValue ?? landmarkPose.yaw,
			pitch: face.pitch?.doubleValue ?? landmarkPose.pitch,
			roll: face.roll?.doubleValue ?? landmarkPose.roll)

		onSample(
			FaceSample(
				landmarks: landmarks,
				boundingBox: face.boundingBox,
				pose: pose,
				quality: quality,
				pixelBuffer: buffer),
			false)
	}

	/// Estimates head orientation from landmark geometry.
	///
	/// A fallback for when Vision declines to report pose. The nose tip sits above the
	/// midpoint between the pupils when the head is level and centred; turning the head
	/// slides it sideways, tipping it slides it up or down. Measuring that displacement
	/// against the interocular distance cancels out how near the face is to the camera.
	///
	/// Approximate, and not a substitute for a real pose estimate — but the enrolment
	/// ring only needs a direction that moves consistently as the user turns.
	static func pose(from landmarks: VNFaceLandmarks2D) -> FacePose {
		guard
			let leftPupil = landmarks.leftPupil?.normalizedPoints.first,
			let rightPupil = landmarks.rightPupil?.normalizedPoints.first,
			let nose = landmarks.nose?.normalizedPoints, !nose.isEmpty
		else { return .zero }

		let eyeMidX = (leftPupil.x + rightPupil.x) / 2
		let eyeMidY = (leftPupil.y + rightPupil.y) / 2
		let interocular = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
		guard interocular > 0.001 else { return .zero }

		// Centroid of the nose region is steadier frame to frame than any single point.
		let noseX = nose.map(\.x).reduce(0, +) / CGFloat(nose.count)
		let noseY = nose.map(\.y).reduce(0, +) / CGFloat(nose.count)

		let dx = (noseX - eyeMidX) / interocular
		let dy = (noseY - eyeMidY) / interocular

		// Scale factors chosen so a comfortable head turn reaches roughly ±0.5 rad, which
		// is the range `FacePose.offCentre` normalises against.
		let yaw = Double(dx) * 1.6
		// The nose sits about 0.55 interocular widths below the eye line at rest; the
		// offset from that baseline is what indicates pitch.
		let pitch = (Double(dy) + 0.55) * 1.6
		let roll = Double(atan2(rightPupil.y - leftPupil.y, rightPupil.x - leftPupil.x))

		return FacePose(yaw: yaw, pitch: pitch, roll: roll)
	}
}
