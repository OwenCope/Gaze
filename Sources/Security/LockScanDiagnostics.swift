import Foundation
import Observation

@MainActor
@Observable
final class LockScanDiagnostics {
	static let shared = LockScanDiagnostics()

	enum Outcome: CaseIterable {
		case starting, scanning, movement, manualInput, cameraUnavailable, firstFrameTimeout, cameraStalled
		case verificationUnavailable, notRecognized, spoofRejected, ended, scanOnlyPassed
		case submissionStopped, submissionPending, submissionUnconfirmed, unlocked, cancelled

		var isScanning: Bool { self == .starting || self == .scanning || self == .movement }

		var message: String {
			switch self {
			case .starting: "Waiting for the camera's first fresh frame."
			case .scanning: "Looking for your enrolled face."
			case .movement: "Follow the blob, then return to your starting position."
			case .manualInput: "Gaze stopped when keyboard or mouse input was detected. Use your password or Touch ID for this lock."
			case .cameraUnavailable: "The enrolled camera could not start. Unlock manually, then check Test Recognition."
			case .firstFrameTimeout: "The camera did not deliver a fresh frame in time. No password was sent. Unlock manually, then check Test Recognition."
			case .cameraStalled: "The camera stopped delivering fresh frames. No password was sent. Use your password or Touch ID."
			case .verificationUnavailable: "A required verification check was unavailable. No password was sent. Use your password or Touch ID."
			case .notRecognized: "Face verification or a movement did not complete. No password was sent. Face the camera and return to rest between movements."
			case .spoofRejected: "The anti-spoof check rejected the attempt. No password was sent. Use your password or Touch ID."
			case .ended: "The scan ended without complete verification. No password was sent. Try Test Recognition to check framing and movement."
			case .scanOnlyPassed: "Recognition and the selected movement checks passed in scan-only mode. That mode does not enter a password or unlock your Mac."
			case .submissionStopped: "Password delivery stopped before Gaze could confirm an unlock. It will not retry during this lock. Use your password or Touch ID."
			case .submissionPending: "Password input was sent; waiting for macOS to confirm that the screen unlocked."
			case .submissionUnconfirmed: "macOS did not confirm an unlock after password input. Gaze will not retry during this lock. Use your password or Touch ID."
			case .unlocked: "macOS reported that the screen unlocked after Gaze sent password input."
			case .cancelled: "The scan was cancelled or the Mac was unlocked another way."
			}
		}
	}

	private var attemptID: UUID?
	private(set) var outcome: Outcome?
	private(set) var movementFailure: MovementFailure?
	var summary: String {
		let outcomeMessage = outcome?.message ?? "No lock-screen attempt in this app session."
		guard let movementFailure else { return outcomeMessage }
		return outcomeMessage + "\n\n" + movementFailure.message
	}

	struct MovementFailure {
		let action: String
		let returning: Bool
		let comparedIdentity: Bool
		let score: Float
		let threshold: Float
		let poseOffset: Double?
		let poseTarget: Double?
		let returnTolerance: Double?

		var message: String {
			let phase = returning ? "returning to the starting pose" : "making the requested movement"
			let comparison = comparedIdentity
				? String(format: "Face match %.3f was below %.2f.", score, threshold)
				: "The face comparison could not complete."
			var text = "Last movement stopped: \(action), while \(phase). \(comparison)"
			if let poseOffset, let poseTarget, let returnTolerance {
				text += String(format: " Movement from start: %+.2f rad; requested: %+.2f rad; return range: ±%.2f rad.",
					poseOffset, poseTarget, returnTolerance)
			}
			return text
		}
	}

	func begin(_ identifier: UUID) {
		attemptID = identifier
		outcome = .starting
		movementFailure = nil
	}

	func recordMovementFailure(_ failure: MovementFailure, for identifier: UUID) {
		guard attemptID == identifier else { return }
		movementFailure = failure
	}

	func record(_ outcome: Outcome, for identifier: UUID) {
		guard attemptID == identifier else { return }
		self.outcome = outcome
	}

	func finishScanning(for identifier: UUID) {
		guard outcome?.isScanning == true else { return }
		record(.cancelled, for: identifier)
	}

	func cancel(for identifier: UUID) {
		guard outcome?.isScanning == true || outcome == .submissionPending else { return }
		record(.cancelled, for: identifier)
	}
}
