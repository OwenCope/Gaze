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

	@State private var isAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
	@State private var isRequesting = false

	private let ringSide: CGFloat = 300
	private let previewSide: CGFloat = 224

	var body: some View {
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
						isEngaged: model.isEngaged
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
								.animation(Theme.Motion.quick, value: camera.faceMissing)
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
			// A button only where there is a decision. Once the camera is running the
			// screen is waiting on a face, not on a click.
			if !isAuthorized {
				SetupButton(title: isRequesting ? "Requesting…" : "Allow Camera Access", action: requestAccess)
					.disabled(isRequesting)
			} else {
				Text(model.map { "\(Int($0.progress * 100))%" } ?? "")
					.font(Typography.setupBody.weight(.semibold).monospacedDigit())
					.foregroundStyle(Theme.setupTertiary)
					.opacity(showsPercentage ? 1 : 0)
					.animation(Theme.Motion.quick, value: showsPercentage)
					.frame(height: 28)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
		}
		.onAppear { refresh() }
	}

	// MARK: - Words

	private var title: String {
		guard isAuthorized else { return "Gaze needs the camera" }
		switch model?.phase {
		case .capturing: return "Move your head slowly"
		default: return "Center your face"
		}
	}

	private var caption: String {
		guard isAuthorized else {
			return "Nothing is recorded, and no images ever leave this Mac."
		}
		guard let model else { return " " }
		if case .capturing = model.phase { return model.instruction }
		return camera.faceMissing ? "Look at the camera and fill the circle." : "Hold there."
	}

	/// Only while there is progress to report. At 0% it reads as stuck.
	private var showsPercentage: Bool {
		guard let model, case .capturing = model.phase else { return false }
		return model.progress > 0
	}

	// MARK: - Permission

	private func refresh() {
		let granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
		isAuthorized = granted
		if granted { onAuthorized() }
	}

	private func requestAccess() {
		guard !isRequesting else { return }

		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .authorized:
			refresh()
		case .notDetermined:
			isRequesting = true
			AVCaptureDevice.requestAccess(for: .video) { granted in
				Task { @MainActor in
					isRequesting = false
					isAuthorized = granted
					if granted { onAuthorized() }
				}
			}
		case .denied, .restricted:
			// Refused once already: the system will never ask again, so the only way
			// forward is Settings. Sending them there beats a button that does nothing.
			if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
				NSWorkspace.shared.open(url)
			}
		@unknown default:
			isAuthorized = false
		}
	}
}
