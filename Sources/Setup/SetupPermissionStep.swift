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
	@State private var settingsOpened = false
	@State private var showRelaunch = false

	static var isOutsideApplications: Bool {
		let path = Bundle.main.bundleURL.path
		if path.contains("/build/") { return false }
		if path.contains("/AppTranslocation/") { return true }
		if path.hasPrefix("/Volumes/") { return true }
		if path.hasPrefix("/Applications/") { return false }
		let homeApps = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
		if path == homeApps || path.hasPrefix(homeApps + "/") { return false }
		return true
	}

	var body: some View {
		SetupPermissionContent(
			position: position, status: status, settingsError: settingsError,
			showRelaunch: showRelaunch,
			onContinue: onContinue, onSkip: onSkip, onBack: onBack, onClose: onClose,
			onOpenSettings: openSettings,
			onRevealApp: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) },
			onRelaunch: relaunchForPermission
		)
		.onAppear { refresh() }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
			guard settingsOpened else { return }
			settingsOpened = false
			showRelaunch = false
			Task { @MainActor in
				try? await Task.sleep(for: .seconds(4))
				if !SetupPermissionStatus.current.isReady { showRelaunch = true }
			}
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
		if status.isReady { showRelaunch = false }
	}

	private func openSettings() {
		settingsOpened = true
		showRelaunch = false
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
		guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
			settingsError = "Open System Settings → Privacy & Security → Accessibility."
			return
		}
		settingsError = NSWorkspace.shared.open(url) ? nil : "Open System Settings → Privacy & Security → Accessibility."
		refresh()
	}

	private func relaunchForPermission() {
		let bundlePath = Bundle.main.bundleURL.path
		let inner = "sleep 0.6; /usr/bin/open -n \(Self.shQuote(bundlePath)) --args --setup-step=permission"
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", "nohup /bin/bash -c \(Self.shQuote(inner)) >/dev/null 2>&1 &"]
		try? process.run()
		NSApp.terminate(nil)
	}

	private static func shQuote(_ value: String) -> String {
		"'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
	}
}

struct SetupPermissionContent: View {
	var position: SetupPosition?
	let status: SetupPermissionStatus
	var settingsError: String?
	var showRelaunch = false
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?
	var onClose: (() -> Void)? = nil
	var onOpenSettings: () -> Void
	var onRevealApp: () -> Void
	var onRelaunch: () -> Void = {}

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
			if !status.isReady, SetupPermissionStep.isOutsideApplications {
				StatusLine(kind: .warning,
					message: "Gaze is running from outside Applications. Move it to Applications, then open it from there.")
			}
			if !status.isReady {
				Button(SetupPermissionStep.isOutsideApplications
					? "Show Gaze in Finder"
					: "Already on, or not listed? Show Gaze in Finder", action: onRevealApp)
					.buttonStyle(.link).font(.system(size: 12))
			}
			if showRelaunch, !status.isReady {
				Button("Set Up Later", action: onSkip)
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
			secondaryButtonTitle: status.isReady ? nil : (showRelaunch ? "Quit and Reopen" : "Set Up Later"),
			onSecondary: status.isReady ? nil : (showRelaunch ? onRelaunch : onSkip),
			footer: position.map { AnyView(SetupProgress(position: $0)) },
			onBack: onBack
		)
		.frame(width: GazeTourSizing.panelWidth, height: GazeTourSizing.panelHeight)
	}
}

