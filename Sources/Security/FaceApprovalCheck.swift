import AppKit
import SwiftUI
import os

/// One face check for approving something while the Mac is unlocked: an admin
/// prompt, `sudo`, a Shortcut. Shared so every one of them has the same rules.
///
/// The rules, in order: an enrolled face held for two seconds, anti-spoof, then a
/// nod. The nod is the consent, not just liveness: the panel names what is being
/// approved while it asks for it, so looking at the screen is never enough on its
/// own. Something that pops up a request while you happen to be in front of the
/// camera still needs you to read it and nod.
///
/// The check is shown in the notch panel, the same one as the lock screen.
@MainActor
final class FaceApprovalCheck {
	enum Outcome: Equatable {
		case approved
		/// Nothing was checked: Gaze isn't set up for it, it's paused, or it's locked out.
		case unavailable
		/// The request went away or the user stopped it. Not counted as a failure.
		case cancelled
		/// Ran out of time without a matching face and a nod. Counts toward lockout.
		case failed
	}

	private let store: FaceEnrollmentStore
	private let lockout: LockoutManager
	/// Kept here so its fold-away animation can finish after `run` returns.
	private var panel: NotchCapsuleController?
	private var busy = false
	private var detailsPanel: ApprovalDetailsPanel?
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "FaceApproval")

	/// What the person is consenting to, shown in full beside the notch while the
	/// check runs. The notch headline has room for one short line; this does not.
	struct Details {
		/// The requester in full, never truncated.
		let name: String
		/// What it asks for, e.g. "wants to make changes".
		let action: String
		/// Labelled facts, e.g. ("Location", "~/Applications/Foo.app").
		let rows: [(label: String, value: String)]
	}

	init(store: FaceEnrollmentStore, lockout: LockoutManager) {
		self.store = store
		self.lockout = lockout
	}

	var isBusy: Bool { busy }

	/// Whether a check could run now, without starting one.
	var isReady: Bool {
		!busy && store.isEnrolled && !store.isCorrupted && UnlockGuard.embedderBlocker() == nil
			&& store.pinnedCameraID?.isEmpty == false && lockout.mayAttempt()
			&& !Preferences.shared.isPaused && SpoofDetector.isAvailable
			&& AutofillConsoleSession.current() != nil
	}

	/// Runs the check.
	///
	/// - Parameters:
	///   - subject: what is being approved, as the user should read it, e.g.
	///     "Installer wants to make changes". Shown in the panel with the nod prompt.
	///   - details: shown in full in a panel under the notch while the check runs,
	///     with a Don't Allow button. Dismissing it ends the check as cancelled.
	///   - isStillWanted: polled about twice a second; return false when the request
	///     went away (prompt closed, process exited) and the check stops as cancelled.
	///   - onApproved: runs once, while the panel still shows the check, after the
	///     face and nod passed. Return false if acting on it failed; the panel then
	///     closes without a tick.
	func run(subject: String, details: Details? = nil, isStillWanted: @escaping @MainActor () -> Bool,
		onApproved: @MainActor () async -> Bool) async -> Outcome {
		guard isReady, let pinnedCamera = store.pinnedCameraID else { return .unavailable }
		let detector = AntiSpoofGate(spoof: SpoofDetector.shared)
		guard detector.isActive else { return .unavailable }
		let session = AutofillSessionLease()
		guard session.isValid else { return .unavailable }
		busy = true
		defer { busy = false; session.invalidate() }

		let faceIDs = store.faces.filter(\.isEnabled).map(\.id)
		let camera = CameraController()
		let panel = self.panel ?? NotchCapsuleController(usesLockScreenSpace: false)
		self.panel = panel
		var finished = false
		var dismissed = false
		if let details {
			let sheet = detailsPanel ?? ApprovalDetailsPanel()
			detailsPanel = sheet
			sheet.show(details, onDismiss: { dismissed = true })
		}
		let sheet = detailsPanel
		session.onInvalidation = { camera.stop(); panel.hide(); sheet?.hide() }
		defer { session.onInvalidation = nil; camera.stop(); sheet?.hide(); if !finished { panel.hide() } }

		var lastWantedCheck = ContinuousClock.now
		var wanted = true
		func current() -> Bool {
			guard !dismissed, !Task.isCancelled, session.isValid, !store.isCorrupted, !Preferences.shared.isPaused,
				store.faces.filter(\.isEnabled).map(\.id) == faceIDs, store.pinnedCameraID == pinnedCamera,
				!lockout.isLockedOut else { return false }
			// Checked twice a second, not per frame: a slow check here starves the camera.
			if lastWantedCheck.duration(to: .now) > .milliseconds(500) {
				lastWantedCheck = .now
				wanted = isStillWanted()
			}
			return wanted
		}
		guard current() else { return .cancelled }
		panel.show(phase: .scanning)
		Self.logger.notice("Face approval started.")
		await camera.start(pinnedDeviceID: pinnedCamera)
		guard current(), camera.state == .running, camera.boundDeviceID == pinnedCamera else {
			Self.logger.notice("Face approval stopped before scanning: camera=\(String(describing: camera.state), privacy: .public)")
			return .cancelled
		}

		let evaluator = UnlockFrameEvaluator(embedder: store.embedder, faces: store.faces.filter(\.isEnabled), antiSpoof: detector)
		// Always a nod: it reads as "yes", and it is the one movement nobody makes by
		// accident while reading something else on screen.
		let challenge = LivenessChallenge(action: .nod, allowsLook: false)
		// Exactly one movement, whatever the lock-screen setting: the nod is consent.
		var gate = UnlockChallengeGate(requiredActions: 1)
		var frames = RecognitionFrameGate()
		var hold = RecognitionMatchHold()
		var lastContinuity: UInt64?
		let deadline = ContinuousClock.now.advanced(by: .seconds(30))
		var returning = false
		let consentPrompt = "Nod to approve: \(subject)"
		func restart() {
			hold.reset(); challenge.reset(); gate.reset()
			if returning || gate.isPresented { panel.update(phase: .scanning) }
			returning = false
		}
		while ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(40))
			guard current(), camera.state == .running, camera.boundDeviceID == pinnedCamera else {
				Self.logger.notice("Face approval cancelled: the request went away or Gaze's state changed.")
				return .cancelled
			}
			switch frames.observe(id: camera.frameID, capturedAt: camera.lastFrameCapturedAt, now: .now) {
			case .stalled:
				Self.logger.notice("Face approval stopped: the camera stopped sending frames.")
				return .cancelled
			case .waiting: continue
			case .fresh(let continuous): if !continuous { restart() }
			}
			guard !gate.expired(at: .now) else {
				Self.logger.notice("Face approval failed: no nod in time.")
				lockout.recordFailure()
				return .failed
			}
			guard let sample = camera.sample, FrameQuality.rejection(sample) == nil,
				let capturedAt = camera.lastFrameCapturedAt else { restart(); continue }
			let frameID = camera.frameID
			let continuity = camera.evidenceContinuity.revision
			if lastContinuity != continuity { restart() }
			lastContinuity = continuity
			let result = await evaluator.evaluate(sample)
			guard current(), camera.evidenceContinuity.permits(continuity, at: .now),
				capturedAt <= .now, capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge else { restart(); continue }
			// A frame the photo classifier doubts is skipped, not held against the hold.
			if case .suspect = result.spoofDecision { continue }
			guard result.permitsMatchHold(requiresAntiSpoof: true), let face = result.face else { restart(); continue }
			if hold.faceID != face.id { challenge.reset(); gate.reset() }
			let held = hold.consume(faceID: face.id, now: capturedAt, required: .seconds(2))
			if !gate.isPresented && !gate.isVerified { challenge.prepareBaseline(sample) }
			guard held || gate.isPresented else { continue }
			if !gate.isVerified {
				if !gate.isPresented {
					guard challenge.isBaselineReady else { continue }
					gate.present(at: .now, frameID: frameID)
					let hint = challenge.guidanceHint
					panel.update(phase: .challenge(prompt: consentPrompt,
						symbol: challenge.guidanceSymbol, hintX: hint.x, hintY: hint.y, pulses: hint.pulses))
					continue
				}
				guard gate.admits(frameID: frameID, capturedAt: capturedAt, now: .now) else { continue }
				let wasReturning = challenge.isReturningToRest
				let consumption = challenge.consume(sample)
				if consumption.poseSourceInvalidated { restart(); continue }
				if challenge.isReturningToRest && !wasReturning {
					returning = true
					let hint = challenge.guidanceHint
					panel.update(phase: .challenge(prompt: challenge.guidancePrompt,
						symbol: challenge.guidanceSymbol, hintX: hint.x, hintY: hint.y, pulses: hint.pulses,
						isReturningToRest: true))
				}
				guard challenge.isComplete else { continue }
				gate.completeAction()
				if !gate.isVerified { challenge.reset(); continue }
			}
			guard held, gate.isVerified, current(),
				camera.evidenceContinuity.permits(continuity, at: .now),
				capturedAt.duration(to: .now) <= CameraFrameLease.maximumAge else {
				Self.logger.notice("Face approval cancelled: the last frame went stale.")
				return .cancelled
			}
			camera.stop()
			sheet?.hide()
			guard await onApproved() else { return .cancelled }
			lockout.recordSuccess()
			finished = true
			panel.update(phase: .success)
			panel.hide(after: 0.9)
			Self.logger.notice("Face approval approved.")
			return .approved
		}
		Self.logger.notice("Face approval failed: timed out after 30 seconds.")
		lockout.recordFailure()
		return .failed
	}
}

/// The full consent details under the notch: who is asking, what for, where the
/// app lives and who signed it. Non-activating, so the prompt underneath keeps
/// its focus.
@MainActor
private final class ApprovalDetailsPanel {
	private var window: NSPanel?

	func show(_ details: FaceApprovalCheck.Details, onDismiss: @escaping @MainActor () -> Void) {
		let content = ApprovalDetailsView(details: details, onDismiss: { [weak self] in
			onDismiss()
			self?.hide()
		})
		let host = NSHostingView(rootView: content)
		let size = host.fittingSize
		let panel = window ?? NSPanel(contentRect: NSRect(origin: .zero, size: size),
			styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = true
		panel.level = .statusBar
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = true
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
		panel.contentView = host
		if let screen = NSScreen.main {
			let frame = screen.frame
			// Below the notch panel's open height, centred like it.
			let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - 110 - size.height)
			panel.setFrame(NSRect(origin: origin, size: size), display: true)
		}
		window = panel
		panel.orderFrontRegardless()
	}

	func hide() {
		window?.orderOut(nil)
	}
}

private struct ApprovalDetailsView: View {
	let details: FaceApprovalCheck.Details
	let onDismiss: @MainActor () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(details.name)
					.font(.system(size: 13, weight: .semibold))
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)
				Text(details.action)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			ForEach(Array(details.rows.enumerated()), id: \.offset) { _, row in
				VStack(alignment: .leading, spacing: 1) {
					Text(row.label)
						.font(.system(size: 10, weight: .medium))
						.foregroundStyle(.secondary)
					Text(row.value)
						.font(.system(size: 11, weight: .medium))
						.lineLimit(2)
						.truncationMode(.middle)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			HStack {
				Text("Nod to approve")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.secondary)
				Spacer(minLength: 12)
				Button("Don't Allow", action: onDismiss)
					.buttonStyle(.borderless)
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.primary)
					.padding(.horizontal, 12)
					.padding(.vertical, 5)
					.background(Capsule().fill(Color.primary.opacity(0.1)))
			}
		}
		.foregroundStyle(.primary)
		.padding(16)
		.frame(width: 300, alignment: .leading)
		.gazeGlassPanel(cornerRadius: 22, castsShadow: false)
	}
}
