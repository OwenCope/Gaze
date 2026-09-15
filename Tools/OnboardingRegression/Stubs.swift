import AppKit
import Observation
import SwiftUI

enum PasswordVault {
	static func store(_ candidate: String) throws -> Bool {
		fatalError("Onboarding review must never read or save credentials")
	}
}

@Observable @MainActor final class CameraController {
	enum State: Equatable { case idle, denied, failed(String), running }
	enum Absence { case noFace, multipleFaces(Int), analysisFailed, detectionFailed }
	var state: State = .idle
	var faceMissing = true
	var absence: Absence? = .noFace
}

struct CameraPreview: View {
	let controller: CameraController
	var body: some View {
		Color.black.overlay { Image(systemName: "video.slash").foregroundStyle(.secondary) }
	}
}

@Observable @MainActor final class EnrollmentModel {
	enum Phase { case positioning, capturing, complete }
	var phase = Phase.positioning
	var covered = [Bool](repeating: false, count: 44)
	var currentAngle = 0.0
	var isEngaged = false
	var progress = 0.0
	var instruction = "Camera disabled in review"
	var targetSegment: Int?
	var captureTitle = "Center your face"
}
