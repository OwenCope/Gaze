import Foundation

@MainActor
final class SetupSessionWork {
	private(set) var revision = UUID()
	private var tasks: [UUID: Task<Void, Never>] = [:]
	var activeCount: Int { tasks.count }

	func isCurrent(_ revision: UUID) -> Bool {
		self.revision == revision && !Task.isCancelled
	}

	func run(_ operation: @escaping @MainActor (UUID) async -> Void) {
		let token = revision
		let identifier = UUID()
		tasks[identifier] = Task { [weak self] in
			guard self?.isCurrent(token) == true else { return }
			await operation(token)
			self?.tasks.removeValue(forKey: identifier)
		}
	}

	func cancel() {
		revision = UUID()
		let pending = Array(tasks.values)
		tasks.removeAll()
		for task in pending { task.cancel() }
	}

	isolated deinit {
		for task in tasks.values { task.cancel() }
	}
}
