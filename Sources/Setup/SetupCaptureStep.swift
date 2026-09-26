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
	var onClose: (() -> Void)? = nil
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
					isRequesting: isRequesting, onRequest: requestAccess, onBack: onBack, onClose: onClose)
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
			onBack: onBack,
			onClose: onClose
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
				Text(model.map { "\(Int($0.overallProgress * 100))%" } ?? "")
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
			case .multipleFaces: return "Only one face in view, please"
			case .analysisFailed: return "Hold still for a moment"
			case .detectionFailed: return "The camera frame couldn’t be read"
			default: return "Center your face"
			}
		}
		return model?.captureTitle ?? "Center your face"
	}

	private var caption: String {
		if case .failed = camera.state {
			if onRetry != nil, model?.phase != .complete {
				return "Make sure the built-in camera is available, then choose Try Again. Your face hasn’t been saved."
			}
			if onBack != nil {
				return "Make sure the built-in camera is available. Go back and try again. Your face hasn’t been saved."
			}
			return "Make sure the built-in camera is available and the lens is unobstructed. Your face hasn’t been saved."
		}
		guard isAuthorized else {
			return "Nothing is recorded until you enrol, and no images ever leave this Mac."
		}
		guard let model else { return "Starting the camera…" }
		if camera.faceMissing {
			switch camera.absence {
			case .multipleFaces: return "Gaze found more than one face. Only the person being enrolled should be in view."
			case .analysisFailed: return "Your face was found, but its details couldn’t be measured. Face the camera in even light."
			case .detectionFailed:
				if onBack != nil { return "Face analysis is unavailable for this frame. If it persists, go back and reopen capture." }
				return "Face analysis is unavailable for this frame. Check the camera and lighting, then continue."
			default: return "Look at the camera and fill the circle."
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
			openCameraSettings()
		case .restricted:
			// A policy block the app cannot clear itself, but Settings is still where
			// an administrator allows it — same destination as the denied state.
			openCameraSettings()
		@unknown default:
			openCameraSettings()
		}
	}

	/// System Settings > Privacy & Security > Camera, shared by every state whose
	/// only way forward is the user (or their administrator) allowing it there.
	private func openCameraSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
			NSWorkspace.shared.open(url)
		}
	}
}

struct SetupCameraAccessContent: View {
	var position: SetupPosition?
	let authorization: AVAuthorizationStatus
	var isRequesting = false
	var onRequest: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)?
	@State private var look: Double = 1
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	static func actionTitle(for status: AVAuthorizationStatus) -> String? {
		switch status {
		case .notDetermined: "Allow Camera Access"
		case .denied: "Open Camera Settings"
		// Restricted is set by an administrator or Screen Time and can't be changed in
		// System Settings, so a button would lead nowhere; authorized needs none.
		case .restricted, .authorized: nil
		@unknown default: "Open Camera Settings"
		}
	}

	var body: some View {
		SetupScaffold(
			position: position,
			title: authorization == .restricted ? "Camera access is restricted" : "Let Gaze see you",
			message: message,
			figureHeight: 200,
			onBack: onBack,
			onClose: onClose
		) {
			cameraFigure
		} detail: {
			Label("Recognition happens on this Mac. Nothing is recorded until you enrol.", systemImage: "lock")
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

	/// The companion glancing at the camera, on the tour's Pro Black backdrop.
	private var cameraFigure: some View {
		ZStack {
			if let url = Bundle.main.url(forResource: "tour-backdrop", withExtension: "png", subdirectory: "Art"),
				let nsImage = NSImage(contentsOf: url) {
				Image(nsImage: nsImage)
					.resizable()
					.scaledToFill()
			} else {
				Color(white: 0.06)
			}
			HStack(spacing: 40) {
				GazeLookingCompanion(look: authorization == .notDetermined ? look : 1, happy: false)
					.frame(width: 120, height: 120)
				cameraSymbol
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.accessibilityHidden(true)
		.task(id: animates) {
			guard animates else { return }
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(2.4))
				guard !Task.isCancelled else { return }
				look = look == 1 ? 0 : 1
			}
		}
	}

	/// Gentle motion only while still waiting on the system prompt, and never
	/// with Reduce Motion on.
	private var animates: Bool { authorization == .notDetermined && !reduceMotion }

	private var symbolName: String {
		switch authorization {
		case .denied: "camera.slash.fill"
		case .restricted: "lock.fill"
		case .notDetermined, .authorized: "camera.fill"
		@unknown default: "camera.fill"
		}
	}

	@ViewBuilder
	private var cameraSymbol: some View {
		if animates {
			symbolBase.symbolEffect(.pulse, options: .repeating)
		} else {
			symbolBase
		}
	}

	private var symbolBase: some View {
		Image(systemName: symbolName)
			.font(.system(size: 56, weight: .medium))
			.foregroundStyle(.white)
			.symbolRenderingMode(.monochrome)
	}

	private var message: String {
		switch authorization {
		case .notDetermined:
			"Gaze uses your built-in camera to recognise your face.\nYour camera stays off until you choose Allow.\nChoose Allow when macOS asks for camera access."
		case .denied:
			"Camera access is off. Enable Gaze in Privacy & Security → Camera, then return here to continue."
		case .restricted:
			"A system policy is blocking the camera. Ask your Mac’s administrator to allow access before continuing."
		default:
			"Camera access is unavailable. Close setup and try again."
		}
	}
}
