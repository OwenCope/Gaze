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

	private var page: TourPage {
		TourPage(
			imageName: "Art/tour-backdrop.png",
			imageBundle: .main,
			title: status.isReady ? "Gaze has permission" : "Allow Gaze to enter your password",
			description: status.isReady
				? "macOS has confirmed Accessibility access.\nYou can continue with setup."
				: "Accessibility lets Gaze type your saved password at the lock screen, only after it recognises you. In System Settings, open Privacy & Security, then Accessibility, and turn on Gaze."
		)
	}

	private var primaryTitle: String { status.isReady ? "Continue" : "Open System Settings" }

	private var primaryAction: () -> Void { status.isReady ? onContinue : onOpenSettings }

	private var statusBlock: some View {
		VStack(alignment: .leading, spacing: 10) {
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
				Button("Gaze isn’t listed? Show this app in Finder", action: onRevealApp)
					.buttonStyle(.link).font(.system(size: 12))
				if let settingsError {
					Text(settingsError)
						.font(.system(size: 12)).foregroundStyle(Theme.setupSecondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.frame(maxWidth: 400)
	}

	var body: some View {
		TourSlideshowView(
			pages: [page],
			width: GazeTourSizing.panelWidth,
			continueButtonTitle: "\(primaryTitle)",
			finishButtonTitle: "\(primaryTitle)",
			onFinish: primaryAction,
			onClose: onClose ?? onSkip,
			pageMedia: { _ in AnyView(SetupPermissionFigure(isReady: status.isReady)) },
			mediaHeight: 250,
			pageAccessory: { _ in AnyView(statusBlock) },
			secondaryButtonTitle: status.isReady ? nil : "Set Up Later",
			onSecondary: status.isReady ? nil : onSkip,
			footer: position.map { AnyView(SetupProgress(position: $0)) },
			onBack: onBack
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}
}

/// The companion beside the Accessibility glyph on the tour backdrop, brightening
/// and ticking once macOS confirms access.
private struct SetupPermissionFigure: View {
	var isReady: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
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
		.accessibilityHidden(true)
	}
}
