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

	/// The requested screen, once. Cleared on read so it applies to this opening only.
	static func consumePendingStep() -> SetupStep? {
		defer { pendingStep = nil }
		return pendingStep
	}

	static var isDeliberateOpen: Bool { hasDeliberateRequest }
}
