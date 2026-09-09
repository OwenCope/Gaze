import AppKit
import SwiftUI

/// The window behind `--capture-dataset`.
///
/// A recording tool, not a feature: it exists to make an hour of dataset
/// collection bearable and it is never presented to anyone who did not ask for
/// it on the command line.
struct DatasetCaptureView: View {

	@State private var camera = CameraController()
	@State private var capture = DatasetCapture()

	var body: some View {
		VStack(spacing: 16) {
			ZStack {
				CameraPreview(controller: camera)
					.frame(width: 320, height: 240)
					.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

				// A frame is only written when a face is found, so say when one is not
				// — otherwise a session quietly records nothing and nobody notices
				// until it is time to train.
				if camera.faceMissing {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(.black.opacity(0.55))
						.frame(width: 320, height: 240)
						.overlay {
							Text("No face in frame")
								.font(.callout.weight(.medium))
								.foregroundStyle(.white)
						}
				}
			}

			Picker("Recording", selection: $capture.label) {
				ForEach(DatasetCapture.Label.allCases) { label in
					Text(label.title).tag(label)
				}
			}
			.pickerStyle(.segmented)
			.disabled(capture.isRecording)

			TextField("What is in front of the camera — \"iPhone 14 screen\", \"printed A4\"", text: $capture.deviceNote)
				.textFieldStyle(.roundedBorder)
				.disabled(capture.isRecording)

			HStack {
				Button(capture.isRecording ? "Stop" : "Record") {
					capture.isRecording ? capture.stop() : capture.start()
				}
				.keyboardShortcut(.space, modifiers: [])
				.buttonStyle(.borderedProminent)
				.tint(capture.isRecording ? .red : .accentColor)

				Spacer()

				Text("\(capture.written) frames")
					.font(.callout.monospacedDigit())
					.foregroundStyle(.secondary)

				Button("Show in Finder") {
					NSWorkspace.shared.activateFileViewerSelecting([capture.root])
				}
			}

			// The one thing that decides whether the model works, said where it will
			// be read. A set of one person and one phone teaches "this is Owen's
			// face", not "this is a screen", and it scores beautifully right up until
			// somebody else tries it.
			Text("Record several people and several attack devices. Keep one device out of training entirely and test only on that.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(18)
		.frame(width: 380)
		.task { await camera.start() }
		.onDisappear { camera.stop() }
		.onChange(of: camera.frameID) { _, _ in
			capture.consume(camera.faceMissing ? nil : camera.sample)
		}
	}
}
