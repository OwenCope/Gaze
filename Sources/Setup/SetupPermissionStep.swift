import AppKit
import SwiftUI

/// Asks for Accessibility access, which is what lets the password be typed.
///
/// macOS has no in-app prompt for this one — the only route is System Settings, and the app
/// cannot know it has been granted until it is asked again. So the screen watches two
/// things: coming back to the front, and a slow poll for the case where the toggle is
/// flipped while Gaze still has focus.
///
/// **It shows the row you are looking for.** The first version of this screen was a symbol
/// in a rounded tile over two lines of prose, which is the shape of every generated
/// onboarding screen on the internet and says nothing: the person is about to be dropped
/// into a System Settings list of forty apps, and "turn Gaze on in the list" does not help
/// them find it. A picture of the row — the app's real icon, its name, a switch — is what
/// they will actually be scanning for, and it is the difference between an instruction and
/// a demonstration.
///
/// Drawn rather than screenshotted, deliberately. A capture of that pane contains every app
/// on the machine and the owner's name, and shipping someone else's installed-app list
/// inside a downloadable binary is not a thing to do for a nicer illustration.
struct SetupPermissionStep: View {

	var position: SetupPosition?
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?

	@State private var isTrusted = Self.initialTrust

	/// `--preview-ungranted` forces the not-yet-allowed state.
	///
	/// The screen worth designing is the one that asks, and it is invisible on any machine
	/// where the permission is already granted — which is every machine this gets worked on
	/// after the first run. Revoking Accessibility to look at a layout is not a reasonable
	/// thing to have to do.
	private static var initialTrust: Bool {
		CommandLine.arguments.contains("--preview-ungranted") ? false : AXIsProcessTrusted()
	}

	var body: some View {
		SetupScaffold(
			position: position,
			title: isTrusted ? "Gaze can type for you" : "One switch, in System Settings",
			message: isTrusted
				? "Accessibility access is on. Gaze can enter your password at the lock screen."
				: "macOS won't let any app type at the lock screen until you allow it. Find this row and turn it on.",
			figureHeight: isTrusted ? 132 : 96,
			onBack: onBack
		) {
			if isTrusted {
				SetupGlyph(symbol: "checkmark", tint: Theme.faceID)
			} else {
				PermissionRowIllustration()
			}
		} detail: {
			if !isTrusted {
				steps.padding(.top, 26)
			}
		} actions: {
			if isTrusted {
				SetupButton(action: onContinue)
			} else {
				SetupButton(title: "Open System Settings", action: openSettings)
				Button("Set this up later", action: onSkip)
					.buttonStyle(.plain)
					.font(Typography.setupBody)
					.foregroundStyle(Theme.setupTertiary)
			}
		}
		.animation(Theme.Motion.standard, value: isTrusted)
		.onAppear { refresh() }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
		}
		// Settings can be granted without Gaze ever losing focus — the toggle lives in
		// another window, and returning to it is not an activation.
		.task {
			while !Task.isCancelled && !isTrusted {
				try? await Task.sleep(for: .seconds(1))
				refresh()
			}
		}
	}

	/// Three numbered lines, because this is a procedure carried out somewhere else.
	///
	/// Prose is the wrong shape for instructions you have to follow while looking at a
	/// different window: you come back to it, and a paragraph makes you re-read from the
	/// start to find your place. A numbered list does not.
	private var steps: some View {
		VStack(alignment: .leading, spacing: 13) {
			step(1, "Open System Settings with the button below.")
			step(2, "Scroll the list to Gaze.")
			step(3, "Turn it on. Come back here — this screen notices.")
		}
		.frame(maxWidth: 420, alignment: .leading)
	}

	private func step(_ number: Int, _ text: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 11) {
			Text("\(number)")
				.font(.system(size: 12, weight: .semibold))
				.monospacedDigit()
				.foregroundStyle(Theme.setupTertiary)
				.frame(width: 20, height: 20)
				.background {
					Circle().fill(.white.opacity(0.09))
					Circle().strokeBorder(.white.opacity(0.13), lineWidth: 1)
				}
			Text(text)
				.font(Typography.setupBody)
				.foregroundStyle(Theme.setupSecondary)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func refresh() {
		guard !CommandLine.arguments.contains("--preview-ungranted") else { return }
		let trusted = AXIsProcessTrusted()
		if trusted != isTrusted { isTrusted = trusted }
	}

	private func openSettings() {
		if let url = URL(
			string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
		{
			NSWorkspace.shared.open(url)
		}
	}
}

/// The row they are looking for, drawn, with its switch turning itself on.
///
/// The switch animates rather than sitting in one state, because the instruction is an
/// action. A static picture of a row with a switch already on says "this is what it looks
/// like when you are finished", which is the one moment they are not in.
struct PermissionRowIllustration: View {

	@State private var isOn = false

	var body: some View {
		HStack(spacing: 11) {
			Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
				.resizable()
				.frame(width: 26, height: 26)

			Text("Gaze")
				.font(.system(size: 14))
				.foregroundStyle(.white)

			Spacer(minLength: 40)

			// A switch, at the size macOS draws one. Not a `Toggle`: a real one would be
			// operable, and a control in an illustration that does nothing when clicked is
			// worse than a picture of one.
			ZStack(alignment: isOn ? .trailing : .leading) {
				Capsule()
					.fill(isOn ? Theme.faceID : Color.white.opacity(0.22))
				Circle()
					.fill(.white)
					.padding(2)
					.shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
			}
			.frame(width: 38, height: 22)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 11)
		.frame(width: 320)
		.background {
			RoundedRectangle(cornerRadius: 11, style: .continuous)
				.fill(.white.opacity(0.07))
			RoundedRectangle(cornerRadius: 11, style: .continuous)
				.strokeBorder(.white.opacity(0.12), lineWidth: 1)
		}
		.glassEffect(.regular, in: .rect(cornerRadius: 11, style: .continuous))
		.shadow(color: .black.opacity(0.35), radius: 16, y: 7)
		.task {
			// Off for a beat, on for longer. Weighted that way because the state being
			// demonstrated is *on* — the off state is only there to make the change visible.
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(900))
				withAnimation(Theme.Motion.arrive) { isOn = true }
				try? await Task.sleep(for: .milliseconds(2200))
				withAnimation(Theme.Motion.quick) { isOn = false }
			}
		}
	}
}
