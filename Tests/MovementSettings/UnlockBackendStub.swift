import Foundation

/// Stand-in for the real `UnlockBackendKind` (`Sources/Security/UnlockBackend.swift`).
///
/// Only the cases `Preferences.swift` names are reproduced, so this harness can
/// compile the real preferences source without pulling in the backend's whole
/// dependency graph (vault, embedders, capture). It asserts nothing on its own.
enum UnlockBackendKind: String, CaseIterable, Sendable {
	case none
	case authPlugin
	case keystroke
}

/// Stand-in for `DetectionDistance` (`Sources/Recognition/FrameQuality.swift`), which
/// `Preferences.swift` stores; the real one would pull in the frame-quality code.
enum DetectionDistance: String, CaseIterable, Sendable {
	case close
	case standard
	case far
}
