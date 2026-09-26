import Foundation

@MainActor
enum SetupLifecycleTests {
	final class Gate {
		var continuation: CheckedContinuation<Void, Never>?
		func wait() async { await withCheckedContinuation { continuation = $0 } }
		func release() { continuation?.resume(); continuation = nil }
	}

	static func until(_ condition: @escaping @MainActor () -> Bool) async {
		for _ in 0..<200 {
			if condition() { return }
			try? await Task.sleep(for: .milliseconds(1))
		}
		precondition(condition(), "Async fixture did not reach its expected state")
	}

	static func run() async {
		let work = SetupSessionWork()
		let original = work.revision
		var started = false
		work.run { _ in started = true }
		work.cancel()
		await Task.yield()
		precondition(!started && work.activeCount == 0 && !work.isCurrent(original),
			"Closing before queued work starts prevents the operation")

		var cancelled = false
		work.run { _ in
			started = true
			do { try await Task.sleep(for: .seconds(60)) }
			catch is CancellationError { cancelled = true }
			catch { preconditionFailure("Unexpected fixture error") }
		}
		await until { started }
		work.cancel()
		await until { cancelled }
		precondition(work.activeCount == 0, "Closing cancels pending cooperative work")

		let stale = Gate()
		var applied = false
		var staleFinished = false
		work.run { token in
			await stale.wait()
			if work.isCurrent(token) { applied = true }
			staleFinished = true
		}
		await until { stale.continuation != nil }
		work.cancel()
		let reopenedRevision = work.revision
		var reopenedApplied = false
		work.run { token in reopenedApplied = work.isCurrent(token) }
		stale.release()
		await until { reopenedApplied && staleFinished && work.activeCount == 0 }
		precondition(!applied && work.isCurrent(reopenedRevision),
			"Stale completion cannot change the newly opened flow")

		let first = Gate()
		let second = Gate()
		work.run { _ in await first.wait() }
		work.run { _ in await second.wait() }
		await until { first.continuation != nil && second.continuation != nil }
		precondition(work.activeCount == 2, "Camera and commit work are tracked independently")
		first.release()
		await until { work.activeCount == 1 }
		second.release()
		await until { work.activeCount == 0 }

		var lifetime: SetupSessionWork? = SetupSessionWork()
		var lifetimeStarted = false
		var lifetimeCancelled = false
		lifetime?.run { _ in
			lifetimeStarted = true
			do { try await Task.sleep(for: .seconds(60)) }
			catch is CancellationError { lifetimeCancelled = true }
			catch { preconditionFailure("Unexpected fixture error") }
		}
		await until { lifetimeStarted }
		lifetime = nil
		await until { lifetimeCancelled }
		print("PASS: setup close-before-start, pending-task cancellation, stale completion, reopen isolation, concurrent completion and teardown; no camera or owner-authentication UI.")
	}
}
