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
				? "macOS has confirmed access. You can continue."
				: "Lets Gaze type your password at the lock screen, only after it recognises you."
		)
	}

	private var primaryTitle: String { status.isReady ? "Continue" : "Open System Settings" }

	private var primaryAction: () -> Void { status.isReady ? onContinue : onOpenSettings }

	private var statusBlock: some View {
		VStack(spacing: 6) {
			if !status.isReady {
				Button("Already on, or not listed? Show Gaze in Finder", action: onRevealApp)
					.buttonStyle(.link).font(.system(size: 12))
			}
			if let settingsError {
				Text(settingsError)
					.font(.system(size: 12)).foregroundStyle(Theme.setupSecondary)
					.fixedSize(horizontal: false, vertical: true)
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
			pageMedia: { _ in AnyView(SetupAccessibilityDemo(isReady: status.isReady)) },
			pageAccessory: { _ in AnyView(statusBlock) },
			secondaryButtonTitle: status.isReady ? nil : "Set Up Later",
			onSecondary: status.isReady ? nil : onSkip,
			footer: position.map { AnyView(SetupProgress(position: $0)) },
			onBack: onBack
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}
}

