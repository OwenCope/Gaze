import AppKit
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What one look at the lock screen came to.
struct UnlockAttempt: Codable, Identifiable {
	enum Result: String, Codable {
		case unlocked
		case notRecognised
		case unknownFace
		case spoofRejected
		case openedAnotherWay
		case leftLocked
		/// Old logs only. Reads as openedAnotherWay in the UI.
		case closedWithoutUnlocking
	}

	enum Reason: String, Codable {
		case tooDark
		case tooFar
		case faceTurned
		case noFace
		case differentPerson
		case movementTimedOut
		case photoOrScreen
	}

	var id: UUID
	var date: Date
	var result: Result
	/// Why a look failed. Optional so older logs still decode.
	var reason: Reason?
	/// Seconds from wake/lock to unlock, for successes.
	var duration: TimeInterval?
	/// Photo filename inside the attempts directory, when one was kept.
	var photoFile: String?
	/// Where the time went on a successful unlock, in seconds: camera start, first
	/// recognition, the steady hold and movement, then macOS accepting the password.
	/// Optional so older logs still decode.
	var steps: Steps?

	struct Steps: Codable, Equatable {
		var camera: TimeInterval? = nil
		var recognise: TimeInterval? = nil
		var check: TimeInterval? = nil
		var macOS: TimeInterval? = nil
		/// Seconds from the movement prompt appearing to it being completed.
		var movement: TimeInterval? = nil
		/// The prompt text shown for the movement challenge.
		var movementPrompt: String? = nil
		/// Per-pass Follow-the-light scores, oldest first. Optional so older logs still decode.
		var lookPasses: [String]? = nil
	}
}

/// The recent history behind the Settings “Unlock Attempts” section.
///
/// Photos stay on this Mac: they are written with complete file protection next
/// to the log and are never uploaded anywhere.
@Observable
@MainActor
final class UnlockAttemptLog {

	static let shared = UnlockAttemptLog()

	/// When a look keeps its photo. Off by default.
	enum PhotoPolicy: String, CaseIterable {
		case off
		case whenNotGaze
		case always

		var title: String {
			switch self {
			case .off: return "Off"
			case .whenNotGaze: return "When Gaze doesn't unlock"
			case .always: return "Every time"
			}
		}
	}

	private static let photoPolicyKey = "attemptPhotoPolicy"
	private static let capturesPhotosKey = "captureAttemptPhotos"
	private static let maxAttempts = 50
	private static let retentionDays = 30
	private static let photoLongSide: CGFloat = 800
	private static let photoQuality = 0.8

	private(set) var attempts: [UnlockAttempt] = []
	// Not observed: filling it while a row draws must not make the list draw again.
	@ObservationIgnored private var photoCache: [String: NSImage] = [:]

	/// When a look keeps its photo. Off until the person asks for it.
	var photoPolicy: PhotoPolicy {
		didSet { UserDefaults.standard.set(photoPolicy.rawValue, forKey: Self.photoPolicyKey) }
	}

	/// Whether any look keeps a photo.
	var capturesPhotos: Bool { photoPolicy != .off }

	private init() {
		if let raw = UserDefaults.standard.string(forKey: Self.photoPolicyKey),
			let saved = PhotoPolicy(rawValue: raw) {
			photoPolicy = saved
		} else if UserDefaults.standard.bool(forKey: Self.capturesPhotosKey) {
			photoPolicy = .whenNotGaze
		} else {
			photoPolicy = .off
		}
		// A tiny JSON read, once, so the section never flashes empty on launch.
		// Everything heavier — photos, writes, pruning — happens off the main actor.
		let loaded = (try? Data(contentsOf: Self.listURL()))
			.flatMap { try? JSONDecoder().decode([UnlockAttempt].self, from: $0) } ?? []
		let cutoff = Date().addingTimeInterval(TimeInterval(-Self.retentionDays * 24 * 60 * 60))
		let kept = loaded.filter { $0.date >= cutoff }.prefix(Self.maxAttempts)
		attempts = Array(kept)
		let stale = loaded.filter { $0.date < cutoff }
		if !stale.isEmpty {
			let files = stale.compactMap(\.photoFile)
			Task.detached(priority: .utility) { Self.deletePhotoFiles(files) }
		}
	}

	/// Records one attempt. Never throws, never blocks: the photo conversion and
	/// every write happen in a detached task. Safe to call on the unlock path.
	func record(_ result: UnlockAttempt.Result, duration: TimeInterval? = nil, steps: UnlockAttempt.Steps? = nil,
		photo: CVPixelBuffer? = nil, reason: UnlockAttempt.Reason? = nil) {
		let id = UUID()
		let keepsPhoto = photo != nil
			&& (photoPolicy == .always || (photoPolicy == .whenNotGaze && result != .unlocked))
		let attempt = UnlockAttempt(id: id, date: Date(), result: result, reason: reason, duration: duration,
			photoFile: keepsPhoto ? "\(id.uuidString).jpg" : nil, steps: steps)
		attempts.insert(attempt, at: 0)
		var trimmedFiles: [String] = []
		while attempts.count > Self.maxAttempts {
			let removed = attempts.removeLast()
			if let file = removed.photoFile {
				trimmedFiles.append(file)
				photoCache.removeValue(forKey: file)
			}
		}
		let snapshot = attempts
		// Retained by the log, so the camera cannot free the frame underneath the
		// background conversion.
		let frame = photo.map(RetainedFrame.init)
		Task.detached(priority: .utility) {
			if let frame, let file = attempt.photoFile,
				let data = Self.jpegData(from: frame.buffer) {
				Self.writeProtected(data, to: Self.directory().appendingPathComponent(file))
				await MainActor.run { UnlockAttemptLog.shared.photoRevision += 1 }
			}
			Self.deletePhotoFiles(trimmedFiles)
			Self.save(snapshot)
		}
	}

	func deleteAll() {
		let files = attempts.compactMap(\.photoFile)
		attempts = []
		photoCache = [:]
		Task.detached(priority: .utility) {
			Self.deletePhotoFiles(files)
			Self.save([])
		}
	}

	/// Safe to call from a view body: after the first call per photo it is a
	/// dictionary lookup. `NSImage` already returns nil for a file that is not
	/// there, so no existence check is needed.
	func photo(for attempt: UnlockAttempt) -> NSImage? {
		// Read so a row redraws once its photo lands on disk.
		_ = photoRevision
		guard let file = attempt.photoFile else { return nil }
		if let cached = photoCache[file] { return cached }
		// Only hits are cached. The photo is written in the background, so a row drawn
		// right after the attempt found no file yet; caching that miss hid the photo for good.
		guard let loaded = NSImage(contentsOf: Self.directory().appendingPathComponent(file)) else { return nil }
		photoCache[file] = loaded
		return loaded
	}

	/// Bumped when a photo finishes writing.
	private(set) var photoRevision = 0

	// MARK: - Files

	/// A frame handed to the background writer.
	private struct RetainedFrame: @unchecked Sendable {
		let buffer: CVPixelBuffer

		init(_ buffer: CVPixelBuffer) {
			self.buffer = buffer
		}
	}

	private nonisolated static func directory() -> URL {
		let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let dir = support.appendingPathComponent("Gaze/Attempts", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private nonisolated static func listURL() -> URL {
		directory().appendingPathComponent("attempts.json")
	}

	private nonisolated static func save(_ attempts: [UnlockAttempt]) {
		guard let data = try? JSONEncoder().encode(attempts) else { return }
		writeProtected(data, to: listURL())
	}

	private nonisolated static func writeProtected(_ data: Data, to url: URL) {
		try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true)
		try? data.write(to: url, options: [.atomic, .completeFileProtection])
	}

	private nonisolated static func deletePhotoFiles(_ files: [String]) {
		for file in files {
			try? FileManager.default.removeItem(at: directory().appendingPathComponent(file))
		}
	}

	/// JPEG at 0.8 quality, scaled so the long side is at most 800 px.
	private nonisolated static func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
		var image = CIImage(cvPixelBuffer: pixelBuffer)
		let longSide = max(image.extent.width, image.extent.height)
		if longSide > photoLongSide {
			let scale = photoLongSide / longSide
			image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
		}
		let context = CIContext()
		guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
		else { return nil }
		CGImageDestinationAddImage(destination, cgImage,
			[kCGImageDestinationLossyCompressionQuality as String: photoQuality] as CFDictionary)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return data as Data
	}
}
