import AppKit
import AVFoundation
import SwiftUI

@main
struct OnboardingTests {
	@MainActor static func main() throws {
		let app = NSApplication.shared
		app.appearance = NSAppearance(named: .darkAqua)
		if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
			app.applicationIconImage = NSImage(contentsOf: url)
		}
		if CommandLine.arguments.contains("--review") {
			let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 706),
				styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
			window.title = "Gaze Onboarding — Design Review · No camera or credentials"
			window.contentView = NSHostingView(rootView: OnboardingReview())
			window.center()
			window.makeKeyAndOrderFront(nil)
			app.setActivationPolicy(.regular)
			app.activate(ignoringOtherApps: true)
			app.run()
			return
		}
		checkPlan()
		checkWelcomeTour()
		checkPermissions()
		checkFirstUse()
		checkRequests()
		checkExpressions()
		checkLessonPlayback()
		checkCompletion()
		checkShakeInterpolation()
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		if CommandLine.arguments.contains("--offscreen-only") {
			print("SKIP: display-driven frame pacing requires an unlocked desktop")
		} else {
			let cadence = LessonMotionTests.run()
			try JSONSerialization.data(withJSONObject: ["kind": "display_callback_cadence", "lessons": cadence,
				"limitations": ["Render callbacks, not physical display scanout", "Camera and authentication services are test doubles"]],
				options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("motion-cadence.json"))
		}
		let wallpaper = DesktopWallpaper.shared
		let deadline = Date(timeIntervalSinceNow: 2)
		while wallpaper.image == nil && Date() < deadline {
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
		}
		for scheme in [ColorScheme.dark, .light] {
			app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
			for page in ReviewPage.allCases {
				try CompanionCapture.snapshot(
					ReviewPageView(page: page, next: {}, previous: {})
						.frame(width: 880, height: 660)
						.background(SetupBackdrop())
						.environment(\.colorScheme, scheme)
						.environment(\.notchReduceMotion, true)
						.transaction { $0.disablesAnimations = true },
					to: directory.appendingPathComponent("\(page.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
			}
		}
		for lesson in GazeExpressionLesson.allCases {
			for scheme in [ColorScheme.dark, .light] {
				app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
				try CompanionCapture.snapshot(
					GazeExpressionGuide(compact: true, lesson: lesson)
						.padding(24).frame(width: 560, height: 380)
						.background(scheme == .dark ? Color(white: 0.09) : Color(white: 0.94))
						.environment(\.colorScheme, scheme)
						.environment(\.notchReduceMotion, true),
					to: directory.appendingPathComponent("lesson-\(lesson.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
			}
		}
		for scheme in [ColorScheme.dark, .light] {
			app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
			let suffix = scheme == .dark ? "dark" : "light"
			try CompanionCapture.snapshot(
				SetupHowStep(position: .init(index: 0, count: 5), onContinue: {}, onBack: {}, movementCount: 1)
					.frame(width: 880, height: 660).background(SetupBackdrop())
					.environment(\.colorScheme, scheme).environment(\.notchReduceMotion, true),
				to: directory.appendingPathComponent("how-one-\(suffix).png"))
			try CompanionCapture.snapshot(
				SetupMeetGazeStep(position: .init(index: 1, count: 5), onContinue: {}, onBack: {}, movementCount: 1)
					.frame(width: 880, height: 660).background(SetupBackdrop())
					.environment(\.colorScheme, scheme).environment(\.notchReduceMotion, true),
				to: directory.appendingPathComponent("meetGaze-one-\(suffix).png"))
			try CompanionCapture.snapshot(
				GazeExpressionGuide(compact: true, lesson: .scanning, movementCount: 1)
					.padding(24).frame(width: 560, height: 380)
					.background(scheme == .dark ? Color(white: 0.09) : Color(white: 0.94))
					.environment(\.colorScheme, scheme).environment(\.notchReduceMotion, true),
				to: directory.appendingPathComponent("lesson-scanning-one-\(suffix).png"))
		}
		print("PASS: first-use policy, request routing, add-face isolation, expression mappings, companion motion, permission policy and \(ReviewPage.allCases.count * 2 + GazeExpressionLesson.allCases.count * 2 + 6) light/dark offscreen screens")
	}

	static func checkShakeInterpolation() {
		var shake = ShakeEffect(travel: 1)
		for endpoint in [CGFloat(0), 1, 2] {
			shake.animatableData = endpoint
			precondition(abs(shake.effectValue(size: CGSize(width: 100, height: 40)).m31) < 0.001,
				"A completed shake must return to its resting position")
		}
		shake.animatableData = 0.25
		precondition(abs(shake.animatableData - 0.25) < 0.001, "Interpolation must retain fractional progress")
		let outward = shake.effectValue(size: CGSize(width: 100, height: 40)).m31
		shake.animatableData = 0.5
		let returning = shake.effectValue(size: CGSize(width: 100, height: 40)).m31
		precondition(outward > 1 && returning < -1, "The error cue must visibly move in both directions")
		shake.isEnabled = false
		precondition(abs(shake.effectValue(size: CGSize(width: 100, height: 40)).m31) < 0.001,
			"Reduce Motion must suppress an in-flight shake immediately")
		print("PASS: shake interpolation retains fractional frames, settles at zero and respects Reduce Motion")
	}

	static func checkPlan() {
		precondition(ReviewPage.camera.advanced(by: 1) == .password)
		precondition(ReviewPage.permission.advanced(by: 1) == .done)
		precondition(ReviewPage.cameraRestricted.advanced(by: 1) == .password)
		precondition(ReviewPage.done.advanced(by: 1) == .done)
		precondition(Set(ReviewPage.walkthrough.map(\.rawValue)).isDisjoint(with: ReviewPage.diagnosticStates.map(\.rawValue)))
		for hasPassword in [false, true] {
			for hasPermission in [false, true] {
				for forced in [nil] + SetupStep.allCases.map(Optional.some) {
					let plan = SetupPlan(hasPassword: hasPassword, hasPermission: hasPermission, including: forced)
					precondition(plan.steps.prefix(3) == [.how, .meetGaze, .capture])
					precondition(plan.steps.contains(.password) == (!hasPassword || forced == .password))
					precondition(plan.steps.contains(.permission) == (!hasPermission || forced == .permission))
					var traversed: [SetupStep] = []
					var current = SetupStep.welcome
					while let next = plan.next(after: current) {
						precondition(next.rawValue > current.rawValue)
						traversed.append(next)
						current = next
					}
					precondition(traversed == plan.steps + [.done])
					precondition(plan.previous(before: .how) == .welcome)
					precondition(plan.previous(before: .meetGaze) == .how)
					precondition(plan.previous(before: .capture) == .meetGaze)
					precondition(plan.previous(before: .password) == nil, "Back must not re-enrol a saved face")
					precondition(plan.previous(before: .permission) == (plan.steps.contains(.password) ? .password : nil))
					let addFace = SetupPlan(hasPassword: hasPassword, hasPermission: hasPermission, including: forced, purpose: .addFace)
					precondition(addFace.steps == [.capture])
					precondition(addFace.next(after: .capture) == .done)
					precondition(addFace.next(after: .done) == nil)
					for step in SetupStep.allCases { precondition(addFace.previous(before: step) == nil) }
				}
			}
		}
		let unenrolled = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: false)
		precondition(unenrolled.steps.prefix(3) == [.how, .meetGaze, .capture],
			"Unenrolled onboarding must still capture a face")
		let enrolled = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: true)
		precondition(enrolled.steps.prefix(2) == [.how, .meetGaze],
			"Enrolled onboarding must still explain the app")
		precondition(!enrolled.steps.contains(.capture),
			"Enrolled onboarding must not save another face")
		let enrolledForced = SetupPlan(hasPassword: false, hasPermission: false, including: .capture, hasEnrollment: true)
		precondition(enrolledForced.steps.contains(.capture),
			"Explicitly forced capture must still capture when enrolled")
		let enrolledAddFace = SetupPlan(hasPassword: false, hasPermission: false, purpose: .addFace, hasEnrollment: true)
		precondition(enrolledAddFace.steps == [.capture],
			"Add-face must always capture, regardless of enrollment")
	}

	static func checkWelcomeTour() {
		// The welcome tour already demonstrates the movements, so onboarding continues
		// directly at the first required setup stage — no separate practice afterward.
		for hasPassword in [false, true] {
			for hasPermission in [false, true] {
				for hasEnrollment in [false, true] {
					let tour = SetupPlan(hasPassword: hasPassword, hasPermission: hasPermission, hasEnrollment: hasEnrollment, usesWelcomeTour: true)
					precondition(!tour.steps.contains(.how) && !tour.steps.contains(.meetGaze),
						"Tour onboarding must not repeat the welcome tour's explanation or practice")
					precondition(tour.steps.contains(.capture) == !hasEnrollment)
					precondition(tour.steps.contains(.password) == !hasPassword)
					precondition(tour.steps.contains(.permission) == !hasPermission)
					precondition(tour.next(after: .welcome) == (tour.steps.first ?? .done),
						"Tour welcome must lead directly to the first required setup stage")
					precondition(tour.previous(before: .capture) == .welcome,
						"Back from capture must return to the tour when no guide was forced")
					var traversed: [SetupStep] = []
					var current = SetupStep.welcome
					while let next = tour.next(after: current) {
						precondition(next.rawValue > current.rawValue)
						traversed.append(next)
						current = next
					}
					precondition(traversed == tour.steps + [.done])
				}
			}
		}
		// A new user goes straight from the tour into capture, password, permission.
		let tour = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: false, usesWelcomeTour: true)
		precondition(tour.steps == [.capture, .password, .permission],
			"Tour onboarding must capture, then ask for password and permission")
		precondition(tour.next(after: .welcome) == .capture,
			"Tour welcome must lead directly into capture, not a separate practice")
		precondition(tour.previous(before: .capture) == .welcome,
			"Back from capture must return to the tour when no guide was forced")
		precondition(tour.previous(before: .password) == nil, "Back must not re-enrol a saved face")
		precondition(tour.previous(before: .permission) == .password)
		// Enrolled users skip capture but still work through password and permission.
		let tourEnrolled = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: true, usesWelcomeTour: true)
		precondition(tourEnrolled.steps == [.password, .permission],
			"Enrolled tour onboarding must skip capture")
		precondition(tourEnrolled.next(after: .welcome) == .password)
		// Fully configured users finish right after the tour.
		let tourConfigured = SetupPlan(hasPassword: true, hasPermission: true, hasEnrollment: true, usesWelcomeTour: true)
		precondition(tourConfigured.steps == [],
			"Fully configured tour onboarding must have no further setup stages")
		precondition(tourConfigured.next(after: .welcome) == .done)
		// An explicitly forced explanation screen is still honoured on the tour path.
		let tourForcedHow = SetupPlan(hasPassword: false, hasPermission: false, including: .how, hasEnrollment: false, usesWelcomeTour: true)
		precondition(tourForcedHow.steps == [.how, .capture, .password, .permission],
			"Forced .how must still open on the tour path without a separate practice")
		precondition(tourForcedHow.next(after: .welcome) == .how)
		precondition(tourForcedHow.previous(before: .how) == .welcome)
		precondition(tourForcedHow.previous(before: .capture) == .how,
			"Back from capture must return to .how when it was forced open")
		// An explicitly forced practice guide is still honoured on the tour path.
		let tourForcedMeetGaze = SetupPlan(hasPassword: false, hasPermission: false, including: .meetGaze, hasEnrollment: false, usesWelcomeTour: true)
		precondition(tourForcedMeetGaze.steps == [.meetGaze, .capture, .password, .permission],
			"Forced .meetGaze must still open on the tour path")
		precondition(tourForcedMeetGaze.next(after: .welcome) == .meetGaze)
		precondition(tourForcedMeetGaze.previous(before: .meetGaze) == .welcome)
		precondition(tourForcedMeetGaze.previous(before: .capture) == .meetGaze,
			"Back from capture must return to .meetGaze when it was forced open")
		// The legacy path without the welcome tour is unchanged: explanation and
		// standalone practice still open before capture.
		let legacy = SetupPlan(hasPassword: false, hasPermission: false, hasEnrollment: false, usesWelcomeTour: false)
		precondition(legacy.steps == [.how, .meetGaze, .capture, .password, .permission])
		precondition(legacy.next(after: .welcome) == .how)
		precondition(legacy.previous(before: .meetGaze) == .how)
		precondition(legacy.previous(before: .capture) == .meetGaze)
		// The tour flag changes nothing for add-face: always one capture, no way back.
		let tourAddFace = SetupPlan(hasPassword: false, hasPermission: false, purpose: .addFace, hasEnrollment: true, usesWelcomeTour: true)
		precondition(tourAddFace.steps == [.capture],
			"Add-face must always capture, regardless of the tour flag")
		precondition(tourAddFace.next(after: .capture) == .done)
		for step in SetupStep.allCases { precondition(tourAddFace.previous(before: step) == nil) }
		print("PASS: welcome tour leads directly into setup, forced guides, Back navigation and add-face isolation")
	}

	static func checkFirstUse() {
		let suite = "com.gazeunlock.OnboardingTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		precondition(OnboardingHistory.needsIntroduction(isEnrolled: false, defaults: defaults))
		precondition(!OnboardingHistory.needsIntroduction(isEnrolled: true, defaults: defaults))
		precondition(OnboardingHistory.presentsSetup(isEnrolled: false, arguments: [], defaults: defaults))
		for arguments in [["--agent"], ["--settings"], ["--agent", "--setup"]] {
			precondition(!OnboardingHistory.presentsSetup(isEnrolled: false, arguments: arguments, defaults: defaults))
		}
		OnboardingHistory.markPresented(defaults: defaults)
		for enrolled in [false, true] {
			precondition(!OnboardingHistory.presentsSetup(isEnrolled: enrolled, arguments: [], defaults: defaults))
			for arguments in [["--setup"], ["--capture-dataset"], ["--setup-step=meetGaze"]] {
				precondition(OnboardingHistory.presentsSetup(isEnrolled: enrolled, arguments: arguments, defaults: defaults))
			}
		}
		precondition(!OnboardingHistory.needsIntroduction(isEnrolled: false, defaults: UserDefaults(suiteName: suite)!))
	}

	@MainActor static func checkRequests() {
		let revision = SetupRequest.presentation.revision
		SetupRequest.begin()
		precondition(SetupRequest.presentation.purpose == .addFace)
		precondition(SetupRequest.consumePendingStep() == .capture)
		precondition(SetupRequest.consumePendingStep() == nil)
		SetupRequest.beginOnboarding()
		precondition(SetupRequest.presentation.purpose == .onboarding)
		precondition(SetupRequest.consumePendingStep() == .welcome)
		precondition(SetupRequest.presentation.revision == revision + 2)
		for step in SetupStep.allCases {
			SetupRequest.begin(at: step)
			precondition(SetupRequest.consumePendingStep() == step)
			precondition(SetupRequest.presentation.purpose == (step == .capture ? .addFace : .onboarding))
		}
	}

	static func checkExpressions() {
		precondition(GazeExpressionLesson.scanning.explanation(movementCount: 1).contains("one short movement."))
		precondition(GazeExpressionLesson.scanning.explanation(movementCount: 2).contains("two short movements."))
		let motions: [GazeFaceMotion] = [.resting, .scanning, .turnLeft, .turnRight, .nod, .blink, .openMouth, .accepted, .rejected]
		precondition(GazeExpressionLesson.allCases.map(\.motion) == motions)
		precondition(GazeExpressionLesson.waiting.previous == nil)
		precondition(GazeExpressionLesson.retry.next == nil)
		for lesson in GazeExpressionLesson.allCases {
			if let next = lesson.next { precondition(next.previous == lesson) }
		}
		for time in stride(from: 0.0, through: 40.0, by: 1.0 / 120) {
			let sample = GazePeekSample.at(time)
			precondition(sample.reveal.isFinite && (0...1).contains(sample.reveal))
			precondition(sample.pose.face.eyesOpen == 1, "Idle peeking must not look like a blink challenge")
			precondition(sample.pose.face.turn.isFinite && sample.pose.face.gaze.isFinite)
			let next = GazePeekSample.at(time + 1.0 / 120)
			precondition(abs(sample.reveal - next.reveal) < 0.02)
			if time > 1.4 { precondition(sample.reveal == 1, "Companion stays present after arriving") }
		}
		precondition(GazePeekSample.at(2.8).reveal == 1)
		precondition(GazePeekSample.at(12.8).reveal == 1)
		precondition(GazeCuriosityMotion.pose(at: 1.5).face.gaze > 0)
		precondition(GazeCuriosityMotion.pose(at: 1.5).face.turn == 0, "Eyes notice before the body turns")
		precondition(GazeCuriosityMotion.pose(at: 1.5).drift == 0, "Do not slide before noticing")
		precondition(GazeCuriosityMotion.pose(at: 3.2).drift > 0, "Body follows the glance")
		for time in [0.0, 7.0, 8.0, 12.9, GazeCuriosityMotion.duration, GazeCuriosityMotion.duration + 0.5] {
			precondition(GazeCuriosityMotion.pose(at: time) == GazeCompanionPose(), "Curiosity includes real resting holds")
		}
		for frame in 0..<2160 {
			let pose = GazeCuriosityMotion.pose(at: Double(frame) / 120)
			let next = GazeCuriosityMotion.pose(at: Double(frame + 1) / 120)
			precondition(abs(pose.drift - next.drift) < 0.004)
			precondition(abs(pose.face.gaze - next.face.gaze) < 0.01)
			precondition(abs(pose.face.turn - next.face.turn) < 0.01)
			precondition(pose.face.eyesOpen == 1 && pose.face.expression == 0 && pose.face.nod == 0)
		}
	}

	static func checkLessonPlayback() {
		for motion in GazeExpressionLesson.allCases.map(\.motion) {
			var playback = GazeLessonPlayback(motion: motion, at: 0)
			let before = playback.pose(at: 0.75)
			playback.setPaused(true, at: 0.75)
			precondition(playback.pose(at: 10) == before, "Pause must hold the pose")
			playback.setPaused(false, at: 10)
			precondition(playback.pose(at: 10) == before, "Resume must not jump")
			let current = playback.pose(at: 10.1)
			playback.select(.nod, at: 10.1)
			precondition(playback.pose(at: 10.1) == current, "Selection blends from the current pose")
		}
		for motion in [GazeFaceMotion.accepted, .rejected] {
			let playback = GazeLessonPlayback(motion: motion, at: 0)
			let period = GazeCompanionPresentation.standard.duration(for: motion)! + 1
			let before = playback.pose(at: period - 0.0001)
			let after = playback.pose(at: period + 0.0001)
			precondition(abs(before.face.expression - after.face.expression) < 0.01)
			precondition(abs(before.face.nod - after.face.nod) < 0.01)
			precondition(abs(before.face.turn - after.face.turn) < 0.01)
		}
		print("PASS: lesson pause/resume, interruptible selection and continuous result loops")
	}

	static func checkCompletion() {
		for failed in [false, true] {
			for needsPassword in [false, true] {
				for needsAccessibility in [false, true] {
					for addingFace in [false, true] {
						let unfinished = SetupUnfinished(needsPassword: needsPassword, needsAccessibility: needsAccessibility)
						let title = SetupDoneStep.title(failed: failed, unfinished: unfinished, isAddingFace: addingFace)
						precondition((title == "Enjoy a little less typing.") == (!failed && !addingFace && unfinished.isComplete))
						precondition((title == "Face added") == (!failed && addingFace))
						// The Settings route is only for partial first-run setups: never on
						// failure, never for add-face, never when complete, never without an opener.
						let offersSettings = SetupDoneStep.showsFinishInSettings(failed: failed, unfinished: unfinished, isAddingFace: addingFace, canOpenSettings: true)
						precondition(offersSettings == (!failed && !addingFace && !unfinished.isComplete))
						precondition(!SetupDoneStep.showsFinishInSettings(failed: failed, unfinished: unfinished, isAddingFace: addingFace, canOpenSettings: false))
					}
				}
			}
		}
	}

	static func checkPermissions() {
		for accessibility in [false, true] {
			for keyboardEvents in [false, true] {
				precondition(SetupPermissionStatus(accessibility: accessibility, keyboardEvents: keyboardEvents).isReady
					== (accessibility && keyboardEvents))
				let unfinished = SetupUnfinished(needsPassword: !accessibility, needsAccessibility: !keyboardEvents)
				precondition(unfinished.isComplete == (accessibility && keyboardEvents))
			}
		}
		precondition(SetupCameraAccessContent.actionTitle(for: .notDetermined) == "Allow Camera Access")
		precondition(SetupCameraAccessContent.actionTitle(for: .denied) == "Open Camera Settings")
		precondition(SetupCameraAccessContent.actionTitle(for: .restricted) == nil)
		precondition(SetupCameraAccessContent.actionTitle(for: .authorized) == nil)
	}
}

enum ReviewPage: String, CaseIterable, Identifiable {
	case welcome, how, meetGaze, camera, cameraDenied, cameraRestricted, addFace, faceAdded, password, permission, permissionPending, permissionGranted, done, unfinished, failed
	static let walkthrough: [Self] = [.welcome, .how, .meetGaze, .camera, .password, .permission, .done]
	static let diagnosticStates: [Self] = [.cameraDenied, .cameraRestricted, .addFace, .faceAdded, .permissionPending, .permissionGranted, .unfinished, .failed]
	var walkthroughPage: Self {
		switch self {
		case .cameraDenied, .cameraRestricted, .addFace: .camera
		case .permissionPending, .permissionGranted: .permission
		case .unfinished, .failed, .faceAdded: .done
		default: self
		}
	}
	func advanced(by offset: Int) -> Self {
		let pages = Self.walkthrough
		let index = pages.firstIndex(of: walkthroughPage) ?? 0
		return pages[min(max(index + offset, 0), pages.count - 1)]
	}
	var id: String { rawValue }
	var title: String {
		switch self {
		case .welcome: "Welcome"
		case .how: "How it works"
		case .meetGaze: "Meet Gaze"
		case .addFace: "Add a face"
		case .faceAdded: "Face added"
		case .camera: "Camera request"
		case .cameraDenied: "Camera denied"
		case .cameraRestricted: "Camera restricted"
		case .password: "Password preview"
		case .permission: "Accessibility request"
		case .permissionPending: "Accessibility pending"
		case .permissionGranted: "Accessibility granted"
		case .done: "Complete"
		case .unfinished: "Finish later"
		case .failed: "Couldn’t finish"
		}
	}
}

struct ReviewPageView: View {
	let page: ReviewPage
	var next: () -> Void
	var previous: () -> Void
	var body: some View {
		switch page {
		case .welcome:
			GazeWelcomeTour(onContinue: next, onClose: next)
		case .how:
			SetupHowStep(position: .init(index: 0, count: 5), onContinue: next, onBack: previous)
		case .meetGaze:
			SetupMeetGazeStep(position: .init(index: 1, count: 5), onContinue: next, onBack: previous)
		case .addFace:
			SetupCameraAccessContent(authorization: .notDetermined, onRequest: next)
				.overlay { GazePeekingCompanion() }
		case .faceAdded:
			SetupDoneStep(failure: nil, unfinished: .init(), isAddingFace: true, onDone: next, onRetry: previous)
		case .camera, .cameraDenied, .cameraRestricted:
			SetupCameraAccessContent(position: .init(index: 2, count: 5),
				authorization: page == .camera ? .notDetermined : page == .cameraDenied ? .denied : .restricted,
				onRequest: next, onBack: previous)
		case .password:
			PasswordReviewPage(onContinue: next, onSkip: next, onBack: previous)
		case .permission, .permissionPending, .permissionGranted:
			SetupPermissionContent(position: .init(index: 4, count: 5),
				status: .init(accessibility: page != .permission, keyboardEvents: page == .permissionGranted),
				onContinue: next, onSkip: next, onBack: previous, onOpenSettings: next, onRevealApp: {})
		case .done, .unfinished, .failed:
			SetupDoneStep(failure: page == .failed ? "Gaze couldn’t save your face. Nothing was changed. Please try again." : nil,
				unfinished: .init(needsPassword: page == .unfinished, needsAccessibility: page == .unfinished),
				onDone: next, onRetry: previous,
				onOpenSettings: page == .unfinished ? {} : nil,
				onTestRecognition: {})
		}
	}
}

struct PasswordReviewPage: View {
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: () -> Void

	var body: some View {
		SetupScaffold(
			position: .init(index: 3, count: 5),
			title: "Your login password",
			message: "This is a design preview. Don’t enter your real password.\nIn Gaze, macOS checks your password before it is saved.",
			figureHeight: 132,
			onBack: onBack
		) {
			SetupGlyph(symbol: "key.fill")
		} detail: {
			VStack(spacing: 10) {
				Text("Password entry is off in this preview")
					.font(.system(size: 14))
					.foregroundStyle(Theme.setupSecondary)
					.frame(width: 360, height: 44)
					.glassEffect(.regular, in: .capsule)
				Text("Nothing will be checked or saved.")
					.font(.caption).foregroundStyle(Theme.setupSecondary)
			}
			.padding(.top, 22)
		} actions: {
			SetupButton(title: "Continue Preview", action: onContinue)
			SetupSecondaryButton(title: "Set Up Later", action: onSkip)
		}
	}
}

struct OnboardingReview: View {
	@State private var page = ReviewPage.welcome
	@State private var reducedMotion = false
	@State private var lightAppearance = false
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text("Design review").font(.caption).foregroundStyle(.secondary)
				Spacer()
				Picker("Step", selection: Binding(get: { page.walkthroughPage }, set: { page = $0 })) {
					ForEach(ReviewPage.walkthrough) { page in Text(page.title).tag(page) }
				}.frame(width: 220)
				Menu("Test States") {
					ForEach(ReviewPage.diagnosticStates) { state in
						Button(state.title) { page = state }
					}
				}.frame(width: 100)
				Button("Next") { navigate(1) }
					.buttonStyle(.glass)
					.disabled(page.walkthroughPage == .done)
				Toggle("Reduce Motion", isOn: $reducedMotion).toggleStyle(.checkbox)
				Toggle("Light", isOn: $lightAppearance).toggleStyle(.checkbox)
			}
			.padding(12)
			ReviewPageView(page: page, next: { navigate(1) }, previous: { navigate(-1) })
				.id(page)
				.transition(reducedMotion ? .identity : .opacity.combined(with: .offset(x: 12)))
				.frame(width: 880, height: 660)
				.environment(\.notchReduceMotion, reducedMotion)
				.transaction { if reducedMotion { $0.disablesAnimations = true } }
		}
		.background(SetupBackdrop())
		.preferredColorScheme(lightAppearance ? .light : .dark)
		.animation(reducedMotion ? nil : .easeInOut(duration: 0.2), value: page)
	}

	private func navigate(_ offset: Int) {
		page = page.advanced(by: offset)
	}
}
