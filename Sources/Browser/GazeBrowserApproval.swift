import AppKit
import SwiftUI
import os

@MainActor
final class GazeBrowserApproval {
	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager
	private var listener: BrowserSocketListener?
	private var busy = false
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "BrowserApproval")

	init(store: FaceEnrollmentStore, lockout: LockoutManager) { self.store = store; self.lockout = lockout }

	func start() {
		guard policyPermitsApproval, listener == nil else { return }
		do {
			listener = try BrowserSocketListener(name: "gaze.sock", peer: "com.gazeunlock.Passwords") { [weak self] request in
				guard let self else { throw BrowserBridgeError.unavailable }
				return try await self.verify(request)
			}
		} catch { Self.logger.error("Browser approval listener unavailable; no fallback authorization is enabled.") }
	}

	private func verify(_ request: BrowserMessage) async throws -> BrowserMessage {
		if request.operation == "status" {
			try request.validateRequest(operation: "status")
			let session = AutofillSessionLease()
			defer { session.invalidate() }
			guard policyPermitsApproval, session.isValid else { throw BrowserBridgeError.unavailable }
			return request.response(operation: "status", error: readinessIssue)
		}
		try request.validateRequest(operation: "verify")
		guard readinessIssue == nil, policyPermitsApproval,
			UnlockGuard.embedderBlocker() == nil, store.isEnrolled, !store.isCorrupted,
			let pinnedCamera = store.pinnedCameraID, !pinnedCamera.isEmpty,
			lockout.mayAttempt() else { throw BrowserBridgeError.unavailable }
		let session = AutofillSessionLease()
		guard session.isValid else { throw BrowserBridgeError.cancelled }
		let detector = AntiSpoofGate(spoof: SpoofDetector())
		guard detector.isActive else { throw BrowserBridgeError.unavailable }
		busy = true
		defer { busy = false; session.invalidate() }
		lockout.recordFailure()
		guard !lockout.isLockedOut else { throw BrowserBridgeError.unavailable }
		let faceIDs = store.faces.map(\.id)
		let requestLease = BrowserRequestLease(request)
		let camera = CameraController()
		let panel = BrowserGuidancePanel(origin: request.origin)
		session.onInvalidation = { camera.stop(); panel.close() }
		defer { session.onInvalidation = nil; camera.stop(); panel.close() }
		func current() -> Bool {
			!Task.isCancelled && policyPermitsApproval && !Preferences.shared.isPaused && !captureWindowIsOpen && session.isValid && requestLease.permits(request)
				&& !store.isCorrupted && store.faces.map(\.id) == faceIDs && store.pinnedCameraID == pinnedCamera
				&& !lockout.isLockedOut
		}
		guard current() else { throw BrowserBridgeError.cancelled }
		panel.show()
		await camera.start(pinnedDeviceID: pinnedCamera)
		guard current(), camera.state == .running, camera.boundDeviceID == pinnedCamera else { throw BrowserBridgeError.unavailable }
		let evaluator = UnlockFrameEvaluator(embedder: store.embedder, faces: store.faces, antiSpoof: detector)
		let challenge = LivenessChallenge()
		var gate = UnlockChallengeGate()
		var frames = RecognitionFrameGate()
		var hold = RecognitionMatchHold()
		var lastContinuity: UInt64?
		let deadline = ContinuousClock.now.advanced(by: .seconds(30))
		while ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(40))
			guard current(), !panel.cancelled, panel.isVisible, camera.state == .running,
				camera.boundDeviceID == pinnedCamera else { throw BrowserBridgeError.cancelled }
			switch frames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: .now) {
			case .stalled: throw BrowserBridgeError.unavailable
			case .waiting: continue
			case .fresh(let continuous):
				if !continuous { hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning }
			}
			guard !gate.expired(at: .now) else { throw BrowserBridgeError.cancelled }
			guard let sample = camera.sample, FrameQuality.rejection(sample) == nil,
				let capturedAt = camera.lastFrameCapturedAt else {
				hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning
				continue
			}
			let frameID = camera.frameID
			let continuity = camera.evidenceContinuity.revision
			if lastContinuity != continuity { hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning }
			lastContinuity = continuity
			let result = await evaluator.evaluate(sample)
			guard current(), camera.state == .running, camera.boundDeviceID == pinnedCamera,
				camera.evidenceContinuity.permits(continuity, at: .now),
				capturedAt <= .now, capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge else {
				hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning
				continue
			}
			guard result.permitsMatchHold(requiresAntiSpoof: true), let face = result.face else {
				hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning
				continue
			}
			if hold.faceID != face.id { challenge.reset(); gate.reset() }
			let held = hold.consume(faceID: face.id, now: capturedAt, required: .seconds(2))
			if !gate.isPresented && !gate.isVerified { challenge.prepareBaseline(sample) }
			guard held || gate.isPresented else { continue }
			if !gate.isVerified {
				if !gate.isPresented {
					guard challenge.isBaselineReady else { continue }
					gate.present(at: .now, frameID: frameID)
					let hint = challenge.action.hint
					panel.motion = GazeFaceMotion(phase: .challenge(prompt: challenge.action.prompt,
						symbol: challenge.action.symbol, hintX: hint.x, hintY: hint.y, pulses: hint.pulses))
					continue
				}
				guard gate.admits(frameID: frameID, capturedAt: capturedAt, now: .now) else { continue }
				let consumption = challenge.consume(sample)
				if consumption.poseSourceInvalidated {
					hold.reset(); challenge.reset(); gate.reset(); panel.motion = .scanning
					continue
				}
				guard challenge.isComplete else { continue }
				gate.completeAction()
				if !gate.isVerified { challenge.next(); continue }
			}
			guard held, gate.isVerified, current(), panel.isVisible, !panel.cancelled,
				camera.evidenceContinuity.permits(continuity, at: .now),
				capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge else { throw BrowserBridgeError.cancelled }
			lockout.recordSuccess()
			guard !lockout.isLockedOut else { throw BrowserBridgeError.unavailable }
			return request.response(operation: "verified", approved: true)
		}
		throw BrowserBridgeError.cancelled
	}

	private var policyPermitsApproval: Bool {
		UnlockExecutionPolicy.current.permitsBrowserApproval(passwordReplayEnabled: PasswordReplaySafety.isEnabled)
	}

	private var captureWindowIsOpen: Bool {
		NSApp.windows.contains { $0.isVisible && (["enrollment", "test", "dataset"].contains($0.identifier?.rawValue ?? "") || ["Set Up Gaze", "Test Recognition", "Capture Dataset"].contains($0.title)) }
	}

	private var readinessIssue: String? {
		if busy { return "Gaze is already verifying another request." }
		if Preferences.shared.isPaused { return "Resume Gaze before approving a browser request." }
		if captureWindowIsOpen { return "Close face enrollment or Test Recognition before using browser approval." }
		if store.isCorrupted { return "Gaze cannot read the enrolled face. Open Gaze to review enrollment." }
		if !store.isEnrolled || store.pinnedCameraID?.isEmpty != false { return "Add a face in Gaze before using browser approval." }
		if UnlockGuard.embedderBlocker() != nil { return "Gaze’s recognition model is unavailable." }
		if !SpoofDetector.isAvailable { return "Gaze’s anti-spoof model is unavailable. Approval remains blocked." }
		if lockout.isLockedOut { return "Gaze is locked out. Review Gaze’s authentication settings." }
		return nil
	}
}

@MainActor
private final class BrowserGuidancePanel: ObservableObject {
	@Published var motion: GazeFaceMotion = .scanning
	@Published var cancelled = false
	let origin: BrowserOrigin
	private var window: NSPanel?
	var isVisible: Bool { window?.isVisible == true && window?.occlusionState.contains(.visible) == true }
	init(origin: BrowserOrigin) { self.origin = origin }
	func show() {
		let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 250),
			styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.level = .floating
		panel.hidesOnDeactivate = false
		panel.hasShadow = true
		panel.contentView = NSHostingView(rootView: BrowserGuidanceView(model: self))
		if let screen = NSScreen.main {
			panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 165, y: screen.visibleFrame.maxY - 264))
		}
		window = panel
		panel.orderFrontRegardless()
	}
	func close() { window?.orderOut(nil); window = nil }
}

private struct BrowserGuidanceView: View {
	@ObservedObject var model: BrowserGuidancePanel
	var body: some View {
		VStack(spacing: 12) {
			Text("Approve with Gaze").font(.headline)
			Text(model.origin.value).font(.caption).lineLimit(2).textSelection(.enabled)
			GazeLessonAnimation(motion: model.motion, paused: false, material: .charcoal).frame(width: 108, height: 108)
			Text(model.motion == .scanning ? "Look at Gaze" : "Follow this movement").font(.callout).foregroundStyle(.secondary)
			Button("Cancel") { model.cancelled = true }.gazeButton()
		}.padding(20).frame(width: 330, height: 250).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
	}
}
