import AppKit
import ApplicationServices
import LocalAuthentication
import Observation
import SwiftUI

/// Face-scan state the recognizer reports for the caption under the face mark.
enum AppLockScanState: Equatable {
	case scanning
	case unavailable(reason: String)
	case faceDisabled
	/// Looked for a while with no match; the camera is off until the face is clicked.
	case resting
}

/// Mutable caption state shared with the hosted SwiftUI view.
///
/// The hosting view outlives any single show, so the caption lives in an
/// observable model rather than being passed as a plain value — replacing the
/// root view on each scan update would reset the view's identity.
@Observable
@MainActor
final class AppLockShieldStatus {
	var caption = "Looking for you"
	/// Drives the face the same way the lock-screen panel does: looking, the
	/// frown when it can't help, and the smile when it's you.
	var phase: NotchCapsuleModel.Phase = .scanning
}

/// The lock over a locked app.
///
/// It covers the app's own windows and nothing else, and follows them if they move
/// or resize. It is a non-activating panel: it never takes focus (`canBecomeKey` and
/// `canBecomeMain` are false), and Esc arrives through a local event monitor. One
/// window at most; every show tears the previous one down first.
@MainActor
final class AppLockShield {

	/// Fired when the shield appears. The camera step sets this and calls
	/// `unlockSucceeded()` on a match.
	var faceUnlockAttempt: ((String) -> Void)?

	/// Stops the in-flight face scan, if any. Set by the recognizer alongside
	/// `faceUnlockAttempt`; the shield calls it on every exit path.
	var stopFaceScan: (() -> Void)?

	private let machine: AppLockStateMachine
	private let status = AppLockShieldStatus()
	private var window: AppLockShieldWindow?
	private var escMonitor: Any?
	private var bundleID: String?
	private var appName = "this app"
	/// Keeps the shield on the app's windows as they move, and waits for the first
	/// window of an app that's still launching.
	private var followTask: Task<Void, Never>?
	/// Accessibility notifications for the locked app's windows moving and resizing, so
	/// the shield moves with them immediately rather than on the next poll.
	private var windowObserver: AXObserver?
	/// Set once the face or password has let the person in, so a late scan report
	/// can't turn "Unlocked" back into an error.
	private var didUnlock = false
	/// Last VoiceOver announcement, so the same words are not read twice in a row.
	private var lastAnnouncedText: String?

	init(machine: AppLockStateMachine) {
		self.machine = machine
	}

	/// Routes the watcher's shield requests here. Chain any previous handler.
	func attach(to watcher: AppLockWatcher) {
		let previous = watcher.onShieldNeeded
		watcher.onShieldNeeded = { [weak self] id in
			previous?(id)
			Task { @MainActor in self?.show(for: id) }
		}
	}

	func show(for bundleID: String) {
		guard AppLockStore.isNeverLockable(bundleID) == false else { return }
		// Already covering this app: another activation must not restart the scan.
		if self.bundleID == bundleID, window != nil, !didUnlock { return }
		teardownWindow()
		self.bundleID = bundleID
		didUnlock = false
		let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
		appName = app?.localizedName ?? "this app"
		status.caption = "Looking for you"
		status.phase = .scanning

		let window = AppLockShieldWindow()
		window.contentView = shieldRoot(icon: app?.icon ?? NSWorkspace.shared.icon(forFile: "/Applications"))
		self.window = window
		escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard event.keyCode == 53 else { return event }
			Task { @MainActor in self?.dismiss(hidingApp: true) }
			return nil
		}
		startWindowObserver(for: app)
		followTask = Task { [weak self] in await self?.follow(bundleID: bundleID) }
		faceUnlockAttempt?(bundleID)
	}

	/// Called by the camera step (or the password fallback) on a match.
	func unlockSucceeded() {
		guard let id = bundleID, !didUnlock else { return }
		didUnlock = true
		machine.unlock(id)
		stopFaceScan?()
		// The smile first, as on the lock screen, then the shield goes.
		status.phase = .success
		status.caption = "Unlocked"
		announceForVoiceOver("Unlocked")
		let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 650))
			self?.dissolve()
		}
	}

	/// Receives the recognizer's scan state for the caption under the face mark.
	func reportScanState(_ state: AppLockScanState) {
		guard !didUnlock else { return }
		switch state {
		case .scanning:
			status.caption = "Looking for you"
			status.phase = .scanning
			announceForVoiceOver(
				appName == "this app" ? "Looking for your face" : "Looking for your face to open \(appName)")
		case .unavailable(let reason):
			status.caption = reason
			status.phase = .notRecognised
			announceForVoiceOver(reason)
		case .faceDisabled:
			status.caption = "Use your password to open \(appName)"
			status.phase = .notRecognised
			announceForVoiceOver("Face unlock is off for this app. Use your password.")
		case .resting:
			status.caption = "Click Gaze to look again"
			status.phase = .locked
			announceForVoiceOver("Stopped looking. Click to try again, or use your password.")
		}
	}

	/// Reads state changes for VoiceOver. Silent when VoiceOver is off, and never
	/// repeats the same words twice in a row.
	private func announceForVoiceOver(_ text: String) {
		guard !text.isEmpty, text != lastAnnouncedText, NSWorkspace.shared.isVoiceOverEnabled else {
			return
		}
		lastAnnouncedText = text
		NSAccessibility.post(
			element: NSApp as Any,
			notification: .announcementRequested,
			userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
	}

	func dismiss(hidingApp: Bool = true) {
		stopFaceScan?()
		clearEscMonitor()
		followTask?.cancel()
		followTask = nil
		stopWindowObserver()
		if hidingApp, let id = bundleID {
			NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.hide()
		}
		window?.orderOut(nil)
		window = nil
		bundleID = nil
	}

	private func dissolve() {
		stopFaceScan?()
		clearEscMonitor()
		followTask?.cancel()
		followTask = nil
		stopWindowObserver()
		bundleID = nil
		guard let window else { return }
		self.window = nil
		if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
			window.orderOut(nil)
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.3
			context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
			window.animator().alphaValue = 0
		} completionHandler: {
			window.orderOut(nil)
		}
	}

	/// Orders out any existing window and clears its hooks, without hiding an
	/// app. Re-entrant shows replace rather than stack.
	private func teardownWindow() {
		stopFaceScan?()
		clearEscMonitor()
		followTask?.cancel()
		followTask = nil
		stopWindowObserver()
		window?.orderOut(nil)
		window = nil
	}

	private func clearEscMonitor() {
		if let escMonitor {
			NSEvent.removeMonitor(escMonitor)
			self.escMonitor = nil
		}
	}

	// MARK: - Following the app's windows

	/// Puts the shield over the app's windows and keeps it there.
	///
	/// An app opened while locked has no window yet when it activates, so this waits
	/// for one instead of covering the whole screen.
	private func follow(bundleID: String) async {
		var shown = false
		var waited: Duration = .zero
		while !Task.isCancelled, let window, self.bundleID == bundleID {
			if let frame = Self.windowFrame(for: bundleID) {
				if window.frame != frame { place(window, at: frame) }
				if !shown {
					window.alphaValue = 1
					window.orderFront(nil)
					shown = true
				}
			} else if shown {
				// Its windows went away (minimised or closed): nothing left to cover.
				window.orderOut(nil)
				shown = false
			} else if waited >= .seconds(3) {
				// Still no window after launching: keep the app out of the way instead.
				NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.hide()
			}
			// Every display frame while shown, so a drag or resize is tracked smoothly
			// rather than in visible steps.
			// With Accessibility notifications the poll is only a safety net.
			let step: Duration = !shown ? .milliseconds(60) : windowObserver != nil ? .milliseconds(100) : .milliseconds(16)
			try? await Task.sleep(for: step)
			waited += step
		}
	}

	/// Moves the shield with no implicit animation, so it sticks to the window instead of
	/// easing along behind it.
	private func place(_ window: NSWindow, at frame: NSRect) {
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0
			context.allowsImplicitAnimation = false
			window.setFrame(frame, display: true)
		}
	}

	/// Called from the Accessibility observer whenever the app's windows move or change.
	fileprivate func windowsChanged() {
		guard let window, let bundleID, let frame = Self.windowFrame(for: bundleID) else { return }
		if window.frame != frame { place(window, at: frame) }
	}

	private func startWindowObserver(for app: NSRunningApplication?) {
		stopWindowObserver()
		guard let pid = app?.processIdentifier, AXIsProcessTrusted() else { return }
		var created: AXObserver?
		let callback: AXObserverCallback = { _, _, _, refcon in
			guard let refcon else { return }
			let shield = Unmanaged<AppLockShield>.fromOpaque(refcon).takeUnretainedValue()
			MainActor.assumeIsolated { shield.windowsChanged() }
		}
		guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
		let element = AXUIElementCreateApplication(pid)
		let refcon = Unmanaged.passUnretained(self).toOpaque()
		for name in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXFocusedWindowChangedNotification,
			kAXWindowCreatedNotification, kAXUIElementDestroyedNotification] {
			AXObserverAddNotification(observer, element, name as CFString, refcon)
		}
		CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
		windowObserver = observer
	}

	private func stopWindowObserver() {
		guard let observer = windowObserver else { return }
		CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
		windowObserver = nil
	}

	/// The union of the app's ordinary windows, in AppKit screen coordinates.
	///
	/// Only layer-0 windows count: menu bar extras and popovers sit on other layers
	/// and would stretch the shield across the screen. `CGWindowListCopyWindowInfo`
	/// measures from the top-left of the main display; AppKit from the bottom-left.
	private static func windowFrame(for bundleID: String) -> NSRect? {
		guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
			let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
				as? [[String: Any]],
			let primaryHeight = NSScreen.screens.first?.frame.height
		else { return nil }
		var union: NSRect?
		for entry in list {
			guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid,
				(entry[kCGWindowLayer as String] as? Int) == 0,
				let bounds = entry[kCGWindowBounds as String] as? [String: Any],
				let x = (bounds["X"] as? NSNumber)?.doubleValue,
				let y = (bounds["Y"] as? NSNumber)?.doubleValue,
				let width = (bounds["Width"] as? NSNumber)?.doubleValue,
				let height = (bounds["Height"] as? NSNumber)?.doubleValue,
				width > 80, height > 80
			else { continue }
			let rect = NSRect(x: x, y: primaryHeight - y - height, width: width, height: height)
			union = union?.union(rect) ?? rect
		}
		return union
	}

	// MARK: - Content

	private func shieldRoot(icon: NSImage) -> NSView {
		let host = NSHostingView(rootView: AppLockShieldView(
			appName: appName,
			icon: icon,
			status: status,
			onUsePassword: { [weak self] in self?.authenticateWithPassword() },
			onLookAgain: { [weak self] in self?.lookAgain() },
			onBackgroundClick: { [weak self] in self?.dismiss(hidingApp: true) }
		))
		host.wantsLayer = true
		// Round like a window, so the app's own corners never show past the shield.
		host.layer?.cornerRadius = AppLockShieldWindow.cornerRadius
		host.layer?.cornerCurve = .continuous
		host.layer?.masksToBounds = true
		return host
	}

	/// Clicking the face after the camera has rested starts looking again.
	private func lookAgain() {
		guard let id = bundleID, !didUnlock, status.phase == .locked || status.phase == .notRecognised else { return }
		status.caption = "Looking for you"
		status.phase = .scanning
		faceUnlockAttempt?(id)
	}

	private func authenticateWithPassword() {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open \(appName)") { [weak self] success, _ in
			guard success else { return }
			Task { @MainActor in self?.unlockSucceeded() }
		}
	}
}

private final class AppLockShieldWindow: NSWindow {

	/// macOS window corners.
	static let cornerRadius: CGFloat = 16

	init() {
		// Made on a real screen, at a real size. A window born at .zero has no screen,
		// so its backing scale is 1 and the face's Metal drawable renders at half
		// resolution on a Retina display: the pixelated face.
		let screen = NSScreen.main ?? NSScreen.screens.first
		let start = NSRect(x: screen?.frame.midX ?? 0, y: screen?.frame.midY ?? 0, width: 400, height: 400)
		super.init(contentRect: start, styleMask: .borderless, backing: .buffered, defer: false)
		level = .floating + 1
		collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
		isOpaque = false
		backgroundColor = .clear
		hasShadow = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		alphaValue = 0
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}

/// The lock over an app, laid out like any other Gaze page: a plain white or black
/// ground that follows the Mac's appearance, the face looking for you, one line
/// saying which app is locked, and the password as the quiet way in.
///
/// Esc and clicking the empty ground still hide the app; they aren't spelled out,
/// the same way a sheet doesn't explain that Esc closes it.
private struct AppLockShieldView: View {

	let appName: String
	let icon: NSImage
	let status: AppLockShieldStatus
	let onUsePassword: () -> Void
	let onLookAgain: () -> Void
	let onBackgroundClick: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.colorScheme) private var colorScheme
	@State private var appeared = false

	private static let curve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)

	/// The content's natural size is about 364 × 330; smaller windows shrink it.
	private static func fit(_ size: CGSize) -> CGFloat {
		guard size.width > 0, size.height > 0 else { return 1 }
		return min(1, size.width / 364, size.height / 330)
	}

	private var ground: Color { colorScheme == .dark ? Color(red: 0.078, green: 0.078, blue: 0.082) : .white }
	private var primary: Color { colorScheme == .dark ? .white : Color(white: 0.11) }
	private var secondary: Color { colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.55) }

	var body: some View {
		GeometryReader { geometry in
		ZStack {
			ground
				.contentShape(Rectangle())
				.onTapGesture { onBackgroundClick() }
			VStack(spacing: 0) {
				// The face is the page; the app is named on it the way the App Lock
				// header badges Gaze's icon with a lock.
				GazeFaceMark(phase: status.phase, active: true)
					.frame(width: 96, height: 96)
					.overlay(alignment: .bottomTrailing) {
						Image(nsImage: icon)
							.resizable()
							.interpolation(.high)
							.frame(width: 34, height: 34)
							.shadow(color: .black.opacity(0.25), radius: 4, y: 2)
							.offset(x: 8, y: 8)
					}
					.contentShape(Rectangle())
					.onTapGesture { onLookAgain() }
					.accessibilityHidden(true)
				Text("\(appName) is locked")
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(primary)
					.fixedSize()
					.padding(.top, 28)
				Text(status.caption)
					.font(.system(size: 15))
					.foregroundStyle(secondary)
					.multilineTextAlignment(.center)
					.frame(width: 300)
					.fixedSize(horizontal: false, vertical: true)
					.contentTransition(.opacity)
					.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: status.caption)
					.padding(.top, 6)
				Button(action: onUsePassword) {
					Text("Use Password")
						.font(.system(size: 14, weight: .medium))
						.foregroundStyle(primary)
						.padding(.horizontal, 20)
						.frame(height: 34)
						.fixedSize()
						.background(Capsule().fill(primary.opacity(colorScheme == .dark ? 0.14 : 0.07)))
						.contentShape(Capsule())
				}
				// Drawn rather than a system style: this window can never be key, and the
				// system styles draw themselves greyed out in a window that isn't.
				.buttonStyle(.plain)
				.opacity(status.phase == .success ? 0 : 1)
				.animation(reduceMotion ? nil : .smooth(duration: 0.25), value: status.phase == .success)
				.padding(.top, 26)
				.accessibilityLabel("Use Password")
			}
			.padding(32)
			// Laid out once at full size, then scaled down to fit a small window, so a
			// narrow app never truncates the words.
			.scaleEffect(Self.fit(geometry.size))
			.animation(reduceMotion ? nil : .smooth(duration: 0.25), value: Self.fit(geometry.size))
			.scaleEffect(appeared || reduceMotion ? 1 : 0.96)
			.opacity(appeared || reduceMotion ? 1 : 0)
			.accessibilityElement(children: .contain)
			.accessibilityLabel("\(appName) is locked. \(status.caption)")
		}
		.frame(width: geometry.size.width, height: geometry.size.height)
		}
		.onAppear {
			withAnimation(reduceMotion ? nil : Self.curve) { appeared = true }
		}
	}
}
