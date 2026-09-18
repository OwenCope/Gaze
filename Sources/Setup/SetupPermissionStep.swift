import AppKit
import ApplicationServices
import SwiftUI

struct SetupPermissionStatus: Equatable {
	var accessibility: Bool
	var keyboardEvents: Bool
	var isReady: Bool { accessibility && keyboardEvents }

	static var current: Self {
		Self(accessibility: AXIsProcessTrusted(), keyboardEvents: CGPreflightPostEventAccess())
	}
}

struct SetupPermissionStep: View {
	var position: SetupPosition?
	var onContinue: () -> Void
	var onSkip: () -> Void
	var onBack: (() -> Void)?
	@State private var status = SetupPermissionStatus(accessibility: false, keyboardEvents: false)
	@State private var settingsError: String?

	var body: some View {
		SetupPermissionContent(
			position: position, status: status, settingsError: settingsError,
			onContinue: onContinue, onSkip: onSkip, onBack: onBack,
			onOpenSettings: openSettings,
			onRevealApp: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
		)
		.onAppear { refresh() }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			refresh()
		}
		.task {
			while !Task.isCancelled {
				do { try await Task.sleep(for: .seconds(1)) }
				catch { return }
				refresh()
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
		let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
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
	var onOpenSettings: () -> Void
	var onRevealApp: () -> Void
	@State private var showsInfo = false

	var body: some View {
		SetupScaffold(
			position: position,
			title: status.isReady ? "Gaze has permission" : "Allow Gaze to enter your password",
			message: status.isReady
				? "macOS has confirmed Accessibility access.\nYou can continue with setup."
				: "Accessibility lets Gaze type your saved password at the lock screen, only after it recognises you.\nYou control this in System Settings, and you can skip it for now.",
			figureHeight: 84,
			onBack: onBack
		) {
			SetupGlyph(symbol: "hand.raised", tint: status.isReady ? Theme.faceID : nil)
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
					Button { showsInfo.toggle() } label: {
						Image(systemName: "info.circle").font(.system(size: 16))
					}
					.buttonStyle(.borderless)
					.accessibilityLabel("About Accessibility access")
					.help("Why Gaze needs this permission")
					.popover(isPresented: $showsInfo) {
						Text("Gaze checks your face and movement before entering your saved login password. Accessibility enables keyboard events; it does not approve a face or replace macOS authentication. A Keychain password prompt is separate from this permission.")
							.font(.system(size: 13)).frame(width: 280).padding(20)
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
