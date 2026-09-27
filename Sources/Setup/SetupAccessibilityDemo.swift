import AppKit
import SwiftUI

/// The permission page's scene: the real System Settings pane, emptied down to one row,
/// with Gaze in it and macOS's own switch turning on.
///
/// The window is a screenshot (`Art/setup-accessibility.png`) so it looks exactly like
/// System Settings; only the row is live, placed in the screenshot's pixel coordinates.
struct SetupAccessibilityDemo: View {
	var isReady: Bool

	@State private var isOn = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// The screenshot's size and the empty row it leaves for Gaze, in its own pixels.
	private static let imageSize = CGSize(width: 1479, height: 392)
	private static let rowMidY: CGFloat = 306
	private static let iconX: CGFloat = 523
	private static let nameX: CGFloat = 583
	private static let switchMidX: CGFloat = 1383

	var body: some View {
		GeometryReader { proxy in
			let scale = proxy.size.width / Self.imageSize.width
			ZStack(alignment: .topLeading) {
				backdrop
				row(scale: scale)
			}
			.frame(width: proxy.size.width, height: Self.imageSize.height * scale)
			.frame(maxHeight: .infinity)
		}
		.aspectRatio(Self.imageSize.width / Self.imageSize.height, contentMode: .fit)
		.shadow(color: .black.opacity(0.45), radius: 24, y: 12)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.allowsHitTesting(false)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("System Settings, with Gaze turned on.")
		.task(id: isReady) {
			if isReady || reduceMotion {
				isOn = true
				return
			}
			while !Task.isCancelled {
				isOn = false
				do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
				withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOn = true }
				do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
			}
		}
	}

	@ViewBuilder
	private var backdrop: some View {
		if let url = Bundle.main.url(forResource: "setup-accessibility", withExtension: "png", subdirectory: "Art"),
			let image = NSImage(contentsOf: url) {
			Image(nsImage: image).resizable().interpolation(.high)
		} else {
			Color(white: 0.95)
		}
	}

	private func row(scale: CGFloat) -> some View {
		let iconSide = 40 * scale
		return ZStack(alignment: .topLeading) {
			Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
				.resizable()
				.frame(width: iconSide, height: iconSide)
				.offset(x: Self.iconX * scale, y: Self.rowMidY * scale - iconSide / 2)
			Text("Gaze")
				.font(.system(size: 26 * scale))
				.foregroundStyle(Color(white: 0.1))
				.fixedSize()
				.frame(height: iconSide, alignment: .center)
				.offset(x: Self.nameX * scale, y: Self.rowMidY * scale - iconSide / 2)
			// macOS's own switch, so it is the real Liquid Glass control, drawn light to
			// match the light System Settings window around it.
			Toggle("Gaze", isOn: $isOn)
				.toggleStyle(.switch)
				.labelsHidden()
				.controlSize(.regular)
				.environment(\.colorScheme, .light)
				.scaleEffect(scale * 1.9)
				.frame(width: 80 * scale, height: 44 * scale)
				.offset(x: Self.switchMidX * scale - 40 * scale, y: Self.rowMidY * scale - 22 * scale)
		}
	}
}
