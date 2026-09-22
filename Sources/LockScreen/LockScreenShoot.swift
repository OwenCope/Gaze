import AppKit
import SwiftUI

/// A stand-in for the lock screen, for taking pictures of.
///
/// The real lock screen cannot be captured *while Gaze is unlocking it*. macOS runs the
/// login window in a separate secure session: `screencapture` returns black there, and a
/// screen recording is killed the instant the screen locks — measured, not assumed. So the
/// one shot the app most wants of itself, the panel recognising a face at the lock screen,
/// is the one shot the system will not let it take.
///
/// The answer is not to redraw the lock screen. Five attempts at that produced something
/// that was wrong in a different way each time, because a lock screen is a hundred small
/// decisions — clock weight, the gap under the date, how much the wallpaper is dimmed, the
/// exact width of the password field — and being wrong about any one of them is what makes
/// a picture read as an imitation.
///
/// So: **a real screenshot of the real lock screen is the backdrop**, and the real
/// `NotchCapsule` runs on top of it. Both halves are genuine; only their combination is
/// staged, and the combination is the part the system forbids rather than the part anyone
/// would doubt. The still is `Resources/Art/lockscreen-base.png`, captured on this Mac at
/// its own resolution, so it lands pixel-for-pixel.
///
/// Nothing here runs at the actual lock screen — `LockScreenSpace` handles that — and it is
/// behind a launch flag so it cannot appear by accident.
///
/// `--shoot-lockscreen` loops the sequence, for recording. `--shoot-once` holds on the
/// tick, for a still. Escape quits.
@MainActor
final class LockScreenShoot {

	private var window: NSWindow?
	private var capsule: NotchCapsuleController?
	private var keyMonitor: Any?

	func run() {
		guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

		let window = NSWindow(
			contentRect: screen.frame,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		// Below the capsule but above everything else, so the panel Gaze actually draws
		// sits on top of this the way it sits on top of the real lock screen.
		window.level = .screenSaver
		window.backgroundColor = .black
		window.isOpaque = true
		window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

		// Sized and pinned explicitly. Assigning a hosting view to `contentView` and then
		// resizing the window leaves it at its own intrinsic size, laid out inside a frame
		// wider than itself.
		let hosting = NSHostingView(rootView: LockScreenShootView())
		hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
		hosting.autoresizingMask = [.width, .height]
		window.contentView = hosting
		window.setFrame(screen.frame, display: true)
		window.makeKeyAndOrderFront(nil)
		self.window = window

		NSApp.activate(ignoringOtherApps: true)

		let capsule = NotchCapsuleController()
		self.capsule = capsule
		capsule.show(phase: .locked)

		Task {
			// Looped, because the thing being recorded is a sequence rather than a moment.
			// One pass means starting the recording and the app in the right order and
			// getting it right first time; looping means starting the recording whenever
			// and trimming afterwards, which is how anyone captures a UI animation.
			let loops = !CommandLine.arguments.contains("--shoot-once")
			repeat {
				capsule.update(phase: .locked)
				try? await Task.sleep(for: .seconds(2))
				capsule.update(phase: .scanning)
				try? await Task.sleep(for: .seconds(3))
				capsule.update(phase: .success)
				try? await Task.sleep(for: .seconds(loops ? 3 : 3600))
			} while loops && !Task.isCancelled
		}

		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			// 53 is Escape. Matched by key code rather than characters so it works on any
			// keyboard layout.
			if event.keyCode == 53 {
				self?.stop()
				return nil
			}
			return event
		}
	}

	private func stop() {
		if let monitor = keyMonitor {
			NSEvent.removeMonitor(monitor)
			keyMonitor = nil
		}
		capsule?.hide()
		capsule = nil
		window?.orderOut(nil)
		window = nil
		NSApp.terminate(nil)
	}
}

/// The lock screen still, filling the display.
///
/// Deliberately nothing else. Everything that used to be drawn here — clock, account
/// picture, name, password field, a dimming gradient over the wallpaper — is already in
/// the photograph, correct, because macOS drew it.
struct LockScreenShootView: View {

	var body: some View {
		ZStack {
			Color.black

			if let image = Self.base {
				Image(nsImage: image)
					.resizable()
					// `.fill`, so a still captured at a different resolution than the screen
					// it is shown on covers rather than letterboxes. At matching resolution
					// — the normal case — this is a 1:1 draw.
					.aspectRatio(contentMode: .fill)
			} else {
				// Nothing to show and nothing to invent. A black screen with the capsule on
				// it is at least honest about being a preview.
				VStack(spacing: 8) {
					Image(systemName: "photo.badge.exclamationmark")
						.font(.system(size: 34))
					Text("Resources/Art/lockscreen-base.png is missing")
						.font(.system(size: 13))
				}
				.foregroundStyle(.white.opacity(0.5))
			}
		}
		.ignoresSafeArea()
	}

	private static let base: NSImage? = {
		guard
			let url = Bundle.main.url(
				forResource: "lockscreen-base", withExtension: "png", subdirectory: "Art")
		else { return nil }
		return NSImage(contentsOf: url)
	}()
}
