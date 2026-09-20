import Foundation

enum UnlockExecutionPolicy: Equatable {
	case normal
	case uiReview
	case scanOnly
	case browserOnly

	static var current: Self { Self(arguments: CommandLine.arguments) }

	init(arguments: [String]) {
		if arguments.contains("--scan-only") {
			self = .scanOnly
		} else if arguments.contains("--ui-review") {
			self = .uiReview
		} else if arguments.contains("--browser-only") {
			self = .browserOnly
		} else {
			self = .normal
		}
	}

	var permitsPasswordSubmission: Bool { self == .normal }
	var permitsAutomaticLocking: Bool { self == .normal }
	var permitsLockObservation: Bool { self == .normal || self == .scanOnly }

	func permitsBrowserApproval(passwordReplayEnabled _: Bool) -> Bool {
		self == .browserOnly || self == .scanOnly || self == .normal
	}

	func permitsScanning(passwordReplayEnabled: Bool, keystrokeSelected: Bool) -> Bool {
		self == .scanOnly || (self == .normal && passwordReplayEnabled && keystrokeSelected)
	}
}
