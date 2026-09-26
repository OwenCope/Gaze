import AppKit
import ApplicationServices
import SwiftUI

struct SetupPermissionStatus: Equatable {
	var accessibility: Bool
	var keyboardEvents: Bool
	var isReady: Bool { accessibility && keyboardEvents }

	static var current: Self {
		#if PRODUCT_CAPTURE
		// Product captures photograph a finished setup; only the capture tool's build sets this.
		if ProductCaptureDemo.isOn { return Self(accessibility: true, keyboardEvents: true) }
		#endif
		return Self(accessibility: AXIsProcessTrusted(), keyboardEvents: CGPreflightPostEventAccess())
	}
}

struct SetupPermissionStep: View {
	var position: SetupPosition?
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)? = nil
	@State private var status = SetupPermissionStatus(accessibility: false, keyboardEvents: false)
	@State private var settingsError: String?

	var body: some View {
		SetupPermissionContent(
			position: position, status: status, settingsError: settingsError,
			onContinue: onContinue, onSkip: onSkip, onBack: onBack, onClose: onClose,
			onOpenSettings: openSettings,
			onRevealApp: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
		)
		.onAppear { refresh() }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
		}
		.task {
			var delaySeconds = 1.0
			while !Task.isCancelled {
				do { try await Task.sleep(for: .seconds(delaySeconds)) }
				catch { return }
				refresh()
				if status.isReady { return }
				delaySeconds = min(delaySeconds * 2, 8)
			}
		}
	}

	private func refresh() {
		guard !CommandLine.arguments.contains("--preview-ungranted") else { return }
		status = .current
	}

	private func openSettings() {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
		guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
			settingsError = "Open System Settings → Privacy & Security → Accessibility."
			return
		}
		settingsError = NSWorkspace.shared.open(url) ? nil : "Open System Settings → Privacy & Security → Accessibility."
		refresh()
	}
}

struct SetupPermissionContent: View {
	var position: SetupPosition?
	let status: SetupPermissionStatus
	var settingsError: String?
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)? = nil
	var onOpenSettings: () -> Void
	var onRevealApp: () -> Void

	var body: some View {
		SetupScaffold(
			position: position,
			title: status.isReady ? "Gaze has permission" : "Allow Gaze to enter your password",
			message: status.isReady
				? "macOS has confirmed Accessibility access.\nYou can continue with setup."
				: "Accessibility lets Gaze type your saved password at the lock screen, only after it recognises you.\nYou control this in System Settings, and you can skip it for now.",
			figureHeight: 200,
			onBack: onBack,
			onClose: onClose
		) {
			SetupPermissionFigure(isReady: status.isReady)
		} detail: {
			VStack(alignment: .leading, spacing: 18) {
				HStack(spacing: 12) {
					Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
						.resizable().frame(width: 32, height: 32)
						.accessibilityHidden(true)
					VStack(alignment: .leading, spacing: 3) {
						Text("Gaze").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
						Text(status.isReady ? "Access enabled" : status.accessibility ? "Waiting for macOS to confirm" : "Access not enabled")
							.font(.system(size: 12)).foregroundStyle(Theme.setupSecondary)
					}
					Spacer()
					InfoButton(title: "About Accessibility access") {
						Text("Gaze checks your face and movement before entering your saved login password. Accessibility enables keyboard events; it does not approve a face or replace macOS authentication. A Keychain password prompt is separate from this permission.")
					}
				}
				.padding(14)
				.background(.primary.opacity(0.06), in: .rect(cornerRadius: 12))

				if !status.isReady {
					VStack(alignment: .leading, spacing: 10) {
						instruction(1, "Open Privacy & Security → Accessibility.")
						instruction(2, "Turn on Gaze, then return to this window.")
					}
					Button("Gaze isn’t listed? Show this app in Finder", action: onRevealApp)
						.buttonStyle(.link).font(.system(size: 12))
					Text(settingsError ?? (status.accessibility
						? "If access stays pending, quit and reopen this copy of Gaze."
						: "Use + in Accessibility to add this copy of Gaze if needed."))
						.font(.system(size: 12)).foregroundStyle(Theme.setupSecondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.frame(maxWidth: 400)
			.padding(.top, 24)
		} actions: {
			if status.isReady {
				SetupButton(action: onContinue)
			} else {
				SetupButton(title: "Open System Settings", action: onOpenSettings)
				SetupSecondaryButton(title: "Set Up Later", action: onSkip)
			}
		}
	}

	private func instruction(_ number: Int, _ text: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 12) {
			Text("\(number).")
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(Theme.setupTertiary)
			Text(text).font(.system(size: 13)).foregroundStyle(Theme.setupSecondary)
		}
	}
}

/// The companion beside the Accessibility glyph on the tour backdrop, brightening
/// and ticking once macOS confirms access.
private struct SetupPermissionFigure: View {
	var isReady: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			if let url = Bundle.main.url(forResource: "tour-backdrop", withExtension: "png", subdirectory: "Art"),
				let image = NSImage(contentsOf: url)
			{
				Image(nsImage: image)
					.resizable()
					.scaledToFill()
			} else {
				Color(white: 0.06)
			}
			HStack(spacing: 40) {
				GazeLookingCompanion(look: 1, happy: isReady)
					.frame(width: 110, height: 110)
				Image(systemName: isReady ? "checkmark.circle.fill" : "accessibility")
					.font(.system(size: 52, weight: .medium))
					.foregroundStyle(.white)
					.symbolRenderingMode(.monochrome)
					.contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.accessibilityHidden(true)
	}
}
