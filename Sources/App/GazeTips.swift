import SwiftUI
import TipKit
import os

/// Native TipKit guidance for the notch panel preview.
///
/// The opening introduction stays in TourKit (`GazeWelcomeTour`); this tip only
/// points at the simulated panel preview in Settings, which runs without the
/// camera. It never appears on password or camera-consent screens, and no
/// window is shown automatically.
struct GazePanelPreviewTip: Tip {
	var title: Text {
		Text("Try the panel")
	}

	var message: Text? {
		Text("Preview each state without using the camera.")
	}

	var image: Image? {
		Image(systemName: "play.rectangle")
	}

	var options: [any TipOption] {
		Tips.MaxDisplayCount(2)
	}
}

/// Owns TipKit configuration.
///
/// Configure once at launch in normal mode only; review, scan-only and
/// browser-only modes never configure and never mutate tip history. Failures
/// log one fixed, non-sensitive message. The datastore is never reset here.
@MainActor
enum GazeTips {
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "Tips")

	private static var didConfigure = false

	static func configure() {
		guard !didConfigure else { return }
		didConfigure = true
		do {
			try Tips.configure([
				.displayFrequency(.daily),
				.datastoreLocation(.applicationDefault),
			])
		} catch {
			logger.notice("TipKit configuration failed")
		}
	}
}
