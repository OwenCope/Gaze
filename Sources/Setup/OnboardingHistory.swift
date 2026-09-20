import Foundation

enum OnboardingHistory {
	static let seenKey = "gaze.onboarding.hasBeenPresented"

	static func needsIntroduction(isEnrolled: Bool, defaults: UserDefaults = .standard) -> Bool {
		!isEnrolled && !defaults.bool(forKey: seenKey)
	}

	static func markPresented(defaults: UserDefaults = .standard) {
		defaults.set(true, forKey: seenKey)
	}

	static func presentsSetup(isEnrolled: Bool, arguments: [String], defaults: UserDefaults = .standard) -> Bool {
		guard !arguments.contains("--agent"), !arguments.contains("--settings") else { return false }
		return arguments.contains("--setup") || arguments.contains("--capture-dataset")
			|| arguments.contains(where: { $0.hasPrefix("--setup-step=") })
			|| needsIntroduction(isEnrolled: isEnrolled, defaults: defaults)
	}
}
