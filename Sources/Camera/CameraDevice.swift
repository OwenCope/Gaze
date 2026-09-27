import AVFoundation

/// Camera selection and trust.
///
/// Frame injection is the attack that matters here. A CoreMediaIO plugin (OBS
/// Virtual Camera and friends) or a USB device advertising itself as a webcam can
/// feed a pre-recorded video straight into the capture pipeline. No liveness model
/// can catch that: the anti-spoof CNNs look for *capture* artefacts — moiré off a
/// phone screen, paper grain, print edges, specular reflection — and an injected
/// recording has none, because nothing was ever filmed. The model sees a clean,
/// well-lit, genuine-looking face and says so.
///
/// So we don't try to detect injection downstream. We refuse to read from anything
/// but the machine's built-in camera, and we pin the exact device at enrolment.
///
/// An opt-in exception covers clamshell mode (lid closed, USB webcam): when the
/// user allows USB cameras, `candidates(allowExternal:)` also admits devices whose
/// transport is USB. Virtual cameras (CoreMediaIO plugins such as OBS) and
/// Continuity Camera stay refused either way.
enum CameraDevice {

	/// FourCC reported by cameras soldered to the logic board (`'bltn'`).
	private static let builtInTransport: Int32 = 0x626C746E
	/// FourCC reported by USB-attached cameras (`'usb '`).
	private static let usbTransport: Int32 = 0x75736220

	enum TrustFailure: Error, CustomStringConvertible {
		case noBuiltInCamera
		case notBuiltIn(name: String)
		case deviceChanged(expected: String, found: String)

		var description: String {
			switch self {
			case .noBuiltInCamera:
				return "No built-in camera found on this Mac."
			case .notBuiltIn(let name):
				return "“\(name)” is not the built-in camera. Gaze only trusts the camera built into this Mac."
			case .deviceChanged(let expected, let found):
				return "The camera changed since you enrolled (expected \(expected), found \(found))."
			}
		}
	}

	/// The built-in camera, or nil if this Mac has none.
	///
	/// `.builtInWideAngleCamera` already excludes `.external` and `.continuityCamera`
	/// on modern macOS, but discovery is only the first filter — `verify` re-checks
	/// the transport type, because device types are a hint and transport is hardware.
	static func builtIn() -> AVCaptureDevice? {
		AVCaptureDevice.DiscoverySession(
			deviceTypes: [.builtInWideAngleCamera],
			mediaType: .video,
			position: .front
		).devices.first { $0.transportType == builtInTransport }
	}

	/// The trusted cameras in preference order: built-in first, then USB when allowed.
	static func candidates(allowExternal: Bool) -> [AVCaptureDevice] {
		var result: [AVCaptureDevice] = []
		if let builtIn = builtIn() { result.append(builtIn) }
		guard allowExternal else { return result }
		let usb = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.external],
			mediaType: .video,
			position: .unspecified
		).devices.filter { $0.transportType == usbTransport }
		result.append(contentsOf: usb.filter { device in
			!result.contains(where: { $0.uniqueID == device.uniqueID })
		})
		return result
	}

	/// Resolves the camera to authenticate against, refusing anything untrusted.
	///
	/// - Parameter pinnedID: the `uniqueID` recorded at enrolment. When present the
	///   device must still be that same one, so swapping hardware invalidates unlock
	///   rather than silently authenticating against a different sensor.
	static func trusted(pinnedID: String?, allowExternal: Bool = false) throws -> AVCaptureDevice {
		guard !allowExternal else {
			let list = candidates(allowExternal: true)
			if let pinnedID {
				if let device = list.first(where: { $0.uniqueID == pinnedID }) { return device }
				throw TrustFailure.deviceChanged(
					expected: pinnedID, found: list.first?.uniqueID ?? "none")
			}
			guard let first = list.first else { throw TrustFailure.noBuiltInCamera }
			return first
		}
		guard let device = builtIn() else { throw TrustFailure.noBuiltInCamera }

		guard device.transportType == builtInTransport else {
			throw TrustFailure.notBuiltIn(name: device.localizedName)
		}

		if let pinnedID, device.uniqueID != pinnedID {
			throw TrustFailure.deviceChanged(expected: pinnedID, found: device.uniqueID)
		}

		return device
	}

	/// True when a virtual or external camera is present on the system.
	///
	/// Not fatal on its own — we never select these — but worth surfacing in the UI
	/// so the user knows a capture plugin is installed.
	static func untrustedCamerasPresent() -> Bool {
		AVCaptureDevice.DiscoverySession(
			deviceTypes: [.external, .continuityCamera],
			mediaType: .video,
			position: .unspecified
		).devices.isEmpty == false
	}
}
