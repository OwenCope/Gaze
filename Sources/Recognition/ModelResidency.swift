import Foundation

/// Dropped after idleness so Gaze doesn't pin Core ML weights forever.
protocol IdleUnloadable: AnyObject {
	func unloadIfIdle(for interval: TimeInterval)
}

/// One reloadable model behind a lock. The lock covers only load/fetch/unload;
/// predictions run unlocked against a local strong reference, so a slow
/// prediction never blocks an unload (or a `preload`) for longer than a load.
final class ModelSlot<Model>: IdleUnloadable, @unchecked Sendable {
	private let lock = NSLock()
	private let load: () -> Model?
	private var value: Model?
	private var lastUse = Date()

	init(load: @escaping () -> Model?, initial: Model? = nil) {
		self.load = load
		self.value = initial
		ModelResidency.register(self)
	}

	/// Loads when needed, stamps use, runs the body unlocked. Nil when loading fails.
	func withModel<R>(_ body: (Model) throws -> R) rethrows -> R? {
		let model = lock.withLock { () -> Model? in
			if value == nil { value = load() }
			lastUse = Date()
			return value
		}
		guard let model else { return nil }
		return try body(model)
	}

	/// Runs the body only if the model is already loaded; never loads. For callers on
	/// the main thread, where a first load would freeze the UI.
	func ifLoaded<R>(_ body: (Model) throws -> R) rethrows -> R? {
		let model = lock.withLock { () -> Model? in
			if value != nil { lastUse = Date() }
			return value
		}
		guard let model else { return nil }
		return try body(model)
	}

	/// Reloads when unloaded (lock-screen path calls this at lock and wake).
	func preload() {
		lock.withLock {
			if value == nil { value = load() }
			lastUse = Date()
		}
	}

	func unloadIfIdle(for interval: TimeInterval) {
		lock.withLock {
			if Date().timeIntervalSince(lastUse) >= interval { value = nil }
		}
	}
}

/// One background sweep unloads every registered slot idle past the limit.
enum ModelResidency {
	static let idleLimit: TimeInterval = 300

	private static let lock = NSLock()
	private static var slots: [any IdleUnloadable] = []
	private static var timer: DispatchSourceTimer?

	static func register(_ slot: AnyObject & IdleUnloadable) {
		lock.withLock {
			slots.append(slot)
			guard timer == nil else { return }
			let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
			t.schedule(deadline: .now() + idleLimit, repeating: 60)
			t.setEventHandler { reap() }
			t.resume()
			timer = t
		}
	}

	private static func reap() {
		let current = lock.withLock { slots }
		for slot in current { slot.unloadIfIdle(for: idleLimit) }
	}
}
