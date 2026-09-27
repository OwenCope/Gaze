import Foundation
import Observation

@MainActor
enum SetupRequest {
	@Observable final class Presentation {
		var revision = 0
		var purpose = SetupPurpose.onboarding
	}
	static let presentation = Presentation()
	private static var hasDeliberateRequest = false
	private static var pendingStep: SetupStep?

	/// Call immediately before `openWindow(id: "enrollment")`.
	static func begin() {
		hasDeliberateRequest = true
		pendingStep = .capture
		presentation.purpose = .addFace
		presentation.revision += 1
	}

	static func beginOnboarding() {
		hasDeliberateRequest = true
		pendingStep = .welcome
		presentation.purpose = .onboarding
		presentation.revision += 1
	}

	/// Call immediately before `openWindow(id: "enrollment")` to open on one screen.
	static func begin(at step: SetupStep) {
		hasDeliberateRequest = true
		pendingStep = step
		presentation.purpose = step == .capture ? .addFace : .onboarding
		presentation.revision += 1
	}

	/// The requested screen for this opening.
	///
	/// Read, not cleared: the setup window resets both when the request arrives and when it
	/// appears, and clearing on the first read sent the second reset back to the tour. Every
	/// way into setup sets a new request, so a stale one is never reused.
	static func consumePendingStep() -> SetupStep? {
		pendingStep
	}

	static var isDeliberateOpen: Bool { hasDeliberateRequest }
}
