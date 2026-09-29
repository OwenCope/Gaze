import CoreGraphics
import Foundation

/// A cheap "is this frame even worth judging?" check, run before the expensive embed.
///
/// The unlock loop used to grade every frame that held a face — including ones caught
/// mid-turn, or with the person halfway across the room — and then count a low score toward
/// the lockout. Those aren't spoofs and they aren't real rejections: they're frames that
/// should never have been graded. Skipping them means the match is judged on frames good
/// enough to judge, and a passer-by six feet away no longer burns the enrolled user's six
/// attempts before they've even sat down.
///
/// Deliberately lenient. The lock screen is dark and the tuning that matters lives at the
/// low-light, low-score end (see `CoreMLEmbedder.matchThreshold`); this rejects only what is
/// genuinely unusable, never a dim-but-real face leaning in to unlock.
enum FrameQuality {

	/// Smallest face, as a fraction of frame height, worth trying to identify. Below this the
	/// face is too far away to be an unlock attempt — a bystander, not someone leaning in.
	/// Follows the Detection distance setting: far accepts smaller faces than the default.
	/// Read straight from the defaults rather than `Preferences.shared`: this runs on
	/// the camera's queue, and the preferences object belongs to the main actor.
	static var minFaceHeight: CGFloat {
		let raw = UserDefaults.standard.string(forKey: "detectionDistance") ?? ""
		return (DetectionDistance(rawValue: raw) ?? .standard).minFaceHeight
	}

	/// Vision's own capture-quality floor. Its scale is roughly 0…1 and a well-framed face
	/// sits far above this, so only motion-blurred or barely-detected faces fall under it.
	///
	/// Checked only when Vision actually reported a quality. `hasQualityMeasurement`
	/// distinguishes an unavailable measurement from a reported zero (unusable).
	static let minVisionQuality: Float = 0.1

	/// Why a frame was not worth grading.
	///
	/// Split out from `isUsable` because the two rejections call for opposite fixes and
	/// were indistinguishable from the logs: a face measured as too small points at the
	/// bounding box (wrong coordinate space, or a genuinely distant person), while a low
	/// Vision quality points at the exposure the lock screen leaves us with. Counting them
	/// together said only that 73 of 74 frames were dropped, which named neither.
	enum Rejection: String {
		case invalidMeasurements = "invalid measurements"
		case tooSmall = "too small"
		case tooBlurred = "too blurred"
	}

	static func rejection(_ sample: FaceSample) -> Rejection? {
		let bounds = sample.boundingBox
		// Pose axes stay out of this guard: FacePose reports unavailable axes as NaN,
		// and a missing yaw/pitch/roll must not make a frame unidentifiable. Liveness
		// still gates on finiteness itself via each axis's AxisSource.
		guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
			bounds.width.isFinite, bounds.height.isFinite,
			bounds.width > 0, bounds.height > 0,
			bounds.minX >= 0, bounds.minY >= 0, bounds.maxX <= 1.000001, bounds.maxY <= 1.000001,
			sample.quality.isFinite, (0...1).contains(sample.quality) else {
			return .invalidMeasurements
		}
		if sample.boundingBox.height < minFaceHeight { return .tooSmall }
		if sample.hasQualityMeasurement, sample.quality < minVisionQuality { return .tooBlurred }
		return nil
	}

	/// Whether this frame is good enough to base an unlock decision on.
	static func isUsable(_ sample: FaceSample) -> Bool { rejection(sample) == nil }
}

/// How far away Gaze can recognise a face.
///
/// Close needs the face to fill more of the frame; far accepts a smaller
/// face and asks for a slightly closer match, since distant faces give noisier prints.
enum DetectionDistance: String, CaseIterable, Sendable {
	case close
	case standard
	case far

	/// Smallest face height, as a fraction of frame height, worth identifying.
	var minFaceHeight: CGFloat {
		switch self {
		case .close: return 0.20
		case .standard: return 0.14
		case .far: return 0.10
		}
	}

	/// Added to the embedder's match threshold alongside the sensitivity offset.
	var thresholdOffset: Float {
		switch self {
		case .close: return 0
		case .standard: return 0
		case .far: return 0.03
		}
	}

	var title: String {
		switch self {
		case .close: return "Close"
		case .standard: return "Default"
		case .far: return "Far"
		}
	}
}
