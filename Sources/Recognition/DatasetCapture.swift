import AVFoundation
import CoreImage
import Foundation
import os

/// Records labelled crops for training an anti-spoof model.
///
/// Launch with `--capture-dataset`. Nothing here is reachable from the shipping
/// interface: it exists so the dataset can be produced by *this* pipeline rather
/// than by a Python script pointed at some video files. Train on crops that were
/// framed, scaled and colour-converted differently from the ones the app will
/// feed the model at unlock time and the score is meaningless — a difference of
/// framing is a difference the model will happily learn instead of the one you
/// wanted.
///
/// Written straight to disk as JPEGs, one directory per session, with a manifest
/// naming what was in front of the camera. The label is recorded by the person
/// holding the phone; there is no way to infer it later.
@MainActor
final class DatasetCapture {

	enum Label: String, CaseIterable, Identifiable {
		/// A person, actually present.
		case live
		/// A photograph or video of a person, held up to the camera.
		case spoof

		var id: String { rawValue }
		var title: String { self == .live ? "Live" : "Spoof" }
	}

	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Dataset")

	/// The side of the square written to disk.
	///
	/// Larger than any model input on purpose. Downscaling later is free; the
	/// frames cannot be recaptured once everyone has gone home, and a 128px set is
	/// useless the day a model wants 224.
	private static let side = 256

	private static let context = CIContext(options: [.useSoftwareRenderer: false])

	private(set) var isRecording = false
	private(set) var written = 0
	/// What is being recorded, and on what. "iPhone 14 screen", "printed A4".
	var label: Label = .live
	var deviceNote = ""

	private var sessionDirectory: URL?
	private var manifest: URL?
	private var lastWrite = Date.distantPast

	/// Frames per second written.
	///
	/// The camera runs far faster, and consecutive frames of someone sitting still
	/// are nearly identical — thousands of them inflate the set without adding
	/// anything to learn from, and they end up split across train and test, which
	/// quietly turns the score into a lie.
	private static let interval: TimeInterval = 1.0 / 6

	var root: URL {
		URL.documentsDirectory.appending(path: "GazeDataset", directoryHint: .isDirectory)
	}

	func start() {
		guard !isRecording else { return }

		// One directory per sitting, named for when it happened and what it holds,
		// so a bad batch can be deleted without unpicking the whole set.
		// Colons are legal in a POSIX filename and a menace everywhere else — Finder
		// shows them as slashes and shell tools need them escaped.
		let stamp = ISO8601DateFormatter.string(
			from: Date(), timeZone: .current,
			formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
			.replacingOccurrences(of: ":", with: "-")
		let name = "\(label.rawValue)-\(stamp)"
		let directory = root.appending(path: name, directoryHint: .isDirectory)

		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let manifest = directory.appending(path: "session.json")
			let info: [String: String] = [
				"label": label.rawValue,
				"device": deviceNote,
				"startedAt": Date().formatted(.iso8601),
				"cropMargin": String(describing: Liveness.cropMargin),
				"side": String(Self.side),
			]
			try JSONSerialization.data(withJSONObject: info, options: .prettyPrinted)
				.write(to: manifest)
			self.manifest = manifest
			sessionDirectory = directory
			written = 0
			isRecording = true
			Self.logger.notice("Recording \(name, privacy: .public)")
		} catch {
			Self.logger.error("Couldn't start a session: \(error)")
		}
	}

	func stop() {
		isRecording = false
		sessionDirectory = nil
		manifest = nil
	}

	/// Feed every frame here; it writes at most `interval` apart.
	func consume(_ sample: FaceSample?) {
		guard isRecording, let sample, let directory = sessionDirectory else { return }
		guard Date().timeIntervalSince(lastWrite) >= Self.interval else { return }

		// The same crop the detector will use, from the same code. This is the whole
		// reason the tool lives inside the app.
		guard
			let crop = FaceAligner.contextCrop(sample, side: Self.side, margin: Liveness.cropMargin),
			let jpeg = Self.encode(crop)
		else { return }

		lastWrite = Date()
		let url = directory.appending(path: String(format: "%05d.jpg", written))
		do {
			try jpeg.write(to: url)
			written += 1
		} catch {
			Self.logger.error("Couldn't write a frame: \(error)")
		}
	}

	private static func encode(_ buffer: CVPixelBuffer) -> Data? {
		let image = CIImage(cvPixelBuffer: buffer)
		guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
		// Quality 0.95, not 1.0. The artefacts this model learns from are fine —
		// moiré, pixel grids — and heavy JPEG compression erases exactly those. The
		// last few percent of quality costs little and is the part that matters.
		return context.jpegRepresentation(of: image, colorSpace: space, options: [
			kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95,
		])
	}
}
