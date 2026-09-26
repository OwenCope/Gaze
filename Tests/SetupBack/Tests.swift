// Setup Back-navigation regression: Back must never repeat a saved capture.
//
// Compiled together with the real Sources/Setup/SetupPlan.swift and nothing
// else from the app — no views, no camera, no keychain, no credentials.

import Foundation

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
	if !condition {
		failures += 1
		print("FAIL: \(message)")
	}
}

/// Follow `previous(before:)` from `step` until it terminates.
private func backChain(_ plan: SetupPlan, from step: SetupStep) -> [SetupStep] {
	var chain: [SetupStep] = []
	var current: SetupStep? = step
	var guardCount = 0
	while let step = current, guardCount < 16 {
		guardCount += 1
		guard let prev = plan.previous(before: step) else { break }
		chain.append(prev)
		current = prev
	}
	return chain
}

/// Follow `next(after:)` from `.welcome` until it terminates.
private func forwardChain(_ plan: SetupPlan) -> [SetupStep] {
	var traversed: [SetupStep] = []
	var current = SetupStep.welcome
	var guardCount = 0
	while let next = plan.next(after: current), guardCount < 16 {
		guardCount += 1
		check(next.rawValue > current.rawValue, "forward order increases (\(current) -> \(next))")
		traversed.append(next)
		current = next
	}
	return traversed
}

private func describe(hasPassword: Bool, hasPermission: Bool, hasEnrollment: Bool, tour: Bool, forced: SetupStep?) -> String {
	"password:\(hasPassword) permission:\(hasPermission) enrolled:\(hasEnrollment) tour:\(tour) forced:\(forced.map { "\($0)" } ?? "nil")"
}

@main
struct SetupBackRegression {
	static func main() {
		let forcedOptions: [SetupStep?] = [nil] + SetupStep.allCases.map { Optional($0) }
		for hasPassword in [false, true] {
			for hasPermission in [false, true] {
				for hasEnrollment in [false, true] {
					for tour in [false, true] {
						for forced in forcedOptions {
							let plan = SetupPlan(
								hasPassword: hasPassword,
								hasPermission: hasPermission,
								including: forced,
								hasEnrollment: hasEnrollment,
								usesWelcomeTour: tour)
							let context = describe(
								hasPassword: hasPassword,
								hasPermission: hasPermission,
								hasEnrollment: hasEnrollment,
								tour: tour,
								forced: forced)

							// Forward stage order/inclusion is unchanged.
							let expectHow = !tour || forced == .how
							let expectMeetGaze = !tour || forced == .meetGaze
							let expectCapture = !hasEnrollment || forced == .capture
							let expectPassword = !hasPassword || forced == .password
							let expectPermission = !hasPermission || forced == .permission
							check(plan.steps.contains(.how) == expectHow, "how inclusion [\(context)]")
							check(plan.steps.contains(.meetGaze) == expectMeetGaze, "meetGaze inclusion [\(context)]")
							check(plan.steps.contains(.capture) == expectCapture, "capture inclusion [\(context)]")
							check(plan.steps.contains(.password) == expectPassword, "password inclusion [\(context)]")
							check(plan.steps.contains(.permission) == expectPermission, "permission inclusion [\(context)]")
							check(forwardChain(plan) == plan.steps + [.done], "forward traversal [\(context)]")

							// Back from password or permission returns to the step shown before it.
							// The plan still names capture; SetupFlow skips over a finished capture
							// (backDestination) so a saved face is never re-enrolled.
							let intro: SetupStep = plan.steps.contains(.meetGaze) ? .meetGaze : (plan.steps.contains(.how) ? .how : .welcome)
							let beforePassword: SetupStep = plan.steps.contains(.capture) ? .capture : intro
							if plan.steps.contains(.password) {
								check(plan.previous(before: .password) == beforePassword, "password backs to the previous shown step [\(context)]")
							}
							if plan.steps.contains(.permission) {
								let expected = plan.steps.contains(.password) ? SetupStep.password : beforePassword
								check(plan.previous(before: .permission) == expected, "permission backs to the previous shown step [\(context)]")
								check(backChain(plan, from: .permission).contains(.welcome), "Back chain from permission reaches welcome [\(context)]")
							}
							if plan.steps.contains(.capture) {
								check(plan.previous(before: .capture) != nil, "capture keeps its Back path [\(context)]")
							}

							// addFace has no Back anywhere, regardless of flags.
							let addFace = SetupPlan(
								hasPassword: hasPassword,
								hasPermission: hasPermission,
								including: forced,
								purpose: .addFace,
								hasEnrollment: hasEnrollment,
								usesWelcomeTour: tour)
							check(addFace.steps == [.capture], "addFace is capture-only [\(context)]")
							check(addFace.next(after: .capture) == .done, "addFace forward [\(context)]")
							for step in SetupStep.allCases {
								check(addFace.previous(before: step) == nil, "addFace has no Back from \(step) [\(context)]")
							}
						}
					}
				}
			}
		}

		// Named spot checks for the defect: SetupFlow keeps its plan fixed for the
		// run, so returning to welcome after a saved capture could lead through
		// capture again. These pin the exact routing, not just the chain property.
		let legacy = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: false, usesWelcomeTour: false)
		check(legacy.steps == [.how, .meetGaze, .capture, .password, .permission], "legacy steps")
		check(legacy.previous(before: .password) == .capture, "legacy password backs to capture (skipped once saved)")
		check(legacy.previous(before: .permission) == .password, "legacy permission backs to password")
		check(legacy.previous(before: .capture) == .meetGaze, "legacy capture backs to meetGaze")

		let tourFresh = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: false, usesWelcomeTour: true)
		check(tourFresh.steps == [.capture, .password, .permission], "tour fresh steps")
		check(tourFresh.previous(before: .password) == .capture, "tour password backs to capture (skipped once saved)")
		check(tourFresh.previous(before: .permission) == .password, "tour permission backs to password")
		check(tourFresh.previous(before: .capture) == .welcome, "tour capture backs to welcome")

		let tourEnrolled = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: true, usesWelcomeTour: true)
		check(tourEnrolled.steps == [.password, .permission], "tour enrolled skips capture")
		check(tourEnrolled.previous(before: .password) == .welcome, "tour enrolled password backs to welcome")
		check(tourEnrolled.previous(before: .permission) == .password, "tour enrolled permission backs to password")

		let enrolledLegacy = SetupPlan(hasPassword: false, hasPermission: true, hasEnrollment: true, usesWelcomeTour: false)
		check(!enrolledLegacy.steps.contains(.capture), "enrolled legacy has no capture")
		check(enrolledLegacy.previous(before: .password) == .meetGaze, "enrolled legacy password backs to meetGaze")

		let passwordOnly = SetupPlan(hasPassword: false, hasPermission: true, hasEnrollment: false, usesWelcomeTour: true)
		check(passwordOnly.steps == [.capture, .password], "password-only tour steps")
		check(passwordOnly.previous(before: .password) == .capture, "password-only password backs to capture (skipped once saved)")

		let permissionOnly = SetupPlan(hasPassword: true, hasPermission: false, hasEnrollment: false, usesWelcomeTour: true)
		check(permissionOnly.steps == [.capture, .permission], "permission-only tour steps")
		check(permissionOnly.previous(before: .permission) == .capture, "permission-only permission backs to capture (skipped once saved)")

		if failures > 0 {
			print("FAIL: \(failures) check(s) failed")
			exit(1)
		}
		print("PASS: Back never repeats a saved capture (\(2 * 2 * 2 * 2 * 8) plan combinations plus addFace, forward order and spot checks)")
	}
}
