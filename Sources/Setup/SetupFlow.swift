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
/// The welcome, the explanation and the capture are always shown. Opening setup
/// is a request to set up, and a short path that skipped ahead to "You're all
/// set" was how someone got a success screen having done nothing. The password
/// and permission steps are the exception: they are the only two that can already
/// be satisfied, and there is nothing to ask when the answer is already stored.
enum SetupStep: Int, CaseIterable {
	case welcome
	case how
	case capture
	case password
	case permission
	case done
}

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
	@State private var failure: String?
	/// The steps this run will actually show, fixed when the flow starts.
	///
	/// Snapshotted rather than recomputed, because the password step satisfies itself the
	/// moment it succeeds — a live count would drop from four to three underneath the
	/// progress row while someone was looking at it.
	@State private var plan: [SetupStep] = []
	/// Which way the last move went, so the screens slide with it.
	@State private var isReturning = false

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		Group {
			switch step {
			case .welcome:
				SetupWelcomeStep(onContinue: advance, onSkip: onFinish)
			case .how:
				SetupHowStep(
					position: position(of: .how),
					onContinue: advance,
					onBack: back
				)
			case .capture:
				SetupCaptureStep(
					position: position(of: .capture),
					camera: camera,
					model: model,
					onAuthorized: startCamera,
					onBack: back
				)
			case .password:
				SetupPasswordStep(
					position: position(of: .password),
					onSaved: advance,
					onSkip: advance
				)
			case .permission:
				SetupPermissionStep(
					position: position(of: .permission),
					onContinue: advance,
					onSkip: advance,
					onBack: plan.contains(.password) ? back : nil
				)
			case .done:
				SetupDoneStep(
					failure: failure,
					unfinished: unfinished,
					onDone: onFinish,
					onRetry: retry
				)
			}
		}
		// Content moves with the direction of travel while the chrome stays put, which is
		// what makes six screens read as one window rather than six windows. Short: the
		// distance says "next", and anything longer says "page".
		//
		// Under "Reduce Motion" it becomes a plain cross-fade. A screen sliding in from the
		// side is the other large movement in setup — the one the setting most directly
		// asks about — and a fade still says "this replaced that" without moving anything
		// across the display.
		.transition(
			reduceMotion
				? .opacity
				: .asymmetric(
					insertion: .offset(x: isReturning ? -26 : 26).combined(with: .opacity),
					removal: .offset(x: isReturning ? 26 : -26).combined(with: .opacity)
				)
		)
		.id(step)
		.frame(width: 880, height: 660)
		// The user's own wallpaper, blurred and darkened — the same ground the rest of the
		// app now uses. Setup used to be flat black, which made it the one window in Gaze
		// that did not belong to the machine it was running on.
		.background(WallpaperBackdrop(style: .setup))
		.preferredColorScheme(.dark)
		// Back to the beginning every time the window is shown.
		//
		// A SwiftUI `Window` scene keeps its state when it is closed and reopened,
		// so without this, opening setup from Settings showed whatever screen it was
		// left on last time. Closing it on the finish screen and opening it again
		// meant being told "You're all set" without having done anything — while
		// Settings, reading the store rather than this view, still said the opposite.
		.onAppear { restart() }
		.onDisappear { camera.stop() }
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
		camera.stop()
		model = nil
		failure = nil
		isReturning = false
		// A screen Settings asked for wins over the launch flag, which wins over the start.
		let requested = SetupRequest.consumePendingStep()
		plan = makePlan(including: requested)
		step = requested ?? Self.consumeLaunchStep() ?? .welcome
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
		case "capture": return .capture
		case "password": return .password
		case "permission": return .permission
		case "done": return .done
		default: return nil
		}
	}

	/// The steps this run will show, decided once.
	///
	/// The explanation and the capture are always in it. The password and the permission
	/// are in it only when they are not already done — there is nothing to ask when the
	/// answer is already on disk, and a screen that exists only to be skipped past is a
	/// step in the count that nobody takes.
	/// - Parameter forced: a screen Settings asked to open on, which is included whether or
	///   not it is already satisfied. Without this the plan would drop the very screen the
	///   flow is about to show — a step on screen but absent from the progress row, and a
	///   `nextStep` that skips straight past it the moment anything advances.
	private func makePlan(including forced: SetupStep? = nil) -> [SetupStep] {
		var steps: [SetupStep] = [.how, .capture]
		if !PasswordVault.hasPassword || forced == .password { steps.append(.password) }
		if !AXIsProcessTrusted() || forced == .permission { steps.append(.permission) }
		return steps
	}

	/// Where a step sits in the progress row, or nil for the two ends of the flow.
	private func position(of step: SetupStep) -> SetupPosition? {
		guard let index = plan.firstIndex(of: step) else { return nil }
		return SetupPosition(index: index, count: plan.count)
	}

	private func advance() {
		guard let next = nextStep(after: step) else { return }
		isReturning = false
		withAnimation(Theme.Motion.standard) { step = next }
	}

	/// One screen back.
	///
	/// Only offered where returning costs nothing. There is no way back into the capture
	/// once it has succeeded — the face is saved by then, and a "back" that silently
	/// re-ran enrolment would be destroying work to look consistent. Leaving the capture
	/// forwards is the only way out of it.
	private func back() {
		let previous: SetupStep?
		switch step {
		case .how:
			previous = .welcome
		case .capture:
			// Nothing is enrolled yet, so this one is free — but the camera and the model
			// have to go with it, or coming back finds a stopped camera and a model that
			// `startCamera` will refuse to replace.
			camera.stop()
			model = nil
			previous = .how
		case .permission:
			previous = plan.contains(.password) ? .password : nil
		default:
			previous = nil
		}
		guard let previous else { return }
		isReturning = true
		withAnimation(Theme.Motion.standard) { step = previous }
	}

	/// The next screen worth showing.
	///
	/// Only the password and the permission are skippable, and only because they are
	/// the only steps whose answer can already be on disk. Asking again for a password
	/// that is already stored is asking someone to prove something the app knows, and
	/// the Accessibility screen has nothing to do once the toggle is on.
	private func nextStep(after current: SetupStep) -> SetupStep? {
		var candidate = SetupStep(rawValue: current.rawValue + 1)
		while let next = candidate, isSatisfied(next) {
			candidate = SetupStep(rawValue: next.rawValue + 1)
		}
		return candidate
	}

	/// A step is "satisfied" — and so skippable — only if it is not part of this run's plan.
	///
	/// The plan already encodes the decision, including the case where Settings asked for a
	/// screen that is technically satisfied. Re-deriving skippability from `PasswordVault`
	/// here as well meant the two disagreed: the plan said "show the password screen", and
	/// the first `advance()` read the vault, saw a stored password and stepped over it.
	private func isSatisfied(_ candidate: SetupStep) -> Bool {
		switch candidate {
		case .password, .permission: return !plan.contains(candidate)
		default: return false
		}
	}

	/// What is still missing once the flow reaches the end.
	///
	/// Read at the point it is shown rather than tracked as the user goes, so skipping
	/// the password screen and then granting it in another window still reports the
	/// truth. `done` uses this to avoid claiming a success it cannot back up.
	private var unfinished: SetupUnfinished {
		SetupUnfinished(
			needsPassword: !PasswordVault.hasPassword,
			needsAccessibility: !AXIsProcessTrusted()
		)
	}

	/// Called once the capture screen has permission — not on entry.
	///
	/// Starting the camera before permission exists is what puts the system's own
	/// prompt on screen at a moment nobody asked for it.
	private func startCamera() {
		guard model == nil else { return }
		model = EnrollmentModel(embedder: store.embedder)
		Task { await camera.start() }
	}

	private func save() {
		guard let model else { return }
		// Say so rather than returning quietly. Returning left the capture screen up
		// with a full ring and nothing happening — the enrollment was finished and
		// the flow simply stopped, which looks like a hang and loses the work.
		guard let cameraID = camera.boundDeviceID else {
			fail("Lost the camera before your face could be saved. Try again.")
			return
		}
		do {
			try store.add(prints: model.prints, cameraID: cameraID)
			camera.stop()
			failure = nil
			// On to the password rather than straight to the end: the face is saved, which
			// is not the same as being able to unlock anything.
			let next = nextStep(after: .capture) ?? .done
			isReturning = false
			withAnimation(Theme.Motion.standard) { step = next }
		} catch {
			fail("Couldn't save your face: \(error.localizedDescription)")
		}
	}

	private func fail(_ message: String) {
		camera.stop()
		failure = message
		isReturning = false
		withAnimation(Theme.Motion.standard) { step = .done }
	}

	/// Start over after a failure.
	///
	/// A fresh model rather than `reset()` on the old one: whatever it captured
	/// before giving up is exactly the material that failed, and carrying it into
	/// the retry is how the second attempt fails the same way as the first.
	private func retry() {
		failure = nil
		model = EnrollmentModel(embedder: store.embedder)
		isReturning = false
		withAnimation(Theme.Motion.standard) { step = .capture }
		Task { await camera.start() }
	}
}
