enum SetupStep: Int, CaseIterable {
	case welcome, how, meetGaze, capture, password, permission, done
}

enum SetupPurpose: Equatable {
	case onboarding, addFace
}

struct SetupPlan {
	let steps: [SetupStep]
	let purpose: SetupPurpose

	init(hasPassword: Bool, hasPermission: Bool, including forced: SetupStep? = nil, purpose: SetupPurpose = .onboarding, hasEnrollment: Bool = false, usesWelcomeTour: Bool = false) {
		self.purpose = purpose
		guard purpose == .onboarding else {
			steps = [.capture]
			return
		}
		// The welcome tour already says what Gaze does and where the data stays, so the
		// old explanation screen is redundant — unless diagnostics asked for it outright.
		var steps: [SetupStep] = []
		if !usesWelcomeTour || forced == .how { steps.append(.how) }
		if !usesWelcomeTour || forced == .meetGaze { steps.append(.meetGaze) }
		if !hasEnrollment || forced == .capture { steps.append(.capture) }
		if !hasPassword || forced == .password { steps.append(.password) }
		if !hasPermission || forced == .permission { steps.append(.permission) }
		self.steps = steps
	}

	func next(after step: SetupStep) -> SetupStep? {
		([.welcome] + steps + [.done]).first { $0.rawValue > step.rawValue }
	}

	func previous(before step: SetupStep) -> SetupStep? {
		guard purpose == .onboarding else { return nil }
		return switch step {
		case .how: .welcome
		case .meetGaze: steps.contains(.how) ? .how : .welcome
		case .capture: steps.contains(.meetGaze) ? .meetGaze : (steps.contains(.how) ? .how : .welcome)
		case .password: steps.contains(.capture) ? .capture : (steps.contains(.meetGaze) ? .meetGaze : (steps.contains(.how) ? .how : .welcome))
		case .permission: steps.contains(.password) ? .password : (steps.contains(.capture) ? .capture : (steps.contains(.meetGaze) ? .meetGaze : (steps.contains(.how) ? .how : .welcome)))
		default: nil
		}
	}
}
