import SwiftUI
import TipKit

struct NotchAnimationPreview: View {
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	let settings: Preferences
	@State private var model = NotchCapsuleModel()
	@State private var playback: Task<Void, Never>?
	@State private var isPlaying = false
	@State private var selectedPhase: PreviewPhase = .scanning
	@State private var wallpaper = DesktopWallpaper.shared
	@State private var panelTip = GazePanelPreviewTip()

	/// The preview tip, or nil outside normal launches so review, scan-only and
	/// browser-only modes neither show tips nor mutate tip history.
	private var previewTip: (any Tip)? {
		AppServices.isUIReview ? nil : panelTip
	}

	private enum PreviewPhase: String, CaseIterable, Identifiable {
		case locked = "Locked"
		case scanning = "Scanning"
		case challenge = "Turn head"
		case rejected = "Rejected"
		case success = "Verified"
		case pending = "Waiting for macOS"
		case unlocked = "Unlocked"
		var id: String { rawValue }
		var phase: NotchCapsuleModel.Phase {
			switch self {
			case .locked: return .locked
			case .scanning: return .scanning
			case .challenge:
				return .challenge(prompt: "Turn your head left", symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
			case .rejected: return .spoofRejected
			case .success: return .success
			case .pending: return .pending
			case .unlocked: return .unlocked
			}
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			NotchPreviewCanvas(model: model, widthAdjust: settings.notchWidthAdjust,
				heightAdjust: settings.notchHeightAdjust, wallpaper: wallpaper.image)
				.frame(height: 280)
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("Notch preview: \(selectedPhase.rawValue)")
			ViewThatFits(in: .horizontal) {
				HStack {
					phasePicker
					Spacer()
					Text("Camera off").foregroundStyle(.secondary)
					playbackButton
				}
				VStack(alignment: .leading, spacing: 10) {
					phasePicker
					HStack {
						Text("Camera off").foregroundStyle(.secondary)
						Spacer()
						playbackButton
					}
				}
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 12)
		}
		.onAppear {
			wallpaper.load()
			syncAppearance()
			model.phase = selectedPhase.phase
			model.isExpanded = true
		}
		.onChange(of: selectedPhase) { _, phase in model.phase = phase.phase }
		.onChange(of: settings.panelShape) { _, _ in syncAppearance() }
		.onChange(of: settings.notchStyle) { _, _ in syncAppearance() }
		.onChange(of: settings.glyphPlacement) { _, _ in syncAppearance() }
		.onChange(of: settings.notchTransparency) { _, _ in syncAppearance() }
		.onChange(of: reduceTransparency) { _, _ in syncAppearance() }
		.onChange(of: reduceMotion) { _, _ in stop() }
		.onChange(of: scenePhase) { _, phase in
			if phase != .active { stop() }
		}
		.onDisappear { stop() }
	}

	private var phasePicker: some View {
		Picker("Preview", selection: $selectedPhase) {
			ForEach(PreviewPhase.allCases) { Text($0.rawValue).tag($0) }
		}
		.fixedSize()
		.disabled(isPlaying)
	}

	private var playbackButton: some View {
		Button(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill") {
			if isPlaying { stop() } else { play() }
		}
		.popoverTip(previewTip)
		.help(isPlaying
			? "Stop the simulated preview. The camera remains off."
			: "Play a simulated preview. The camera remains off.")
	}

	private func syncAppearance() {
		model.shape = settings.panelShape
		model.style = settings.notchStyle
		model.glyphPlacement = settings.glyphPlacement
		model.transparency = settings.notchTransparency
		model.prefersOpaque = reduceTransparency
	}

	private func play() {
		// Explicit Play in normal mode retires the preview tip. Stops driven by
		// Reduce Motion, scene changes, or view teardown never invalidate, and
		// review/scan/browser-only modes never mutate tip history.
		if !AppServices.isUIReview {
			panelTip.invalidate(reason: .actionPerformed)
		}
		playback?.cancel()
		let animateExpansion = !reduceMotion
		isPlaying = true
		model.isExpanded = !animateExpansion
		selectedPhase = .locked
		model.phase = .locked
		playback = Task { @MainActor in
			do {
				if animateExpansion {
					try await Task.sleep(for: .milliseconds(260))
				}
				model.isExpanded = true
				let sequence: [PreviewPhase] = [.locked, .scanning, .challenge, .success, .pending, .unlocked]
				for phase in sequence {
					selectedPhase = phase
					model.phase = phase.phase
					try await Task.sleep(for: .seconds(phase == .challenge ? 2 : 1))
				}
				if animateExpansion {
					model.isExpanded = false
					try await Task.sleep(for: .milliseconds(400))
				}
			} catch { return }
			isPlaying = false
			playback = nil
			selectedPhase = .scanning
			model.phase = .scanning
			model.isExpanded = true
		}
	}

	private func stop() {
		playback?.cancel()
		playback = nil
		isPlaying = false
		model.isExpanded = true
	}
}
