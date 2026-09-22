import AppKit
import SwiftUI

/// The steps of setup.
///
/// Positioning and capturing are phases of one job in `EnrollmentModel`, so they
/// are one screen that follows the model rather than two with a Continue between
/// them — a button asking someone to confirm what the app can already see.
///
/// The three screens either side of the capture are not decoration. Setup used to
/// be welcome → capture → done, which ended on "You're all set" for an app that
/// had no password to type and no permission to type it with: it could recognise
/// you and then do nothing. Everything needed to actually unlock is asked for
/// here, in the order it becomes true — what this does, the face, the password,
/// the permission — and `done` reports which of it landed.
///
	/// The welcome and the explanation are always shown. Opening setup
/// is a request to set up, and a short path that skipped ahead to "You're all
/// set" was how someone got a success screen having done nothing. The capture
/// is shown for a first enrolment or when explicitly requested, and skipped
/// when a usable enrolment already exists so a repeat run does not save
/// another face. The password
/// and permission steps are the exception: they are the only two that can already
/// be satisfied, and there is nothing to ask when the answer is already stored.
/// Setup, start to finish.
///
/// The flow owns the camera and the enrollment model rather than the steps owning
/// them. Steps come and go as people move through, and a camera owned by a step
/// would be opened and closed at every transition — a visible stall, a fresh
/// exposure ramp each time, and enrollment progress thrown away and restarted.
///
/// There is a progress row and a back button now, and there did not used to be.
/// The old reasoning — "a progress dial for two screens is decoration" — was
/// right about two screens and stopped being right at six: an indicator earns its
/// place exactly when someone can no longer hold the remaining length in their
/// head, and four steps past a welcome is over that line.
///
/// Both live in `SetupScaffold` rather than here, and both are deliberately
/// partial. The row appears only on the four middle steps, because the welcome
/// and the finish are the ends of the flow rather than positions in it. Back
/// appears only where returning costs nothing, which rules out stepping back into
/// a capture that has already saved a face.
///
/// Dark throughout, like the rest of Gaze. Not decoration either: the screen is
/// mostly camera, and a dark surround stops the room behind the app competing
/// with the picture and keeps the face the brightest thing on it.
struct SetupFlow: View {

	let store: FaceEnrollmentStore
	var onFinish: () -> Void

	@State private var camera = CameraController()
	@State private var model: EnrollmentModel?
	@State private var step: SetupStep = .welcome
	@State private var tourRevision = 0
	@State private var failure: String?
	@State private var isPresented = false
	@State private var purpose = SetupPurpose.onboarding
	@State private var captureSession = 0
	@State private var work = SetupSessionWork()
	/// The steps this run will actually show, fixed when the flow starts.
	///
	/// Snapshotted rather than recomputed, because the password step satisfies itself the
	/// moment it succeeds — a live count would drop from four to three underneath the
	/// progress row while someone was looking at it.
	@State private var plan = SetupPlan(hasPassword: false, hasPermission: false)
	/// Which way the last move went, so the screens slide with it.
	@State private var isReturning = false

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		Group {
			switch step {
			case .welcome:
			SetupWelcomeStep(
				onContinue: advance,
				onClose: onFinish
			)
			// Recreated on restart so the tour starts fresh on reopening.
			.id(tourRevision)
			case .how:
				SetupHowStep(
					position: position(of: .how),
					onContinue: advance,
					onBack: back,
					movementCount: Preferences.shared.unlockMovementCount.rawValue
				)
			case .meetGaze:
				SetupMeetGazeStep(position: position(of: .meetGaze), onContinue: advance, onBack: back,
					movementCount: Preferences.shared.unlockMovementCount.rawValue)
			case .capture:
				SetupCaptureStep(
					position: position(of: .capture),
					camera: camera,
					model: model,
					onAuthorized: startCamera,
					onBack: purpose == .addFace ? nil : back,
					onClose: purpose == .addFace ? onFinish : nil,
					onRetry: retry
				)
				.id(captureSession)
			case .password:
				SetupPasswordStep(
					position: position(of: .password),
					onSaved: advance,
					onSkip: advance,
					onBack: backDestination(from: .password) != nil ? back : nil
				)
			case .permission:
				SetupPermissionStep(
					position: position(of: .permission),
					onContinue: advance,
					onSkip: advance,
					onBack: backDestination(from: .permission) != nil ? back : nil
				)
			case .done:
				SetupDoneStep(
					failure: failure,
					unfinished: unfinished,
					isAddingFace: purpose == .addFace,
					onDone: onFinish,
					onRetry: retry,
					// A partial first-run setup offers Settings as a second step, never a
					// redirect: Done still just closes. Opening the window enables nothing
					// and requests nothing on its own.
					onOpenSettings: purpose == .onboarding ? {
						AppActivation.bringToFront(userInitiated: true)
						openWindow(id: "settings")
						onFinish()
					} : nil,
					onTestRecognition: purpose == .onboarding ? {
						AppActivation.bringToFront(userInitiated: true)
						openWindow(id: "test")
						onFinish()
					} : nil
				)
			}
		}
		.transition(
			reduceMotion
				? .identity
				: .asymmetric(
					insertion: .offset(x: isReturning ? -12 : 12).combined(with: .opacity),
					removal: .opacity
				)
		)
		// No `.id(step)` here: it recreated every step's view on each move, throwing away
		// per-step state. Identity resets are scoped to the steps that need them — the tour
		// restarts via `tourRevision` on the welcome step, the capture via `captureSession` —
		// while the transition and the `step`-keyed animation below still slide with the flow.
		.frame(minWidth: preferredWidth, idealWidth: preferredWidth, maxWidth: preferredWidth,
			minHeight: preferredHeight, idealHeight: preferredHeight, maxHeight: preferredHeight)
		.animation(.easeInOut(duration: 0.25), value: step)
		.overlay {
			if purpose == .addFace && step == .capture {
				GazePeekingCompanion(isActive: model == nil || model?.phase == .positioning)
			}
		}
		// The user's own wallpaper, blurred and darkened — the same ground the rest of the
		// app now uses. Setup used to be flat black, which made it the one window in Gaze
		// that did not belong to the machine it was running on.
		.background {
			if step != .welcome && step != .done {
				SetupBackdrop()
					.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
			}
		}
		.preferredColorScheme(Preferences.shared.appTheme.colorScheme)
		// Back to the beginning every time the window is shown.
		//
		// A SwiftUI `Window` scene keeps its state when it is closed and reopened,
		// so without this, opening setup from Settings showed whatever screen it was
		// left on last time. Closing it on the finish screen and opening it again
		// meant being told "You're all set" without having done anything — while
		// Settings, reading the store rather than this view, still said the opposite.
		.onAppear {
			isPresented = true
			restart()
		}
		.onDisappear {
			isPresented = false
			cancelCaptureWork()
		}
		.onChange(of: SetupRequest.presentation.revision) { _, _ in
			if isPresented { restart() }
		}
		// Driven by the frame counter rather than the pose: two identical
		// consecutive poses are normal and must still advance the state machine.
		.onChange(of: camera.frameID) { _, _ in
			guard step == .capture else { return }
			model?.consume(camera.faceMissing ? nil : camera.sample)
		}
		.onChange(of: model?.phase) { _, phase in
			switch phase {
			case .complete: save()
			case .failed(let message): fail(message)
			default: break
			}
		}
	}

	// MARK: - Flow

	/// Put the flow back to its opening state.
	private func restart() {
		cancelCaptureWork()
		model = nil
		captureSession += 1
		failure = nil
		isReturning = false
		tourRevision += 1
		// A screen Settings asked for wins over the launch flag, which wins over the start.
		let requested = SetupRequest.consumePendingStep() ?? Self.consumeLaunchStep()
		purpose = SetupRequest.presentation.purpose
		plan = makePlan(including: requested)
		step = requested ?? (purpose == .addFace ? .capture : .welcome)
		if step == .capture && purpose == .onboarding { OnboardingHistory.markPresented() }
	}

	/// Whether the launch flag has already been honoured.
	///
	/// It must be, exactly once. `restart()` runs every time the window appears — including
	/// when someone presses "Add a Face" — and reading the flag there meant a debug launch
	/// argument hijacked every subsequent opening of setup for the life of the process:
	/// press Add a Face, land on the password screen, forever. A launch flag describes the
	/// launch, not the window.
	private static var didConsumeLaunchStep = false

	static func consumeLaunchStep() -> SetupStep? {
		guard !didConsumeLaunchStep else { return nil }
		didConsumeLaunchStep = true
		return launchStep
	}

	/// `--setup-step=how|capture|password|permission|done` opens straight onto one screen.
	///
	/// Working on the permission screen otherwise means clicking through the whole flow
	/// after every rebuild, and screenshotting one screen means getting there by hand each
	/// time. Debug-only in spirit; harmless in a release because nobody passes the flag.
	static var launchStep: SetupStep? {
		guard
			let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--setup-step=") }),
			let name = argument.split(separator: "=").last
		else { return nil }
		switch name {
		case "welcome": return .welcome
		case "how": return .how
		case "meetGaze": return .meetGaze
		case "capture": return .capture
		case "password": return .password
		case "permission": return .permission
		case "done": return .done
		default: return nil
		}
	}

	/// The steps this run will show, decided once.
	///
	/// The explanation is always in it. The capture is in it for a first enrolment
	/// or when explicitly requested, and skipped when a usable enrolment already
	/// exists so reopening setup does not save another face. The password and the permission
	/// are in it only when they are not already done — there is nothing to ask when the
	/// answer is already on disk, and a screen that exists only to be skipped past is a
	/// step in the count that nobody takes.
	/// - Parameter forced: a screen Settings asked to open on, which is included whether or
	///   not it is already satisfied. Without this the plan would drop the very screen the
	///   flow is about to show — a step on screen but absent from the progress row, and a
	///   `nextStep` that skips straight past it the moment anything advances.
	private func makePlan(including forced: SetupStep? = nil) -> SetupPlan {
		if purpose == .addFace { return SetupPlan(hasPassword: false, hasPermission: false, purpose: .addFace) }
		return SetupPlan(hasPassword: PasswordVault.hasPassword,
			hasPermission: SetupPermissionStatus.current.isReady, including: forced,
			hasEnrollment: store.isEnrolled, usesWelcomeTour: true)
	}

	/// Where a step sits in the progress row, or nil for the two ends of the flow.
	private func position(of step: SetupStep) -> SetupPosition? {
		guard purpose == .onboarding else { return nil }
		guard let index = plan.steps.firstIndex(of: step) else { return nil }
		return SetupPosition(index: index, count: plan.steps.count)
	}

	/// Arms unlocking once a first-run setup lands on done with nothing outstanding.
	///
	/// Setup collects everything unlocking needs — the face, the password, the permission —
	/// so leaving the backend off here would make the done screen's promise false.
	private func enableUnlockIfSetupComplete() {
		guard purpose == .onboarding, failure == nil, unfinished.isComplete else { return }
		guard !AppServices.isUIReview else { return }
		PasswordReplaySafety.setEnabled(true)
		Preferences.shared.unlockBackend = .keystroke
		AppServices.shared.startUnlockTrigger()
	}

	private func advance() {
		guard let next = nextStep(after: step) else { return }
		isReturning = false
		withAnimation(stepAnimation) { step = next }
		if next == .capture && purpose == .onboarding { OnboardingHistory.markPresented() }
		if next == .done { enableUnlockIfSetupComplete() }
	}

	/// One screen back.
	///
	/// Only offered where returning costs nothing. There is no way back into the capture
	/// once it has succeeded — the face is saved by then, and a "back" that silently
	/// re-ran enrolment would be destroying work to look consistent. Leaving the capture
	/// forwards is the only way out of it.
	private func back() {
		guard let previous = backDestination(from: step) else { return }
		if step == .capture {
			guard model?.phase != .complete else { return }
			cancelCaptureWork()
			model = nil
		}
		isReturning = true
		withAnimation(stepAnimation) { step = previous }
	}

	/// Where Back goes from a step, or nil when there is nowhere to go.
	///
	/// A destination of capture is blocked once the capture has succeeded: the face is
	/// saved by then, so stepping back into it would re-run enrolment over finished work.
	private func backDestination(from step: SetupStep) -> SetupStep? {
		guard let previous = plan.previous(before: step) else { return nil }
		if previous == .capture, model?.phase == .complete { return nil }
		return previous
	}

	/// The next screen worth showing.
	///
	/// Only the password and the permission are skippable, and only because they are
	/// the only steps whose answer can already be on disk. Asking again for a password
	/// that is already stored is asking someone to prove something the app knows, and
	/// the Accessibility screen has nothing to do once the toggle is on.
	private func nextStep(after current: SetupStep) -> SetupStep? {
		plan.next(after: current)
	}

	private var stepAnimation: Animation? {
		reduceMotion ? nil : .easeInOut(duration: 0.25)
	}

	/// One window size for the whole flow: the tour and the setup steps share it,
	/// so moving from the tour into capture never resizes the window.
	private var preferredWidth: CGFloat { 760 }
	private var preferredHeight: CGFloat { 680 }

	/// What is still missing once the flow reaches the end.
	///
	/// Read at the point it is shown rather than tracked as the user goes, so skipping
	/// the password screen and then granting it in another window still reports the
	/// truth. `done` uses this to avoid claiming a success it cannot back up.
	private var unfinished: SetupUnfinished {
		guard purpose == .onboarding else { return SetupUnfinished() }
		return SetupUnfinished(
			needsPassword: !PasswordVault.hasPassword,
			needsAccessibility: !SetupPermissionStatus.current.isReady
		)
	}

	/// Called once the capture screen has permission — not on entry.
	///
	/// Starting the camera before permission exists is what puts the system's own
	/// prompt on screen at a moment nobody asked for it.
	private func startCamera() {
		guard isPresented, step == .capture, model == nil else { return }
		model = EnrollmentModel(embedder: store.embedder)
		work.run { revision in
			guard work.isCurrent(revision), isPresented, step == .capture, model != nil else { return }
			await camera.start()
		}
	}

	private func save() {
		guard isPresented, step == .capture, let model, model.phase == .complete else { return }
		work.run { revision in await commit(model, revision: revision) }
	}

	private func commit(_ model: EnrollmentModel, revision: UUID) async {
		guard work.isCurrent(revision), isPresented, step == .capture else { return }
		// Say so rather than returning quietly. Returning left the capture screen up
		// with a full ring and nothing happening — the enrollment was finished and
		// the flow simply stopped, which looks like a hang and loses the work.
		guard let cameraID = camera.boundDeviceID else {
			fail("Lost the camera before your face could be saved. Try again.")
			return
		}
		do {
			try await store.add(prints: model.prints, cameraID: cameraID)
			guard work.isCurrent(revision), isPresented, step == .capture else { return }
			camera.stop()
			failure = nil
			// On to the password rather than straight to the end: the face is saved, which
			// is not the same as being able to unlock anything.
			let next = nextStep(after: .capture) ?? .done
			isReturning = false
			withAnimation(stepAnimation) { step = next }
			if next == .done { enableUnlockIfSetupComplete() }
		} catch {
			guard work.isCurrent(revision), isPresented, step == .capture else { return }
			fail("Couldn't save your face: \(error.localizedDescription)")
		}
	}

	private func fail(_ message: String) {
		camera.stop()
		failure = message
		isReturning = false
		withAnimation(stepAnimation) { step = .done }
	}

	/// Start over after a failure.
	///
	/// A fresh model rather than `reset()` on the old one: whatever it captured
	/// before giving up is exactly the material that failed, and carrying it into
	/// the retry is how the second attempt fails the same way as the first.
	private func retry() {
		cancelCaptureWork()
		failure = nil
		model = nil
		isReturning = false
		if purpose == .onboarding { OnboardingHistory.markPresented() }
		withAnimation(stepAnimation) { step = .capture }
		startCamera()
	}

	private func cancelCaptureWork() {
		work.cancel()
		camera.stop()
	}
}
