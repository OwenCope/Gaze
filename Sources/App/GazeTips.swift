import TipKit
import os

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
