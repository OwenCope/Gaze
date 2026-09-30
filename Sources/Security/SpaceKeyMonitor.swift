// Adapted from Glance by Jonathan Zhou, MIT licence, https://github.com/jonnyoo/glance

import Foundation
import IOKit
import IOKit.hid
import os

/// Notices the spacebar on the lock screen, so pressing Space looks again.
///
/// Raw IOKit HID reads: Secure Event Input swallows every other keyboard tap there.
/// Only runs while the screen is locked — LockWatcher starts it with the lock and stops
/// it with the unlock. No key logging: the callback only asks whether the key is Space,
/// and a missing grant fails closed to a no-op rather than prompting.
@MainActor
final class SpaceKeyMonitor {
	private static let logger = Logger(subsystem: "com.gazeunlock.Gaze", category: "SpaceKeyMonitor")

	/// Spacebar key-down: usage page 0x07, usage 0x2C.
	private static let spaceUsagePage: UInt32 = 0x07
	private static let spaceUsage: UInt32 = 0x2C

	/// Fires on spacebar key-down only, not release.
	var onSpaceKeyDown: (() -> Void)?

	private var manager: IOHIDManager?

	/// Idempotent. Fails closed when Input Monitoring isn't granted — never prompts.
	func start() {
		guard manager == nil else { return }
		guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }

		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		// Physical keyboards only (Generic Desktop page, Keyboard usage), not every HID device.
		let match: [String: Int] = [
			kIOHIDDeviceUsagePageKey: 0x01,
			kIOHIDDeviceUsageKey: 0x06,
		]
		IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

		// Capture-less C callback; self rides the context pointer. passUnretained is safe:
		// LockWatcher owns this and always stops (unregistering) before it can go away.
		let context = Unmanaged.passUnretained(self).toOpaque()
		IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
			guard let context else { return }
			let element = IOHIDValueGetElement(value)
			guard IOHIDElementGetUsagePage(element) == SpaceKeyMonitor.spaceUsagePage,
				IOHIDElementGetUsage(element) == SpaceKeyMonitor.spaceUsage,
				IOHIDValueGetIntegerValue(value) == 1
			else { return }
			let monitor = Unmanaged<SpaceKeyMonitor>.fromOpaque(context).takeUnretainedValue()
			// Already on the main thread (main run loop); assume isolation to reach the actor.
			MainActor.assumeIsolated { monitor.onSpaceKeyDown?() }
		}, context)

		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
		guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
			Self.logger.error("Space monitor failed to open; Space won't retry the scan.")
			IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
			return
		}
		Self.logger.notice("Listening for Space on the lock screen.")
		self.manager = manager
	}

	/// Idempotent.
	func stop() {
		guard let manager else { return }
		IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
		IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
		self.manager = nil
	}
}
