/// Stand-in for the pixel pupil finder: this harness's FaceSample carries no pixels,
/// so challenges fall back to the landmark gaze, which these tests drive directly.
enum PupilLocator {
	static func eyeWidthPixels(_ sample: FaceSample) -> Double? { nil }
	static func horizontalOffset(_ sample: FaceSample) -> Double? { nil }
	static func gaze(_ sample: FaceSample) -> (x: Double, y: Double?)? { nil }
}
