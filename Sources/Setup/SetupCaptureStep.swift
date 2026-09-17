import SwiftUI
import AVFoundation
import AppKit

/// One screen for the whole capture: permission, framing, and the two passes.
///
/// Split into a "position your face" screen and a "scanning" screen, this needed
/// a Continue button between them — which is a button asking the user to confirm
/// something the app can already see. `EnrollmentModel` treats positioning and
/// capturing as two phases of one job, and the screen follows it: the ring is
/// hollow while it waits for a face and fills as the angles land, with no
/// transition and nothing to press.
///
/// The result is that this screen has no button at all once the camera is running.
/// It is the middle of the flow and the only part that is genuinely waiting on the
/// person rather than on a decision.
struct SetupCaptureStep: View {

	var position: SetupPosition?
	let camera: CameraController
	/// Nil until permission is granted — there is nothing to enroll into yet.
	let model: EnrollmentModel?
	var onAuthorized: () -> Void
	var onBack: (() -> Void)?
	var onRetry: (() -> Void)? = nil

	@State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
	@State private var isRequesting = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	private var isAuthorized: Bool { authorization == .authorized }

	private let ringSide: CGFloat = 300
	private let previewSide: CGFloat = 224

	var body: some View {
		Group {
			if isAuthorized {
				capture
			} else {
				SetupCameraAccessContent(position: position, authorization: authorization,
					isRequesting: isRequesting, onRequest: requestAccess, onBack: onBack)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
		}
		.onAppear { refresh() }
	}

	private var capture: some View {
		SetupScaffold(
			position: position,
			title: title,
			message: caption,
			figureHeight: ringSide,
			onBack: onBack
		) {
			ZStack {
				if let model {
					EnrollmentRing(
						covered: model.covered,
						currentAngle: model.currentAngle,
						isEngaged: model.isEngaged,
						targetSegment: model.targetSegment
					)
					.frame(width: ringSide, height: ringSide)
				} else {
					Circle()
						.strokeBorder(Theme.tickEmpty, lineWidth: 2)
						.frame(width: ringSide, height: ringSide)
				}

				if isAuthorized {
					CameraPreview(controller: camera)
						.frame(width: previewSide, height: previewSide)
						.clipShape(Circle())
						.overlay {
							// Dimmed while nobody is in frame. Looking away should be
							// visible without a line of text appearing and vanishing
							// each time someone glances at the trackpad.
							Circle()
								.fill(.black.opacity(camera.faceMissing ? 0.5 : 0))
								.animation(reduceMotion ? nil : Theme.Motion.quick, value: camera.faceMissing)
						}
				} else {
					Circle()
						.fill(.white.opacity(0.06))
						.frame(width: previewSide, height: previewSide)
						.overlay {
							Image(systemName: "video.slash.fill")
								.font(.system(size: 38, weight: .medium))
								.foregroundStyle(Theme.setupTertiary)
						}
				}
			}
		} actions: {
			if case .failed = camera.state, let onRetry, model?.phase != .complete {
				SetupButton(title: "Try Again", action: onRetry)
			} else {
				Text(model.map { "\(Int($0.progress * 100))%" } ?? "")
					.font(Typography.setupBody.weight(.semibold).monospacedDigit())
					.foregroundStyle(Theme.setupTertiary)
					.opacity(showsPercentage ? 1 : 0)
					.animation(reduceMotion ? nil : Theme.Motion.quick, value: showsPercentage)
					.frame(height: 28)
			}
		}
	}

	// MARK: - Words

	private var title: String {
		if case .failed = camera.state { return "The camera couldn’t start" }
		guard isAuthorized else { return "Gaze needs the camera" }
		if camera.faceMissing {
			switch camera.absence {
			case .multipleFaces: return "One face at a time"
			case .analysisFailed: return "Hold still for a moment"
			case .detectionFailed: return "The camera frame couldn’t be read"
			default: return "Center your face"
			}
		}
		return model?.captureTitle ?? "Center your face"
	}

	private var caption: String {
		if case .failed = camera.state {
			if onRetry != nil {
				return "Make sure the built-in camera is available, then try again. Your face hasn’t been saved."
			}
			return "Make sure the built-in camera is available. Go back and try again. Your face hasn’t been saved."
		}
		guard isAuthorized else {
			return "Nothing is recorded, and no images ever leave this Mac."
		}
		guard let model else { return " " }
		if camera.faceMissing {
			switch camera.absence {
			case .multipleFaces: return "Gaze found more than one face. Only the person being enrolled should be in view."
			case .analysisFailed: return "Your face was found, but its details couldn’t be measured. Face the camera in even light."
			case .detectionFailed: return "Face analysis is unavailable for this frame. If it persists, go back and reopen capture."
			default: return "Look at the camera and fill the circle. Your captured progress is kept."
			}
		}
		return model.instruction
	}

	/// Only while there is progress to report. At 0% it reads as stuck.
	private var showsPercentage: Bool {
		guard let model, case .capturing = model.phase else { return false }
		return model.progress > 0
	}

	// MARK: - Permission

	private func refresh() {
		authorization = AVCaptureDevice.authorizationStatus(for: .video)
		if isAuthorized { onAuthorized() }
	}

	private func requestAccess() {
		guard !isRequesting else { return }

		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .authorized:
			refresh()
		case .notDetermined:
			isRequesting = true
			AVCaptureDevice.requestAccess(for: .video) { _ in
				Task { @MainActor in
					isRequesting = false
					refresh()
				}
			}
		case .denied:
			// Refused once already: the system will never ask again, so the only way
			// forward is Settings. Sending them there beats a button that does nothing.
			if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
				NSWorkspace.shared.open(url)
			}
		case .restricted:
			refresh()
		@unknown default:
			refresh()
		}
	}
}

struct SetupCameraAccessContent: View {
	var position: SetupPosition?
	let authorization: AVAuthorizationStatus
	var isRequesting = false
	var onRequest: () -> Void
	var onBack: (() -> Void)?

	static func actionTitle(for status: AVAuthorizationStatus) -> String? {
		switch status {
		case .notDetermined: "Allow Camera Access"
		case .denied: "Open Camera Settings"
		default: nil
		}
	}

	var body: some View {
		SetupScaffold(
			position: position,
			title: authorization == .restricted ? "Camera access is restricted" : "Let Gaze see you",
			message: message,
			figureHeight: 132,
			onBack: onBack
		) {
			SetupGlyph(symbol: "camera")
		} detail: {
			Label("Recognition happens on this Mac. Nothing is recorded.", systemImage: "lock")
				.font(.system(size: 12))
				.foregroundStyle(Theme.setupSecondary)
				.padding(.top, 24)
		} actions: {
			if let title = Self.actionTitle(for: authorization) {
				SetupButton(title: isRequesting ? "Waiting for Permission…" : title, action: onRequest)
					.disabled(isRequesting)
			}
		}
	}

	private var message: String {
		switch authorization {
		case .notDetermined:
			"Gaze uses your built-in camera to recognise your face.\nChoose Allow when macOS asks for camera access."
		case .denied:
			"Camera access is off. Enable Gaze in Privacy & Security → Camera, then return here to continue."
		case .restricted:
			"A system policy is blocking the camera. Ask your Mac’s administrator to allow access before continuing."
		default:
			"Camera access is unavailable. Close setup and try again."
		}
	}
}
