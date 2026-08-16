import SwiftUI
#if HAS_FACEIDKIT
import FaceIDKit
#endif

/// The animated mark setup shows: looking, recognised, or not.
///
/// The only place in this flow that knows FaceIDKit exists. Everything else is
/// plain SwiftUI, which is the point — the animations are licensed to this app
/// and cannot be in the repository, so if the `#if` were sprinkled through the
/// step views then half the setup flow would be unbuildable for anyone else.
/// Confined here, the fallback is one substitution and the rest of the flow
/// never knows which it got.
///
/// The fallback is not a placeholder. `faceid` and `checkmark.circle.fill` are
/// system symbols with real transitions behind them, and a build without
/// FaceIDKit should look plainer, never broken.
struct SetupMark: View {

	enum Kind: Equatable {
		case looking
		case success
		case failure
	}

	let kind: Kind
	var diameter: CGFloat = 180
	/// Bump to replay the result animation. Ignored while looking.
	var trigger: Int = 0

	var body: some View {
		#if HAS_FACEIDKIT
		switch kind {
		case .looking:
			FaceIDScanView(
				isVisible: true,
				isScanning: true,
				faceColor: .white,
				scanColor: Theme.faceID
			)
			.frame(width: diameter, height: diameter)
		case .success, .failure:
			FaceIDSuccessView(
				diameter: diameter,
				color: kind == .success ? Theme.faceID : Theme.danger,
				result: kind == .success ? .success : .failure,
				trigger: trigger
			)
			.frame(width: diameter, height: diameter)
		}
		#else
		Image(systemName: symbolName)
			.font(.system(size: diameter * 0.55, weight: .regular))
			.symbolRenderingMode(.hierarchical)
			.foregroundStyle(tint)
			.frame(width: diameter, height: diameter)
			.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
			.symbolEffect(.breathe, options: .repeating.speed(1.6), isActive: kind == .looking)
			.symbolEffect(.bounce, value: trigger)
		#endif
	}

	private var symbolName: String {
		switch kind {
		case .looking: return "faceid"
		case .success: return "checkmark.circle.fill"
		case .failure: return "exclamationmark.circle.fill"
		}
	}

	private var tint: Color {
		switch kind {
		case .looking: return .white
		case .success: return Theme.faceID
		case .failure: return Theme.danger
		}
	}
}
