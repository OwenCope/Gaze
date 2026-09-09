import AVFoundation
import CoreImage
import Observation
import Vision

/// Why there is no usable face in the frame.
///
/// A reason rather than a boolean, because the two common cases need opposite responses
/// from the user and the app used to word them identically. `nil` means there *is* a face.
enum FaceAbsence: Equatable, Sendable {
	/// Nobody in frame.
	case noFace
	/// More than one face, so the app declines to guess which is the user. Also the
	/// shoulder-surfing case, which is why refusing is the safe default rather than
	/// picking the largest.
	case multipleFaces(Int)
	/// Vision could not run the detector on the frame at all.
	case detectionFailed
	/// A face was found but the landmark or quality pass failed on it.
	case analysisFailed

	/// One short line, for the test window.
	var summary: String {
		switch self {
		case .noFace: return "No face"
		case .multipleFaces(let count): return "\(count) faces in frame"
		case .detectionFailed: return "Couldn't read the frame"
		case .analysisFailed: return "Face found, couldn't measure it"
		}
	}
}

/// Head orientation, in radians, as reported by Vision.
struct FacePose: Sendable, Equatable {
	/// Vision's yaw. **Negative when the user turns to their own left.**
	///
	/// Measured, not reasoned about: `LivenessChallenge` was tested against a real head, and
	/// "Turn your head left" completes on a *fall* in this value. Everything that reads a
	/// direction reads this, in this convention, and there is no second one.
	///
	/// This was documented as the opposite — "negative when the user turns to their right" —
	/// while the code twenty lines below it recorded the measured fact. Two contradictory
	/// statements about the same axis in the same file is how the enrolment ring ended up
	/// mapping a head to the wrong side of itself for months.
	var yaw: Double
	/// Vision's pitch: **positive is chin DOWN**, negative is chin up.
	///
	/// This was documented the other way round for a long time, and both things that read
	/// it were wrong as a result — the nod challenge completed when you *raised* your head,
	/// and the enrolment ring's vertical axis ran upside down. The sign was never verified
	/// against the camera; it was assumed from the name and then built on twice.
	var pitch: Double
	var roll: Double   // head tilt

	static let zero = FacePose(yaw: 0, pitch: 0, roll: 0)

	/// Where this pose sits on the enrolment ring, in radians clockwise from up.
	///
	/// Both axes are worked out the same way: from where the face appears to point *on the
	/// screen*, because the ring is drawn around the preview and the user is aiming at it.
	///
	/// **Yaw is used raw.** `CameraPreview` mirrors the image, so a head turned to the user's
	/// own left appears pointing at the left of the screen — and a left turn lowers Vision's
	/// yaw, which `atan2` reads as counter-clockwise from up. The two flips cancel; the raw
	/// value is already in the ring's terms.
	///
	/// It was negated here for a long while, via a `mirroredYaw` helper, and the ring
	/// therefore lit the side opposite the one being looked at — turn towards a gap and the
	/// highlight ran away from you. The negation came from reasoning about which way a
	/// camera faces rather than from watching it, and it survived because the doc comment on
	/// `yaw` stated the sign backwards, so the two agreed with each other and not with the
	/// camera. The helper is gone rather than corrected: one convention, stated once, is
	/// what stops this happening a third time.
	///
	/// **Pitch is negated**, because Vision's positive pitch is chin *down* while the ring's
	/// zero is straight *up*.
	var ringAngle: Double { atan2(yaw, -pitch) }

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
	/// Why, when `faceMissing` is true. Nil while a face is present.
	private(set) var absence: FaceAbsence? = .noFace

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
	private let queue = DispatchQueue(label: "com.gazeunlock.Gaze.capture", qos: .userInitiated)
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
		absence = .noFace
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
				domain: "com.gazeunlock.Gaze", code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Could not read from the built-in camera."])
		}
		session.addInput(input)

		let proxy = SampleProxy { [weak self] sample, absence in
			Task { @MainActor in
				guard let self else { return }
				self.sample = sample
				self.absence = absence
				self.faceMissing = absence != nil
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
				domain: "com.gazeunlock.Gaze", code: 2,
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

	private let onSample: @Sendable (FaceSample?, FaceAbsence?) -> Void
	private let rectanglesRequest = VNDetectFaceRectanglesRequest()
	private let landmarksRequest = VNDetectFaceLandmarksRequest()
	private let qualityRequest = VNDetectFaceCaptureQualityRequest()

	init(onSample: @escaping @Sendable (FaceSample?, FaceAbsence?) -> Void) {
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
			onSample(nil, .detectionFailed)
			return
		}

		// Exactly one face, or we decline to guess which one is the user. Two faces in
		// frame is also the shoulder-surfing case, so refusing is the safe default.
		// Exactly one, and the count is worth reporting rather than flattening.
		//
		// "No face" was shown for both an empty room and a room with two faces in it, which
		// are opposite problems: one means step closer, the other means something in the
		// background is being read as a person. Anybody debugging the second one from the
		// first one's wording is going to conclude the camera is broken.
		let detected = rectanglesRequest.results ?? []
		guard detected.count == 1, let face = detected.first else {
			onSample(nil, detected.isEmpty ? .noFace : .multipleFaces(detected.count))
			return
		}

		landmarksRequest.inputFaceObservations = [face]
		qualityRequest.inputFaceObservations = [face]
		do {
			try handler.perform([landmarksRequest, qualityRequest])
		} catch {
			onSample(nil, .analysisFailed)
			return
		}

		guard let landmarks = landmarksRequest.results?.first?.landmarks else {
			onSample(nil, .analysisFailed)
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
			nil)
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
		//
		// **Negated, to agree with Vision.** This is a fallback for the frames where Vision
		// declines to report a pose, and it was reporting the opposite sign to the thing it
		// stands in for.
		//
		// Vision's yaw falls when the head turns to the user's left (measured against a real
		// head, via the liveness challenge). This estimator's raw `dx` rises: the camera
		// faces the user, so the user's left is the *image's* right, and turning that way
		// slides the nose toward higher x. Two estimators feeding one `FacePose.yaw` with
		// opposite conventions meant anything reading it — the enrolment ring, the turn
		// challenge — silently reversed on the frames where the fallback took over.
		//
		// Untested directly, because Vision almost always answers and there is no supported
		// way to make it decline. The sign is derived rather than measured; the measured
		// half is Vision's, above.
		let yaw = -Double(dx) * 1.6
		// The nose sits about 0.55 interocular widths below the eye line at rest; the
		// offset from that baseline is what indicates pitch.
		let pitch = (Double(dy) + 0.55) * 1.6
		let roll = Double(atan2(rightPupil.y - leftPupil.y, rightPupil.x - leftPupil.x))

		return FacePose(yaw: yaw, pitch: pitch, roll: roll)
	}
}
