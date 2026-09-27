import AVFoundation
import AppKit
import SwiftUI

/// Real product media for a setup page: a recording or screenshot of the actual app or
/// macOS, framed like the welcome tour's shots. Drawn mock-ups read as fake next to the
/// tour, so setup shows the real thing.
struct SetupShot: View {
	enum Source {
		/// A looping muted clip in Resources/Art.
		case video(String)
		/// A still in Resources/Art.
		case image(String)
	}

	let source: Source
	/// Width over height of the media, so it can be fitted without cropping.
	var aspectRatio: CGFloat = 16.0 / 10.0
	var cornerRadius: CGFloat = 14

	var body: some View {
		content
			.aspectRatio(aspectRatio, contentMode: .fit)
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
					.strokeBorder(.white.opacity(0.12), lineWidth: 1)
			}
			.shadow(color: .black.opacity(0.45), radius: 24, y: 12)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
	}

	@ViewBuilder
	private var content: some View {
		switch source {
		case .video(let name):
			if let url = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Art") {
				LoopingVideo(url: url)
			} else {
				Color(white: 0.08)
			}
		case .image(let name):
			if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art"),
				let image = NSImage(contentsOf: url) {
				Image(nsImage: image).resizable().interpolation(.high)
			} else {
				Color(white: 0.08)
			}
		}
	}
}

/// A muted clip, looping, with no controls.
///
/// `AVPlayerLooper` rather than watching for `didPlayToEndTime` and seeking back to zero:
/// the notification approach leaves a visible stutter at the seam — a frame or two of
/// nothing while the seek completes — which on an eight-second loop is noticeable every
/// eight seconds. The looper keeps a second item queued and cuts to it.
///
/// An `NSViewRepresentable` around `AVPlayerLayer` rather than SwiftUI's `VideoPlayer`,
/// which draws playback controls that appear on hover. There is nothing here to control.
struct LoopingVideo: NSViewRepresentable {

	let url: URL

	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		view.wantsLayer = true

		let player = AVQueuePlayer()
		player.isMuted = true
		// Nothing else on this screen makes a sound, and a card that ducks the user's music
		// to play silence is a real thing that real apps do.
		player.audiovisualBackgroundPlaybackPolicy = .pauses

		let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
		context.coordinator.player = player
		context.coordinator.looper = looper

		let layer = AVPlayerLayer(player: player)
		layer.videoGravity = .resizeAspectFill
		layer.frame = view.bounds
		layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
		view.layer?.addSublayer(layer)

		player.play()
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {}

	func makeCoordinator() -> Coordinator { Coordinator() }

	/// Holds the player and the looper. Without a strong reference the looper is collected
	/// as soon as `makeNSView` returns and the clip plays exactly once.
	final class Coordinator {
		var player: AVQueuePlayer?
		var looper: AVPlayerLooper?
	}
}
