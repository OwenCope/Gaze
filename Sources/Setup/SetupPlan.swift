enum SetupStep: Int, CaseIterable {
	case welcome, how, meetGaze, capture, password, permission, done
}

enum SetupPurpose: Equatable {
	case onboarding, addFace
}

struct SetupPlan {
	let steps: [SetupStep]
	let purpose: SetupPurpose

	init(hasPassword: Bool, hasPermission: Bool, including forced: SetupStep? = nil, purpose: SetupPurpose = .onboarding, hasEnrollment: Bool = false) {
		self.purpose = purpose
		guard purpose == .onboarding else {
			steps = [.capture]
			return
		}
		var steps: [SetupStep] = [.how, .meetGaze]
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
		case .meetGaze: .how
		case .capture: .meetGaze
		case .permission: steps.contains(.password) ? .password : nil
		default: nil
		}
	}
}
