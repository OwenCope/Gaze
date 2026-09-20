@preconcurrency import AVFoundation
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
	private(set) var evidenceContinuity = CameraEvidenceContinuity()
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
	private(set) var analyzedFrames: UInt64 = 0
	private(set) var expiredFrames: UInt64 = 0

	/// `uniqueID` of the camera this session is bound to, recorded at enrolment.
	private(set) var boundDeviceID: String?
	private(set) var lastFrameCapturedAt: ContinuousClock.Instant?
	/// Observes every analysis result on the main actor, including rejected frames
	/// as indeterminate results. Polling only the latest frame can miss a brief face.
	var onFrameAnalyzed: ((FaceAbsence?, UInt64, ContinuousClock.Instant) -> Void)?
	private let capture = CameraCaptureDriver()
	private var lease = CameraFrameLease()
	private var starting = false
	private var observers: [NSObjectProtocol] = []
	private let sessionGate: CameraSessionGate

	init(accessScope: CameraSessionGate.Scope = .foreground) {
		sessionGate = CameraSessionGate(scope: accessScope)
		for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
			observers.append(NotificationCenter.default.addObserver(forName: name, object: capture.session, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self, self.lease.generation != nil else { return }
					self.stop()
					self.state = .failed("Camera capture was interrupted. Try again.")
				}
			})
		}
	}

	// MARK: - Lifecycle

	func start(pinnedDeviceID: String? = nil) async {
		guard state != .running, !starting, !Task.isCancelled else { return }
		let generation = lease.begin()
		analyzedFrames = 0
		expiredFrames = 0
		starting = true
		defer { if lease.generation == generation { starting = false } }
		guard sessionGate.begin(onInvalidation: { [weak self] in
			guard let self, self.lease.generation == generation else { return }
			self.stop()
			self.state = .failed("Camera paused when the Mac locked, slept or changed users. Reopen this window after unlocking to restart it.")
		}) else {
			// The lease generation was already minted above; release it so nothing
			// reads an open lease as an active capture.
			lease.stop()
			return
		}

		let authorized = await requestAccess()
		guard lease.generation == generation, sessionGate.isValid else { return }
		guard !Task.isCancelled else { stop(); return }
		guard authorized else {
			stop()
			state = .denied
			return
		}

		let device: AVCaptureDevice
		do {
			device = try CameraDevice.trusted(pinnedID: pinnedDeviceID)
		} catch {
			stop()
			state = .failed(String(describing: error))
			return
		}

		do {
			let running = try await capture.start(with: device) { [weak self] sample, absence, capturedAt in
				Task { @MainActor in
					guard let self, self.state == .running, self.lease.generation == generation,
						self.sessionGate.isValid else { return }
					self.analyzedFrames &+= 1
					guard self.lease.accepts(generation, capturedAt: capturedAt, now: .now) else {
						self.expiredFrames &+= 1
						self.onFrameAnalyzed?(.detectionFailed, self.analyzedFrames, capturedAt)
						return
					}
					let usable = absence == nil && sample.map { FrameQuality.isUsable($0) } == true
					guard self.evidenceContinuity.record(usable: usable, capturedAt: capturedAt) else {
						self.onFrameAnalyzed?(.detectionFailed, self.analyzedFrames, capturedAt)
						return
					}
					self.sample = sample
					self.absence = absence
					self.faceMissing = absence != nil
					self.lastFrameCapturedAt = capturedAt
					self.frameID &+= 1
					self.onFrameAnalyzed?(absence, self.analyzedFrames, capturedAt)
				}
			}
			guard lease.generation == generation, sessionGate.isValid else { return }
			guard !Task.isCancelled else { stop(); return }
			guard running else {
				stop()
				state = .failed("The camera did not start delivering video.")
				return
			}
		} catch {
			guard lease.generation == generation else { return }
			stop()
			state = .failed(error.localizedDescription)
			return
		}

		boundDeviceID = device.uniqueID
		state = .running
	}

	func stop() {
		sessionGate.end()
		evidenceContinuity.invalidate()
		lease.stop()
		starting = false
		capture.stop()
		state = .idle
		sample = nil
		faceMissing = true
		absence = .noFace
		boundDeviceID = nil
		lastFrameCapturedAt = nil
	}

	private func requestAccess() async -> Bool {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .authorized: return true
		case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
		default: return false
		}
	}

	func previewLayer() -> AVCaptureVideoPreviewLayer {
		let layer = AVCaptureVideoPreviewLayer(session: capture.session)
		layer.videoGravity = .resizeAspectFill
		return layer
	}

	isolated deinit {
		sessionGate.end()
		for observer in observers { NotificationCenter.default.removeObserver(observer) }
		capture.stop()
	}
}

private final class CameraCaptureDriver: @unchecked Sendable {
	let session = AVCaptureSession()
	private let output = AVCaptureVideoDataOutput()
	private let sessionQueue = DispatchQueue(label: "com.gazeunlock.Gaze.session", qos: .userInitiated)
	private let frameQueue = DispatchQueue(label: "com.gazeunlock.Gaze.capture", qos: .userInitiated)
	private var proxy: SampleProxy?

	func start(with device: AVCaptureDevice,
		onSample: @escaping @Sendable (FaceSample?, FaceAbsence?, ContinuousClock.Instant) -> Void) async throws -> Bool {
		try await withCheckedThrowingContinuation { continuation in
			sessionQueue.async { [self] in
				do {
					try configure(with: device, onSample: onSample)
					session.startRunning()
					continuation.resume(returning: session.isRunning)
				} catch { continuation.resume(throwing: error) }
			}
		}
	}

	func stop() {
		sessionQueue.async { [self] in
			output.setSampleBufferDelegate(nil, queue: nil)
			if session.isRunning { session.stopRunning() }
			proxy = nil
		}
	}

	private func configure(with device: AVCaptureDevice,
		onSample: @escaping @Sendable (FaceSample?, FaceAbsence?, ContinuousClock.Instant) -> Void) throws {
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

		let proxy = SampleProxy(onSample: onSample)
		self.proxy = proxy

		output.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
		]
		// Analysing stale frames just delays recognition, so drop rather than queue.
		output.alwaysDiscardsLateVideoFrames = true
		output.setSampleBufferDelegate(proxy, queue: frameQueue)

		session.outputs.forEach(session.removeOutput)
		guard session.canAddOutput(output) else {
			throw NSError(
				domain: "com.gazeunlock.Gaze", code: 2,
				userInfo: [NSLocalizedDescriptionKey: "Could not attach the video output."])
		}
		session.addOutput(output)
	}
}

// MARK: - Vision

/// Runs Vision off the main actor and hands finished samples back.
private final class SampleProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

	private let onSample: @Sendable (FaceSample?, FaceAbsence?, ContinuousClock.Instant) -> Void
	private let rectanglesRequest = VNDetectFaceRectanglesRequest()
	private let landmarksRequest = VNDetectFaceLandmarksRequest()
	private let qualityRequest = VNDetectFaceCaptureQualityRequest()

	init(onSample: @escaping @Sendable (FaceSample?, FaceAbsence?, ContinuousClock.Instant) -> Void) {
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
		let capturedAt = ContinuousClock.now
		guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)

		// Detect once, then hand the same observation to the two follow-up requests
		// rather than letting each re-detect.
		do {
			try handler.perform([rectanglesRequest])
		} catch {
			onSample(nil, .detectionFailed, capturedAt)
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
			onSample(nil, detected.isEmpty ? .noFace : .multipleFaces(detected.count), capturedAt)
			return
		}

		landmarksRequest.inputFaceObservations = [face]
		qualityRequest.inputFaceObservations = [face]
		do {
			try handler.perform([landmarksRequest, qualityRequest])
		} catch {
			onSample(nil, .analysisFailed, capturedAt)
			return
		}

		guard let landmarks = landmarksRequest.results?.first?.landmarks else {
			onSample(nil, .analysisFailed, capturedAt)
			return
		}

		let quality = qualityRequest.results?.first?.faceCaptureQuality ?? 0

		// Vision's own estimate when it gives one, geometry when it doesn't, per-axis
		// provenance always. Some revisions populate yaw but leave pitch nil, so the
		// axes decide separately, and a missing landmark estimate lands as
		// NaN/unavailable — never as a frontal zero the challenge could mistake for
		// a held-still head.
		let pose = FacePose.resolved(
			visionYaw: face.yaw?.doubleValue,
			visionPitch: face.pitch?.doubleValue,
			visionRoll: face.roll?.doubleValue,
			estimate: FacePose.estimate(from: landmarks))

		onSample(
			FaceSample(
				landmarks: landmarks,
				boundingBox: face.boundingBox,
				pose: pose,
				quality: quality,
				pixelBuffer: buffer),
			nil, capturedAt)
	}

}
