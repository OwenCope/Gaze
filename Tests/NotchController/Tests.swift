import AppKit
import SwiftUI

@main struct NotchControllerTests {
	@MainActor static func main() {
		_ = NSApplication.shared
		let controller = NotchCapsuleController(usesLockScreenSpace: false)
		let prefs = Preferences.shared
		controller.show()
		guard let panel = NSApp.windows.first(where: { $0 is NSPanel }) else {
			fatalError("Expected a real capsule panel")
		}
		let initial = panel.frame
		prefs.notchHeightAdjust = 20
		controller.show()
		precondition(panel.frame.height == initial.height + 20,
			"Re-showing a mounted panel must apply height changes even when caption room is unchanged")
		precondition(panel.contentView?.fittingSize.height == panel.frame.height, "Capsule root follows height changes")
		precondition(panel.frame.maxY == initial.maxY, "Panel stays attached to the screen top")
		prefs.notchWidthAdjust = 40
		controller.show()
		precondition(panel.frame.width == initial.width + 40, "Mounted panel must apply width changes")
		precondition(panel.frame.midX == initial.midX, "Panel stays centred")
		precondition(panel.contentView?.fittingSize.width == panel.frame.width, "Capsule root follows width changes")
		prefs.panelShape = .island
		controller.show()
		prefs.panelShape = .dynamicIsland
		controller.show()
		precondition(panel.frame.width >= 380, "Dynamic Island must reserve its 340pt body and margins")
		precondition(panel.contentView?.frame.size == panel.frame.size, "Hosting view follows window size")
		print("PASS: mounted capsule height, width, shape changes and top-centre alignment")
	}
}
