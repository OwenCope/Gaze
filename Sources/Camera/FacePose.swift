import Foundation
import Vision

/// Raw Vision orientation in radians, before the preview's horizontal mirror.
struct FacePose: Sendable, Equatable {
	/// Which estimator measured one pose axis.
	///
	/// Vision and the landmark fallback disagree on the zero point and the fallback's
	/// magnitudes are uncalibrated, so a baseline taken with one must never be compared
	/// against movement taken with the other. Every axis carries its own source because
	/// revisions can populate yaw while leaving pitch nil.
	enum AxisSource: Sendable, Equatable {
		/// Vision's own estimate for the frame.
		case vision
		/// Geometric fallback from `estimate(from:)` when Vision omitted that axis.
		case landmarkEstimate
		/// Neither Vision nor the fallback measured this axis. The value is NaN, never
		/// a stand-in zero, so finiteness checks still fail closed.
		case unavailable
	}

	/// Positive yaw moves the face toward screen left in the mirrored preview.
	var yaw: Double
	/// Positive pitch is chin down.
	var pitch: Double
	var roll: Double
	/// Per-axis provenance. Plain `FacePose(yaw:pitch:roll:)` literals default to
	/// `.vision`, keeping synthetic single-source sequences meaningful; production
	/// frames must come through `resolved(visionYaw:visionPitch:visionRoll:estimate:)`.
	var yawSource: AxisSource = .vision
	var pitchSource: AxisSource = .vision
	var rollSource: AxisSource = .vision

	/// Neutral display value, not a measurement. Anything that must distinguish "no
	/// measurement" from "frontal" checks the axis source, not this.
	static let zero = FacePose(yaw: 0, pitch: 0, roll: 0)

	/// Clockwise from up, in the mirrored preview's coordinates.
	var ringAngle: Double { atan2(-yaw, -pitch) }
	var offCentre: Double { min(1, hypot(yaw, pitch) / 0.55) }

	/// Picks Vision's value per axis when present, else the landmark estimate when that
	/// axis was actually estimated, else NaN with `.unavailable`. Axes decide alone: a
	/// missing pitch estimate must not disturb a measured yaw, and a missing estimate
	/// must never read as a frontal zero.
	///
	/// A nonfinite Vision value stays `.vision`: it is a failed measurement from that
	/// estimator, not a licence to substitute the other one.
	static func resolved(visionYaw: Double?, visionPitch: Double?, visionRoll: Double?, estimate: FacePose) -> FacePose {
		func pick(_ vision: Double?, estimatedValue: Double, estimatedSource: AxisSource) -> (Double, AxisSource) {
			if let vision { return (vision, .vision) }
			if estimatedSource == .landmarkEstimate, estimatedValue.isFinite {
				return (estimatedValue, .landmarkEstimate)
			}
			return (.nan, .unavailable)
		}
		let (yaw, yawSource) = pick(visionYaw, estimatedValue: estimate.yaw, estimatedSource: estimate.yawSource)
		let (pitch, pitchSource) = pick(visionPitch, estimatedValue: estimate.pitch, estimatedSource: estimate.pitchSource)
		let (roll, rollSource) = pick(visionRoll, estimatedValue: estimate.roll, estimatedSource: estimate.rollSource)
		return FacePose(yaw: yaw, pitch: pitch, roll: roll,
			yawSource: yawSource, pitchSource: pitchSource, rollSource: rollSource)
	}

	/// Approximate pose when Vision omits an axis. Magnitudes are not calibrated
	/// replacements for Vision; the horizontal sign must agree with it.
	///
	/// Per axis: estimated where the landmarks allow, NaN with `.unavailable` where
	/// they don't. Roll needs both pupils; yaw and pitch additionally need the nose
	/// and a usable interocular distance.
	static func estimate(from landmarks: VNFaceLandmarks2D) -> FacePose {
		estimate(leftPupil: landmarks.leftPupil?.normalizedPoints.first,
			rightPupil: landmarks.rightPupil?.normalizedPoints.first,
			nose: landmarks.nose?.normalizedPoints)
	}

	static func estimate(leftPupil: CGPoint?, rightPupil: CGPoint?, nose: [CGPoint]?) -> FacePose {
		var roll = Double.nan
		var rollSource = AxisSource.unavailable
		if let leftPupil, let rightPupil,
			leftPupil.x.isFinite, leftPupil.y.isFinite,
			rightPupil.x.isFinite, rightPupil.y.isFinite,
			hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y) > 0.001 {
			let value = Double(atan2(rightPupil.y - leftPupil.y, rightPupil.x - leftPupil.x))
			if value.isFinite {
				roll = value
				rollSource = .landmarkEstimate
			}
		}
		guard let leftPupil, let rightPupil, let nose, !nose.isEmpty else {
			return FacePose(yaw: .nan, pitch: .nan, roll: roll,
				yawSource: .unavailable, pitchSource: .unavailable, rollSource: rollSource)
		}
		let eyeMidX = (leftPupil.x + rightPupil.x) / 2
		let eyeMidY = (leftPupil.y + rightPupil.y) / 2
		let interocular = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
		guard interocular.isFinite, interocular > 0.001 else {
			return FacePose(yaw: .nan, pitch: .nan, roll: roll,
				yawSource: .unavailable, pitchSource: .unavailable, rollSource: rollSource)
		}
		let noseX = nose.map(\.x).reduce(0, +) / CGFloat(nose.count)
		let noseY = nose.map(\.y).reduce(0, +) / CGFloat(nose.count)
		let dx = (noseX - eyeMidX) / interocular
		let dy = (noseY - eyeMidY) / interocular
		let yaw = Double(dx) * 1.6
		let pitch = (Double(dy) + 0.55) * 1.6
		return FacePose(
			yaw: yaw.isFinite ? yaw : .nan,
			pitch: pitch.isFinite ? pitch : .nan,
			roll: roll,
			yawSource: yaw.isFinite ? .landmarkEstimate : .unavailable,
			pitchSource: pitch.isFinite ? .landmarkEstimate : .unavailable,
			rollSource: rollSource)
	}
}
