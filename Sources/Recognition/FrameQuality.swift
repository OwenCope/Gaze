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
	/// face is too far away to be someone leaning in — a bystander, not an unlock attempt.
	static let minFaceHeight: CGFloat = 0.18

	/// Vision's own capture-quality floor. Its scale is roughly 0…1 and a well-framed face
	/// sits far above this, so only motion-blurred or barely-detected faces fall under it.
	///
	/// Checked *only when Vision actually reported a quality* — `faceCaptureQuality` is nil on
	/// some revisions and lands here as 0, and a hard floor would then reject every frame and
	/// nobody could ever unlock. A reported 0-ish quality is real; an absent one is not.
	static let minVisionQuality: Float = 0.1

	/// Why a frame was not worth grading.
	///
	/// Split out from `isUsable` because the two rejections call for opposite fixes and
	/// were indistinguishable from the logs: a face measured as too small points at the
	/// bounding box (wrong coordinate space, or a genuinely distant person), while a low
	/// Vision quality points at the exposure the lock screen leaves us with. Counting them
	/// together said only that 73 of 74 frames were dropped, which named neither.
	enum Rejection: String {
		case tooSmall = "too small"
		case tooBlurred = "too blurred"
	}

	static func rejection(_ sample: FaceSample) -> Rejection? {
		if sample.boundingBox.height < minFaceHeight { return .tooSmall }
		if sample.quality > 0, sample.quality < minVisionQuality { return .tooBlurred }
		return nil
	}

	/// Whether this frame is good enough to base an unlock decision on.
	static func isUsable(_ sample: FaceSample) -> Bool { rejection(sample) == nil }
}
