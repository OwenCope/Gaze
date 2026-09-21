import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum PreviewPhase: String, CaseIterable, Identifiable {
	case locked = "Locked"
	case scanning = "Scanning"
	case challenge = "Movement"
	case rejected = "Rejected"
	case verified = "Verified"
	case unlocked = "Unlocked"
	var id: String { rawValue }
	var detail: String {
		switch self {
		case .locked: "Waiting at the notch."
		case .scanning: "Looking for a face."
		case .challenge: "Demonstrating the requested movement."
		case .rejected: "Showing a rejected attempt."
		case .verified: "Showing a verified face."
		case .unlocked: "Returning to the resting bar."
		}
	}

	var phase: NotchCapsuleModel.Phase {
		switch self {
		case .locked: .locked
		case .scanning: .scanning
		case .challenge:
			.challenge(prompt: "Turn your head left", symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
		case .rejected: .spoofRejected
		case .verified: .success
		case .unlocked: .unlocked
		}
	}
}

enum PreviewMovement: String, CaseIterable, Identifiable {
	case turnLeft = "Turn left", turnRight = "Turn right", nod = "Nod", blink = "Blink", openMouth = "Open mouth"
	var id: String { rawValue }
	var phase: NotchCapsuleModel.Phase {
		switch self {
		case .turnLeft: .challenge(prompt: "Turn your head left", symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
		case .turnRight: .challenge(prompt: "Turn your head right", symbol: "arrowshape.right.fill", hintX: 1, hintY: 0, pulses: false)
		case .nod: .challenge(prompt: "Nod your head", symbol: "arrowshape.down.fill", hintX: 0, hintY: 1, pulses: false)
		case .blink: .challenge(prompt: "Blink", symbol: "eye.fill", hintX: 0, hintY: 0, pulses: true)
		case .openMouth: .challenge(prompt: "Open your mouth", symbol: "mouth.fill", hintX: 0, hintY: 0, pulses: true)
		}
	}
}

@MainActor
@Observable
final class RecordingPreview {
	let model = NotchCapsuleModel()
	var selectedPhase = PreviewPhase.scanning {
		didSet { model.phase = selectedPhase == .challenge ? movement.phase : selectedPhase.phase }
	}
	var movement = PreviewMovement.turnLeft {
		didSet {
			if selectedPhase == .challenge { model.phase = movement.phase }
		}
	}
	var controlsVisible = true
	var loops = false
	var playing = false
	var reducedMotion = false
	var duration: Double = 1.5
	var widthAdjust: Double = 0
	var heightAdjust: Double = 0
	var backdrop = "System"
	var wallpaper: NSImage?
	var wallpaperName: String?
	var appearance = "System"
	var imageError: String?
	private var playback: Task<Void, Never>?

	init() {
		model.isExpanded = true
		model.phase = selectedPhase.phase
	}

	var background: Color {
		switch backdrop {
		case "White": .white
		case "Black": .black
		case "Green screen": Color(red: 0, green: 1, blue: 0)
		default: Color(nsColor: .underPageBackgroundColor)
		}
	}

	var colorScheme: ColorScheme? {
		switch appearance {
		case "Light": .light
		case "Dark": .dark
		default: nil
		}
	}

	func togglePlayback() {
		if playing { stop() } else { play() }
	}

	func select(_ phase: PreviewPhase) {
		stop()
		selectedPhase = phase
	}

	func play() {
		stop()
		playing = true
		playback = Task { @MainActor [weak self] in
			guard let self else { return }
			repeat {
				for phase in PreviewPhase.allCases {
					guard !Task.isCancelled else { return }
					selectedPhase = phase
					do { try await Task.sleep(for: .seconds(phase == .challenge ? max(3, duration) : duration)) }
					catch { return }
				}
			} while loops && !Task.isCancelled
			playing = false
			playback = nil
		}
	}

	func stop() {
		playback?.cancel()
		playback = nil
		playing = false
	}

	func chooseWallpaper() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.image]
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Choose Background"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		guard let image = NSImage(contentsOf: url) else {
			imageError = "This image could not be opened. Choose another image."
			return
		}
		wallpaper = image
		wallpaperName = url.lastPathComponent
	}
}

@main
struct GazePreviewApp: App {
	@State private var preview = RecordingPreview()

	var body: some Scene {
		Window("Gaze Preview", id: "gaze-preview") {
			RecordingPreviewView(preview: preview)
				.preferredColorScheme(preview.colorScheme)
				.environment(\.notchReduceMotion, preview.reducedMotion)
				.onAppear {
					NSApplication.shared.setActivationPolicy(.regular)
					NSApplication.shared.activate(ignoringOtherApps: true)
				}
		}
		.defaultSize(width: 1040, height: 700)
		.windowResizability(.contentMinSize)
		.commands {
			CommandMenu("Studies") {
				StudiesWindowButton().keyboardShortcut("a", modifiers: [.command, .shift])
				RecognitionLayoutButton().keyboardShortcut("r", modifiers: [.command, .shift])
			}
			CommandMenu("Recording") {
				Button(preview.playing ? "Stop Playback" : "Play Sequence") { preview.togglePlayback() }
					.keyboardShortcut(.space, modifiers: [])
				Toggle("Loop Playback", isOn: $preview.loops)
				Divider()
				Toggle("Show Controls", isOn: $preview.controlsVisible)
					.keyboardShortcut("h", modifiers: [.command, .shift])
				Picker("Phase", selection: Binding(
					get: { preview.selectedPhase }, set: { preview.select($0) }
				)) {
					ForEach(PreviewPhase.allCases) { Text($0.rawValue).tag($0) }
				}
				Divider()
				Button("Choose Background…") { preview.chooseWallpaper() }
				Picker("Appearance", selection: $preview.appearance) {
					ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) }
				}
			}
		}
		Window("Animation Studies", id: "animation-studies") {
			AnimationStudiesView()
		}
		.defaultSize(width: 1080, height: 820)
		.windowResizability(.contentMinSize)
		Window("Recognition Layout — Simulated", id: "recognition-layout") {
			RecognitionLayoutPreview()
		}
		.windowResizability(.contentSize)
	}
}

struct RecordingPreviewView: View {
	@Bindable var preview: RecordingPreview
	@State private var fitExpanded = false

	private var isOnEar: Bool { preview.model.glyphPlacement == .ear }

	var body: some View {
		HStack(spacing: 0) {
			VStack(spacing: 0) {
				stage
				if preview.controlsVisible { playbackControls }
			}
			.frame(minWidth: 590, maxWidth: .infinity, maxHeight: .infinity)
			if preview.controlsVisible {
				Divider()
				inspector
					.frame(width: 310)
			}
		}
		.frame(minWidth: 920, minHeight: 620)
		.toolbar {
			ToolbarItem(placement: .primaryAction) { StudiesWindowButton() }
			ToolbarItem(placement: .principal) {
				Label("Animation Preview", systemImage: "play.rectangle")
					.font(.headline)
			}
			ToolbarItem(placement: .primaryAction) {
				Button {
					preview.controlsVisible.toggle()
				} label: {
					Label(preview.controlsVisible ? "Hide Controls" : "Show Controls",
						systemImage: "sidebar.right")
				}
				.help(preview.controlsVisible ? "Hide controls (⇧⌘H)" : "Show controls (⇧⌘H)")
			}
		}
		.onChange(of: preview.model.shape, initial: true) { _, shape in
			if shape == .island { preview.model.glyphPlacement = .centred }
		}
		.onExitCommand { preview.controlsVisible = true }
		.onDisappear { preview.stop() }
		.alert("Couldn’t open image", isPresented: Binding(
			get: { preview.imageError != nil }, set: { if !$0 { preview.imageError = nil } }
		)) {
			Button("OK") { preview.imageError = nil }
		} message: {
			Text(preview.imageError ?? "")
		}
	}

	private var stage: some View {
		VStack(alignment: .leading, spacing: 14) {
			if preview.controlsVisible {
				HStack {
					Text("Preview").font(.headline)
					Spacer()
					Label("Camera off", systemImage: "video.slash")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}
			NotchPreviewCanvas(model: preview.model,
				widthAdjust: preview.widthAdjust, heightAdjust: preview.heightAdjust,
				wallpaper: preview.wallpaper, background: preview.background)
				.clipShape(.rect(cornerRadius: preview.controlsVisible ? 12 : 0))
				.overlay {
					if preview.controlsVisible {
						RoundedRectangle(cornerRadius: 12)
							.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
							.allowsHitTesting(false)
					}
				}
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("Simulated notch: \(preview.selectedPhase.rawValue)")
			if preview.controlsVisible {
				Text("Preview only. Your Gaze settings stay unchanged.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
		.padding(preview.controlsVisible ? 24 : 0)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var playbackControls: some View {
		VStack(alignment: .leading, spacing: 16) {
			Picker("Animation phase", selection: Binding(
				get: { preview.selectedPhase }, set: { preview.select($0) }
			)) {
				ForEach(PreviewPhase.allCases) { phase in
					Text(phase.rawValue).tag(phase)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			HStack(spacing: 14) {
				Button {
					preview.togglePlayback()
				} label: {
					Label(preview.playing ? "Stop" : "Play sequence",
						systemImage: preview.playing ? "stop.fill" : "play.fill")
						.frame(width: 116)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.help("Play or stop the sequence (Space)")
				VStack(alignment: .leading, spacing: 3) {
					Text(preview.selectedPhase.rawValue).font(.callout.weight(.medium))
					Text(preview.selectedPhase.detail).font(.caption).foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				Text("Space to play").font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 24)
		.padding(.bottom, 24)
	}

	private var inspector: some View {
		@Bindable var model = preview.model

		return VStack(alignment: .leading, spacing: 0) {
			Text("Controls")
				.font(.headline)
				.padding(.horizontal, 20)
				.padding(.top, 24)
			Form {
				Section("Notch") {
					VStack(alignment: .leading, spacing: 8) {
						Text("Shape").font(.callout)
						Picker("Shape", selection: $model.shape) {
							ForEach(Preferences.PanelShape.allCases, id: \.self) { Text($0.title).tag($0) }
						}
						.pickerStyle(.segmented)
						.labelsHidden()
					}
					if model.shape == .attached {
						Picker("Mark", selection: $model.glyphPlacement) {
							ForEach(Preferences.GlyphPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
						}
					}
					if !isOnEar {
						Picker("Style", selection: $model.style) {
							ForEach(Preferences.NotchStyle.allCases, id: \.self) { Text($0.title).tag($0) }
						}
						if model.style == .semiLiquidGlass {
							valueSlider("Transparency", value: $model.transparency, range: 0...1,
								valueLabel: "\(Int((model.transparency * 100).rounded()))%")
						}
						if model.style != .normal {
							Toggle("Boost contrast", isOn: $model.prefersOpaque)
								.help("Darken the notch material over a light background")
						}
					}
					Toggle("Show captions", isOn: $model.showsCaptions)
						.help("Display only: hides the caption words and their symbols, never the face mark.")
					DisclosureGroup("Size adjustments", isExpanded: $fitExpanded) {
						if !isOnEar {
							valueSlider("Height", value: $preview.heightAdjust, range: -20...20,
								valueLabel: "\(Int(preview.heightAdjust)) pt")
						}
						valueSlider("Width", value: $preview.widthAdjust, range: -40...40,
							valueLabel: "\(Int(preview.widthAdjust)) pt")
						Button("Reset size") { preview.widthAdjust = 0; preview.heightAdjust = 0 }
							.disabled(preview.widthAdjust == 0 && preview.heightAdjust == 0)
					}
				}
				Section("Playback") {
					Toggle("Reduce motion", isOn: $preview.reducedMotion)
						.help("Preview the static, written guidance. System Reduce Motion is always respected.")
					if preview.selectedPhase == .challenge {
						Picker("Movement", selection: $preview.movement) {
							ForEach(PreviewMovement.allCases) { Text($0.rawValue).tag($0) }
						}
					}
					Toggle("Loop sequence", isOn: $preview.loops)
					valueSlider("Time per phase", value: $preview.duration, range: 0.5...4, step: 0.5,
						valueLabel: String(format: "%.1f s", preview.duration))
				}
				Section("Canvas") {
					if preview.wallpaper == nil {
						Picker("Background", selection: $preview.backdrop) {
							ForEach(["System", "White", "Black", "Green screen"], id: \.self) { Text($0) }
						}
					} else {
						HStack(spacing: 8) {
							Label(preview.wallpaperName ?? "Custom image", systemImage: "photo")
								.lineLimit(1)
								.truncationMode(.middle)
								.help(preview.wallpaperName ?? "Custom image")
							Spacer(minLength: 0)
							Button("Remove background image", systemImage: "xmark.circle.fill") {
								preview.wallpaper = nil
								preview.wallpaperName = nil
							}
							.labelStyle(.iconOnly)
							.buttonStyle(.borderless)
						}
					}
					Button(preview.wallpaper == nil ? "Choose image…" : "Replace image…") {
						preview.chooseWallpaper()
					}
					Picker("Appearance", selection: $preview.appearance) {
						ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) }
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
		step: Double = 0.01, valueLabel: String) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(title)
				Spacer()
				Text(valueLabel)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
			.font(.callout)
			Slider(value: value, in: range, step: step) { Text(title) }
				.labelsHidden()
				.accessibilityValue(valueLabel)
		}
	}
}
