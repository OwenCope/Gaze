import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers
import os

struct WallpaperLoadGate {
	struct Request: Equatable, Sendable {
		let url: URL
		let generation: UInt64
	}

	private var generation: UInt64 = 0
	private var loadedURL: URL?
	private(set) var pendingRequest: Request?
	private var retryAfter: [URL: Date] = [:]

	mutating func request(for url: URL, now: Date) -> Request? {
		guard pendingRequest?.url != url else { return nil }
		// Returning to the cached image must invalidate work for a different desktop.
		pendingRequest = nil
		guard loadedURL != url else { return nil }
		retryAfter = retryAfter.filter { $0.value > now }
		guard retryAfter[url] == nil else { return nil }
		generation &+= 1
		let request = Request(url: url, generation: generation)
		pendingRequest = request
		return request
	}

	mutating func complete(_ request: Request, succeeded: Bool, now: Date) -> Bool {
		guard pendingRequest == request else { return false }
		pendingRequest = nil
		if succeeded {
			loadedURL = request.url
			retryAfter.removeValue(forKey: request.url)
		} else {
			loadedURL = nil
			retryAfter[request.url] = now.addingTimeInterval(10)
		}
		return true
	}

	mutating func reset() {
		generation &+= 1
		loadedURL = nil
		pendingRequest = nil
		retryAfter.removeAll()
	}
}

/// The desktop picture, blurred, as a background for Gaze's own windows.
///
/// Settings sitting on the user's own wallpaper is what makes a window feel like part of
/// the machine rather than a rectangle dropped on top of it — it is why the Siri panel and
/// Notification Centre read as macOS. A fixed grey behind glass is glass over nothing.
///
/// Blurred with Core Image at a reduced size rather than SwiftUI's `.blur`. Three reasons,
/// all of which showed up in practice:
///
///   - a 6K wallpaper blurred live is a 6K image blurred on every frame the window draws;
///     downsampling to window size first makes it a rounding error, and a blur of a
///     downsample is visually identical to a downsample of a blur.
///   - `.blur` fades out at the edges of its own bounds, so the corners of the window go
///     pale. `CIAffineClamp` extends the image first, which is the fix.
///   - the result is cached, so switching panes does not re-blur anything.
@Observable
@MainActor
final class DesktopWallpaper {

	static let shared = DesktopWallpaper()

	private(set) var image: NSImage?

	private let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Wallpaper")
	@ObservationIgnored private var loadGate = WallpaperLoadGate()
	@ObservationIgnored private var loadTask: Task<Void, Never>?
	@ObservationIgnored private var reportedUnresolvedURL = false

	private init() {
		load()

		// The desktop picture changes when the user picks a new one, and — with per-space
		// wallpapers — when they switch spaces. Neither posts a "wallpaper changed"
		// notification, so this watches the two things that do happen alongside it.
		let center = NSWorkspace.shared.notificationCenter
		center.addObserver(
			forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.load() }
		}
		NotificationCenter.default.addObserver(
			forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.load() }
		}

		// And a slow poll, because neither of those fires for the common case: changing
		// the desktop picture in System Settings while a Gaze window is already open and
		// frontmost. Two seconds is imperceptible as a delay and costs a string compare —
		// `load()` returns immediately unless the URL actually changed.
		Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(2))
				guard let self else { return }
				self.load()
			}
		}
	}

	/// Reload if the desktop picture has actually changed.
	func load() {
		guard let url = Self.currentWallpaperURL() else {
			loadTask?.cancel()
			loadTask = nil
			loadGate.reset()
			image = nil
			if !reportedUnresolvedURL {
				logger.notice("Could not resolve the desktop picture; keeping the plain ground.")
				reportedUnresolvedURL = true
			}
			return
		}
		reportedUnresolvedURL = false
		guard let request = loadGate.request(for: url, now: .now) else {
			if loadGate.pendingRequest == nil {
				loadTask?.cancel()
				loadTask = nil
			}
			return
		}

		loadTask?.cancel()
		loadTask = Task(priority: .utility) { [weak self] in
			let data = await Self.blurred(contentsOf: request.url)
			guard !Task.isCancelled, let self,
				self.loadGate.pendingRequest == request else { return }
			let blurred = data.flatMap { NSImage(data: $0) }
			guard self.loadGate.complete(request, succeeded: blurred != nil, now: .now)
			else { return }
			self.image = blurred
			self.loadTask = nil
			if blurred == nil {
				self.logger.notice("Could not decode the desktop picture; keeping the plain ground.")
			}
		}
	}

	// MARK: - Finding the wallpaper

	/// Where the desktop picture actually is.
	///
	/// `NSWorkspace.desktopImageURL` is the obvious answer and it is wrong for a large and
	/// growing share of Macs. It only knows about *image* wallpapers; set a dynamic aerial —
	/// which is what macOS offers first — and it quietly hands back Apple's stock default
	/// instead of saying it does not know. That is how this shipped showing a Golden Gate
	/// photograph to someone whose desktop was a completely different picture: not a bug in
	/// the drawing, a wrong answer accepted as a right one.
	///
	/// So the aerial case is resolved first, from the wallpaper store, and the image API is
	/// only trusted when the store says the wallpaper really is an image.
	private static func currentWallpaperURL() -> URL? {
		if let aerial = aerialThumbnailURL() { return aerial }
		guard let screen = NSScreen.main ?? NSScreen.screens.first
		else { return nil }
		return NSWorkspace.shared.desktopImageURL(for: screen)
	}

	/// The still that macOS keeps for the aerial currently set as the desktop.
	///
	/// It is small — a couple of hundred pixels — which would be useless for anything but
	/// this. Everything here is blurred to within an inch of its life before it is drawn, so
	/// the source resolution stops mattering: a heavy Gaussian of a 214px still and of a 6K
	/// frame are the same picture. The alternative was capturing the wallpaper window, which
	/// means asking for Screen Recording, and that is an outrageous thing to prompt for in
	/// order to draw a background.
	// Only ever touched from `load()`, which runs on the main actor; the `nonisolated`
	// below is for the caller's sake, not for background use.
	nonisolated(unsafe) private static var lastIndexMtime: Date?
	nonisolated(unsafe) private static var lastAerialResult: URL?

	nonisolated private static func aerialThumbnailURL() -> URL? {
		let support = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
			.first?.appendingPathComponent("Application Support/com.apple.wallpaper")
		guard let support else { return nil }

		let store = support.appendingPathComponent("Store/Index.plist")
		// The 2s poll re-reads this plist from disk; skip the parse when it is unchanged.
		let mtime = (try? FileManager.default.attributesOfItem(atPath: store.path))?[
			.modificationDate] as? Date
		if let mtime, mtime == lastIndexMtime {
			if let cached = lastAerialResult,
				FileManager.default.fileExists(atPath: cached.path)
			{
				return cached
			}
			if lastAerialResult == nil { return nil }
		}
		guard let data = try? Data(contentsOf: store),
			let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
				as? [String: Any]
		else { return nil }

		// Per-display first, then the all-displays entry. A Mac with one screen writes both,
		// and they can disagree after an external monitor has been plugged in once.
		var choices: [[String: Any]] = []
		if let displays = root["Displays"] as? [String: Any] {
			for (_, value) in displays {
				if let desktop = (value as? [String: Any])?["Desktop"] as? [String: Any],
					let content = desktop["Content"] as? [String: Any],
					let list = content["Choices"] as? [[String: Any]]
				{
					choices += list
				}
			}
		}
		if let all = root["AllSpacesAndDisplays"] as? [String: Any],
			let idle = all["Idle"] as? [String: Any],
			let content = idle["Content"] as? [String: Any],
			let list = content["Choices"] as? [[String: Any]]
		{
			choices += list
		}

		for choice in choices {
			guard choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
				let configuration = choice["Configuration"] as? Data,
				let config = try? PropertyListSerialization.propertyList(
					from: configuration, format: nil) as? [String: Any],
				let assetID = config["assetID"] as? String
			else { continue }

			let thumbnail = support
				.appendingPathComponent("aerials/thumbnails")
				.appendingPathComponent("\(assetID).png")
			if FileManager.default.fileExists(atPath: thumbnail.path) {
				lastIndexMtime = mtime
				lastAerialResult = thumbnail
				return thumbnail
			}
		}
		lastIndexMtime = mtime
		lastAerialResult = nil
		return nil
	}

	// MARK: - Blur

	/// Loads, downsamples and blurs. Returns nil for anything that isn't a readable image.
	///
	/// Not every desktop picture is a file this can open: a Sonoma-and-later dynamic
	/// wallpaper is a `.madesktop` bundle, and the aerials are video. `CIImage` simply
	/// fails on those, which is the right outcome — the caller keeps its flat ground rather
	/// than showing something wrong.
	@concurrent private static func blurred(contentsOf url: URL) async -> Data? {
		guard !Task.isCancelled, let source = CIImage(contentsOf: url),
			!Task.isCancelled, !source.extent.isEmpty, !source.extent.isInfinite
		else { return nil }

		// Wide enough to stay sharp behind a resized window, small enough that the blur is
		// cheap. The blur radius is scaled with it so the result looks the same whatever
		// the original resolution was — a fixed radius on a 6K image is a faint haze and on
		// a 1080p one is soup.
		// Scaled *to* a target rather than only down to it: an aerial thumbnail is a couple
		// of hundred pixels wide and has to come up, a desktop photograph is 6K and has to
		// go down. Both end at the same width, which is what lets one blur radius suit both.
		let targetWidth: CGFloat = 1400
		let scale = targetWidth / source.extent.width
		let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

		let clamp = CIFilter.affineClamp()
		clamp.inputImage = scaled
		clamp.transform = .identity

		let blur = CIFilter.gaussianBlur()
		blur.inputImage = clamp.outputImage
		blur.radius = 34

		// The colour stays.
		//
		// This was desaturated to 0.35 to stop Liquid Glass controls refracting the
		// wallpaper into cyan and yellow fringes — a real effect, and the fix was aimed at
		// the wrong window. The fringing was in *Settings*, and Settings does not draw this
		// at all any more: it is `.behindWindow` glass over the actual desktop, so nothing
		// here could ever have changed it. The only thing the desaturation reached was the
		// setup flow, where it turned a wallpaper already sitting under an 0.80 scrim into
		// a featureless grey smear — the exact synthetic-gradient look this backdrop exists
		// to avoid. A blurred photograph of the user's own desktop is the one thing on that
		// screen that could not have been generated.
		guard !Task.isCancelled,
			let output = blur.outputImage?.cropped(to: scaled.extent) else { return nil }
		let context = CIContext(options: [.useSoftwareRenderer: false])
		guard !Task.isCancelled,
			let cgImage = context.createCGImage(output, from: scaled.extent)
		else { return nil }

		guard !Task.isCancelled else { return nil }
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(
			data, UTType.png.identifier as CFString, 1, nil
		) else { return nil }
		CGImageDestinationAddImage(destination, cgImage, nil)
		guard !Task.isCancelled, CGImageDestinationFinalize(destination), !Task.isCancelled
		else { return nil }
		return Data(referencing: data)
	}
}

/// The wallpaper layer, with the scrim that keeps text on it readable.
///
/// The scrim is the whole reason this is a view rather than an image. A blurred photograph
/// is still a photograph: it has bright regions, and white text over the bright part of a
/// wallpaper is unreadable however pretty the rest looks. So the picture is dimmed to a
/// level where the *lightest* wallpaper still clears the contrast the labels need, and the
/// window's own glass sits on top of that.
///
/// It is deliberately heavier in dark mode than light. Dark mode's labels are white, and
/// white-on-bright is the failing case; light mode's are near-black, which survives far
/// more of the picture showing through.
struct WallpaperBackdrop: View {

	/// How dark the ground is. Settings sits behind glass panels and can afford to show
	/// more of the picture; setup is white type directly on the ground with nothing between,
	/// so it needs the wallpaper pushed much further back.
	enum Style {
		case settings
		case setup
	}

	var style: Style = .settings

	@Environment(\.colorScheme) private var colorScheme
	@State private var wallpaper = DesktopWallpaper.shared

	var body: some View {
		ZStack {
			// Under everything, so a wallpaper that fails to load leaves a sane window
			// rather than a transparent one.
			(style == .setup ? Color.black : Theme.background)

			if let image = wallpaper.image {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.transition(.opacity)
			}

			Color.black.opacity(darkness)
			if style == .settings && colorScheme != .dark {
				Color.white.opacity(0.55)
			}
		}
		.animation(.easeOut(duration: 0.35), value: wallpaper.image != nil)
		.clipped()
		.ignoresSafeArea()
	}

	/// Enough that the lightest wallpaper still clears the contrast the labels need.
	///
	/// Setup is dark whatever the system appearance — it is a dark-only flow — so it does
	/// not branch on colour scheme, and it is heavier than Settings because there is no
	/// glass panel between the type and the picture.
	private var darkness: Double {
		switch style {
		case .setup: return 0.80
		// Settings was 0.62, chosen when this was the only thing between the wallpaper and
		// the type. It no longer is: the glass sheet above carries a material and its own
		// gradient, so 0.62 here was the third scrim on the same picture. The groups are
		// filled surfaces with their own contrast, and the loose type outside them sits on
		// the darkest part of the fall.
		case .settings: return colorScheme == .dark ? 0.46 : 0.10
		}
	}
}
