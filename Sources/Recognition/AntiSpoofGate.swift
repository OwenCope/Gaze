import Foundation

/// The anti-spoof decision for the unlock path.
///
/// Built on the **object detector** (`SpoofDetector`) alone. It looks at the whole frame for
/// the device — a phone body, a screen bezel, a held print — which is the attack that
/// actually happens: someone holding up a photo of you.
///
/// "It behaves, reading a real face as clear" used to be the claim here, and the measurement
/// below does not support it: on the bundled validation set the detector scores a live face
/// at or above 0.5 nearly half the time. It carries real signal — live faces average 0.27
/// against 0.55 for spoofs — but the two distributions overlap heavily, so where the
/// threshold sits decides everything, and it has to sit inside the range the model actually
/// produces.
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
	}

	private let spoof: SpoofDetector?

	/// How sure the object detector must be it sees a device before it rejects.
	///
	/// Deliberately conservative: a false reject here turns a genuine user away, so the bar
	/// to reject is high. But it was 0.85, and 0.85 is not a conservative gate — it is no
	/// gate at all.
	///
	/// Measured against the bundled Roboflow validation set (600 images, 300 per class,
	/// evenly sampled), running the shipped `Spoof.mlmodelc`. The highest spoof-confidence
	/// this model produced on *any* of those images was **0.717**. Nothing can reach 0.85,
	/// so the gate rejected 0 of 300 held-device photos: it has been inert since it was
	/// written, and the unlock path has had no working anti-spoof at all.
	///
	///     threshold   catches spoof   falsely rejects a live face
	///          0.50          87.7%                          48.3%
	///          0.60          60.3%                          10.7%
	///          0.65          24.0%                           4.3%
	///          0.70           3.3%                           0.0%
	///          0.85           0.0%                           0.0%
	///
	/// 0.65 is the point that respects the rule above — a gate that fires, at a false-reject
	/// rate low enough that the owner is not the one being punished by it. 0.60 roughly
	/// doubles the protection and quadruples the false rejects; that trade is a product
	/// decision rather than a fix, so it is left at the safer end.
	///
	/// The scores are clustered (the model's whole usable range is about 0.5–0.72), which is
	/// why the numbers move so fast between rows. Retuning wants a better detector rather
	/// than a better threshold — but a threshold inside the model's range beats one outside
	/// it, which is all this change claims.
	private let spoofRejectThreshold: Float

	init(spoof: SpoofDetector?, spoofRejectThreshold: Float = 0.65) {
		self.spoof = spoof
		self.spoofRejectThreshold = spoofRejectThreshold
	}

	/// Whether the detector is available to run. When false the caller skips the gate.
	var isActive: Bool { spoof != nil }

	func evaluate(_ sample: FaceSample) -> Decision {
		guard let spoof, let confidence = spoof.spoofConfidence(sample),
			confidence.isFinite, (0...1).contains(confidence) else { return .unavailable }
		if confidence >= spoofRejectThreshold {
			return .spoof(reason: "a device was seen in frame", score: confidence)
		}
		return .live
	}
}
