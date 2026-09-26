import AppKit
import AVFoundation

/// Lets the product-capture tool photograph a finished setup instead of a fresh install.
///
/// Always false in the shipping app: the switch exists only when the capture tool builds
/// these sources with `-D PRODUCT_CAPTURE`, and even then only with `--demo-state`.
enum ProductCaptureDemo {
	static var isOn: Bool {
		#if PRODUCT_CAPTURE
		CommandLine.arguments.contains("--demo-state")
		#else
		false
		#endif
	}
}

extension SettingsView {
	static var cameraAuthorized: Bool {
		if ProductCaptureDemo.isOn { return true }
		return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
	}

	/// The capture tool's fresh ad-hoc bundle gets a generic icon from Launch Services
	/// until it is indexed, so under capture it reads the Gaze icon file directly.
	static var appIcon: NSImage {
		if ProductCaptureDemo.isOn, let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
		   let icon = NSImage(contentsOf: url) {
			return icon
		}
		return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
	}
}
