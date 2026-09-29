import Observation

/// App Lock claims the camera while scanning: two sessions at once starve one of frames.
@MainActor @Observable final class ForegroundCameraClaim {
	static let shared = ForegroundCameraClaim()

	private var claimCount = 0
	private(set) var appLockIsScanning = false

	func beginAppLockScan() {
		claimCount += 1
		appLockIsScanning = claimCount > 0
	}

	func endAppLockScan() {
		claimCount = max(0, claimCount - 1)
		appLockIsScanning = claimCount > 0
	}
}
