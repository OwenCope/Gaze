import Foundation

/// The anti-spoof decision for the unlock path.
///
/// Built on `SpoofDetector` alone: a live/spoof classifier run on the face crop (face plus
/// margin, so a bezel, screen edge or paper border near the face stays in view). It replaced
/// a Roboflow object detector that looked for a device in the whole frame and, on Owen's own
/// camera, caught nothing at its threshold.
///
/// The passive texture model (MiniFAS) is **deliberately not used here.** On a webcam it is
/// unreliable in the direction that matters most — it scored a real, live face 0.000 ("spoof")
/// in testing — and in a fail-closed gate a detector that calls the real user a spoof doesn't
/// harden the unlock, it locks the owner out. Texture liveness needs the kind of signal a
/// webcam can't give (Apple uses a depth camera); until there's a model that separates a
/// photo from a face without turning real users away, it stays out of the decision.
///
struct AntiSpoofGate: Sendable {

	enum Decision: Equatable, Sendable {
		case live
		case unavailable
		/// Rejected. `reason` is log/telemetry text; `score` is the signal that tripped it.
		case spoof(reason: String, score: Float)
		/// The classifier called this one frame a spoof, but not yet often enough in the
		/// scan to reject. The frame must not count toward a match; the caller skips it.
		case suspect(score: Float)
	}

	private let spoof: SpoofDetector?

	/// How sure the classifier must be it sees a spoof before it rejects.
	///
	/// Deliberately conservative: a false reject here turns a genuine user away, so the bar
	/// to reject is high. Measured by `Tools/Scripts/train-spoof-classifier.swift` on held-out
	/// data (numbers in `outputs/spoof-models/metrics.json`): Roboflow test frames grouped by
	/// subject (100 live, 100 spoof) and one held-out live and one spoof session from
	/// `DatasetCapture` on Owen's Mac (59 live, 35 spoof crops).
	///
	///                          Roboflow test          Owen's camera
	///                       catches   rejects live  catches   rejects live
	///     old detector 0.65   26%        6%            0%         0%
	///     classifier   0.50   46%       10%           20%         7%
	///     classifier   0.85   38%        6%           14%         2%
	///     classifier   0.90   37%        4%           11%         0%
	///
	/// 0.90 is the point that beats the old gate on both sets without rejecting more live
	/// faces. It is still weak protection: the own-camera set is one session per class, and
	/// more varied spoof sessions are what will move these numbers, not the threshold.
	static let defaultSpoofRejectThreshold: Float = 0.90

	private let spoofRejectThreshold: Float

	init(spoof: SpoofDetector?, spoofRejectThreshold: Float = Self.defaultSpoofRejectThreshold) {
		self.spoof = spoof
		self.spoofRejectThreshold = spoofRejectThreshold
	}

	/// Whether the detector is available to run. When false the caller skips the gate.
	var isActive: Bool { spoof != nil }

	func evaluate(_ sample: FaceSample) -> Decision {
		guard let spoof, let confidence = spoof.spoofConfidence(sample),
			confidence.isFinite, (0...1).contains(confidence) else { return .unavailable }
		if confidence >= spoofRejectThreshold {
			return .spoof(reason: "the face looked like a photo or screen", score: confidence)
		}
		return .live
	}
}
