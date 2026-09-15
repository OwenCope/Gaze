import Foundation
import Vision

/// Raw Vision orientation in radians, before the preview's horizontal mirror.
struct FacePose: Sendable, Equatable {
	/// Positive yaw moves the face toward screen left in the mirrored preview.
	var yaw: Double
	/// Positive pitch is chin down.
	var pitch: Double
	var roll: Double

	static let zero = FacePose(yaw: 0, pitch: 0, roll: 0)

	/// Clockwise from up, in the mirrored preview's coordinates.
	var ringAngle: Double { atan2(-yaw, -pitch) }
	var offCentre: Double { min(1, hypot(yaw, pitch) / 0.55) }

	/// Approximate pose when Vision omits an axis. Magnitudes are not calibrated
	/// replacements for Vision; the horizontal sign must agree with it.
	static func estimate(from landmarks: VNFaceLandmarks2D) -> FacePose {
		guard let leftPupil = landmarks.leftPupil?.normalizedPoints.first,
			let rightPupil = landmarks.rightPupil?.normalizedPoints.first,
			let nose = landmarks.nose?.normalizedPoints, !nose.isEmpty else { return .zero }
		let eyeMidX = (leftPupil.x + rightPupil.x) / 2
		let eyeMidY = (leftPupil.y + rightPupil.y) / 2
		let interocular = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
		guard interocular > 0.001 else { return .zero }
		let noseX = nose.map(\.x).reduce(0, +) / CGFloat(nose.count)
		let noseY = nose.map(\.y).reduce(0, +) / CGFloat(nose.count)
		let dx = (noseX - eyeMidX) / interocular
		let dy = (noseY - eyeMidY) / interocular
		return FacePose(yaw: Double(dx) * 1.6,
			pitch: (Double(dy) + 0.55) * 1.6,
			roll: Double(atan2(rightPupil.y - leftPupil.y, rightPupil.x - leftPupil.x)))
	}
}
