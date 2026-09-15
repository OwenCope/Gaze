import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI
import os

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
	private let context = CIContext(options: [.useSoftwareRenderer: false])
	/// What was loaded last, so a redundant reload can be skipped.
	private var loadedURL: URL?

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
			logger.notice("Could not resolve the desktop picture; keeping the plain ground.")
			return
		}
		guard url != loadedURL else { return }
		loadedURL = url

		Task.detached(priority: .utility) { [context] in
			let blurred = Self.blurred(contentsOf: url, using: context)
			await MainActor.run { self.image = blurred }
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
	nonisolated private static func currentWallpaperURL() -> URL? {
		if let aerial = aerialThumbnailURL() { return aerial }
		guard let screen = MainActor.assumeIsolated({ NSScreen.main ?? NSScreen.screens.first })
		else { return nil }
		return MainActor.assumeIsolated { NSWorkspace.shared.desktopImageURL(for: screen) }
	}

	/// The still that macOS keeps for the aerial currently set as the desktop.
	///
	/// It is small — a couple of hundred pixels — which would be useless for anything but
	/// this. Everything here is blurred to within an inch of its life before it is drawn, so
	/// the source resolution stops mattering: a heavy Gaussian of a 214px still and of a 6K
	/// frame are the same picture. The alternative was capturing the wallpaper window, which
	/// means asking for Screen Recording, and that is an outrageous thing to prompt for in
	/// order to draw a background.
	nonisolated private static func aerialThumbnailURL() -> URL? {
		let support = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
			.first?.appendingPathComponent("Application Support/com.apple.wallpaper")
		guard let support else { return nil }

		let store = support.appendingPathComponent("Store/Index.plist")
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
			if FileManager.default.fileExists(atPath: thumbnail.path) { return thumbnail }
		}
		return nil
	}

	// MARK: - Blur

	/// Loads, downsamples and blurs. Returns nil for anything that isn't a readable image.
	///
	/// Not every desktop picture is a file this can open: a Sonoma-and-later dynamic
	/// wallpaper is a `.madesktop` bundle, and the aerials are video. `CIImage` simply
	/// fails on those, which is the right outcome — the caller keeps its flat ground rather
	/// than showing something wrong.
	nonisolated private static func blurred(contentsOf url: URL, using context: CIContext) -> NSImage? {
		guard let source = CIImage(contentsOf: url) else { return nil }

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
		guard let output = blur.outputImage?.cropped(to: scaled.extent),
			let cgImage = context.createCGImage(output, from: scaled.extent)
		else { return nil }

		return NSImage(cgImage: cgImage, size: scaled.extent.size)
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
