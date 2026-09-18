import Foundation

// Standalone lifecycle regression for ReleaseUpdateChecker scheduling.
//
// Compiled together with the real production files
// (Sources/App/ReleaseUpdateChecker.swift and ReleaseURLPolicy.swift), so
// this exercises the actual check/schedule code — not a stub of it. All
// responses come from StubFeedProtocol; no production request ever leaves the
// process. All persisted state lives in temporary UserDefaults suites that are
// removed afterwards; the owner's defaults and TipKit are never touched.

private enum LifecycleFailure: Error {
    case failed(String)
}

private let lastCheckKey = "lastReleaseCheck"

@MainActor
private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw LifecycleFailure.failed(message) }
    // Unbuffered, so passing checks survive in the log even if a later check traps.
    fputs("PASS \(message)\n", stderr)
}

@MainActor
private func waitUntil(
    _ description: String, timeout: TimeInterval = 30,
    diagnose: @MainActor () -> String = { "" }, _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date(timeIntervalSinceNow: timeout)
    var lastTrace = Date.distantPast
    while true {
        if condition() { return }
        if Date() > deadline { throw LifecycleFailure.failed("timed out waiting for \(description)") }
        if Date().timeIntervalSince(lastTrace) > 2 {
            lastTrace = Date()
            fputs("TRACE waiting for \(description) \(diagnose())\n", stderr)
        }
        // Sleep rather than spinning the runloop: yielding the main actor is
        // what lets the scheduled task and the session callbacks run.
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

@MainActor
private func rest(_ seconds: TimeInterval) async throws {
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - Stub network

/// URLProtocol stub backing every session the checker builds. Serves one
/// canned feed (or one canned error) and counts requests. A configurable delay
/// holds the response so a test can stop the schedule mid-flight; the delay
/// sleeps in slices and aborts promptly on stopLoading, reporting cancellation
/// the way a cancelled URLSession task does.
private final class StubFeedProtocol: URLProtocol {
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var requestCountValue = 0
    nonisolated(unsafe) private static var responseDelayValue: TimeInterval = 0
    nonisolated(unsafe) private static var responseStatusValue = 200
    nonisolated(unsafe) private static var responseBodyValue = Data()
    nonisolated(unsafe) private static var networkErrorValue: (any Error)?

    static var requestCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requestCountValue
    }

    static func configure(
        body: Data = Data(), status: Int = 200, delay: TimeInterval = 0,
        error: (any Error)? = nil
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        requestCountValue = 0
        responseBodyValue = body
        responseStatusValue = status
        responseDelayValue = delay
        networkErrorValue = error
    }

    private let stopLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.stateLock.lock()
        Self.requestCountValue += 1
        let delay = Self.responseDelayValue
        let status = Self.responseStatusValue
        let body = Self.responseBodyValue
        let error = Self.networkErrorValue
        Self.stateLock.unlock()

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let deadline = Date(timeIntervalSinceNow: delay)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            if isStopped {
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
                return
            }
        }
        if isStopped {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let url = request.url ?? ReleaseURLPolicy.feed
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
    }

    private var isStopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopped
    }
}

// MARK: - Fixtures

private func feedBody(tag: String = "9.9.9") -> Data {
    Data(
        ("{\"latest\":{\"tag\":\"\(tag)\",\"name\":\"T\",\"notes\":\"n\","
            + "\"download\":{\"url\":\"https://gazeunlock.com/releases/t.zip\"}}}").utf8)
}

private func stubbedConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubFeedProtocol.self]
    return configuration
}

@MainActor
private func makeChecker(startupDelay: Duration = .milliseconds(50)) throws -> (
    ReleaseUpdateChecker, UserDefaults, String
) {
    let suiteName = "com.gazeunlock.Gaze.UpdateLifecycleTests.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: suiteName) else {
        throw LifecycleFailure.failed("could not create suite \(suiteName)")
    }
    let checker = ReleaseUpdateChecker(
        defaults: suite, sessionConfiguration: stubbedConfiguration,
        startupDelay: startupDelay)
    return (checker, suite, suiteName)
}

private func removeSuite(_ suite: UserDefaults, named suiteName: String) {
    suite.removePersistentDomain(forName: suiteName)
}

@MainActor
private func isAvailable(_ checker: ReleaseUpdateChecker) -> Bool {
    if case .available = checker.state { return true }
    return false
}

// MARK: - Tests

@main
private enum UpdateLifecycleTests {
    static func main() async throws {
        try await warmUpURLSession()
        try await startTwiceIssuesOneRequest()
        try await stopBeforeDelayIssuesNoRequest()
        try await stopInFlightRestoresPriorState()
        try await restartAfterStop()
        try await independentInstances()
        try await ordinaryNetworkFailure()
        try await futureTimestampStillChecks()
        try await recentTimestampSkips()
        try await availableSkipsEvenWithFutureTimestamp()
        print("UpdateLifecycle regression checks passed")
    }

    @MainActor
    static func warmUpURLSession() async throws {
        // The first URLSession in a fresh process can take seconds to start
        // its task (daemon handshake); warm it once so per-test waits measure
        // the schedule, not process startup.
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        await checker.check()
        try require(isAvailable(checker), "warmup check reaches the stub feed")
    }

    @MainActor
    static func startTwiceIssuesOneRequest() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        checker.startScheduledChecks()
        checker.startScheduledChecks()
        try await waitUntil(
            "scheduled check to offer the update",
            diagnose: { "state=\(checker.state) requests=\(StubFeedProtocol.requestCount)" }
        ) { isAvailable(checker) }
        try require(StubFeedProtocol.requestCount == 1, "start-twice issues one request")
        try require(
            suite.object(forKey: lastCheckKey) is Date,
            "normal success schedules lastReleaseCheck")
        checker.stopScheduledChecks()
    }

    @MainActor
    static func stopBeforeDelayIssuesNoRequest() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker(startupDelay: .seconds(30))
        defer { removeSuite(suite, named: name) }
        checker.startScheduledChecks()
        checker.stopScheduledChecks()
        checker.stopScheduledChecks()
        try await rest(0.4)
        try require(StubFeedProtocol.requestCount == 0, "stop-before-delay issues no request")
        try require(checker.state == .idle, "stop-before-delay leaves state idle")
    }

    @MainActor
    static func stopInFlightRestoresPriorState() async throws {
        StubFeedProtocol.configure(body: feedBody(), delay: 10)
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        checker.startScheduledChecks()
        try await waitUntil("check to go in flight") { checker.state == .checking }
        try require(StubFeedProtocol.requestCount == 1, "in-flight check really started one request")
        checker.stopScheduledChecks()
        try await waitUntil("in-flight check to settle after stop") { checker.state != .checking }
        try require(checker.state == .idle, "stop in-flight restores prior idle, no false offline")
        try require(
            suite.object(forKey: lastCheckKey) == nil,
            "stop in-flight advances no timestamp")
        checker.stopScheduledChecks()
    }

    @MainActor
    static func restartAfterStop() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        checker.startScheduledChecks()
        checker.stopScheduledChecks()
        try await rest(0.2)
        try require(StubFeedProtocol.requestCount == 0, "stopped schedule issues no request")
        checker.startScheduledChecks()
        try await waitUntil("restarted check to offer the update") { isAvailable(checker) }
        try require(StubFeedProtocol.requestCount == 1, "restart after stop checks again")
        try require(
            suite.object(forKey: lastCheckKey) is Date,
            "restarted success schedules lastReleaseCheck")
        checker.stopScheduledChecks()
    }

    @MainActor
    static func independentInstances() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (first, firstSuite, firstName) = try makeChecker()
        defer { removeSuite(firstSuite, named: firstName) }
        let (second, secondSuite, secondName) = try makeChecker()
        defer { removeSuite(secondSuite, named: secondName) }
        first.startScheduledChecks()
        second.startScheduledChecks()
        try await waitUntil("both instances to offer the update") {
            isAvailable(first) && isAvailable(second)
        }
        try require(StubFeedProtocol.requestCount == 2, "two instances issue two requests")
        try require(
            firstSuite.object(forKey: lastCheckKey) is Date
                && secondSuite.object(forKey: lastCheckKey) is Date,
            "each instance schedules its own timestamp")
        try require(
            ReleaseUpdateChecker.shared.state == .idle, "schedule never touches .shared")
        first.stopScheduledChecks()
        second.stopScheduledChecks()
    }

    @MainActor
    static func ordinaryNetworkFailure() async throws {
        StubFeedProtocol.configure(error: URLError(.notConnectedToInternet))
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        await checker.check()
        try require(
            checker.state == .failed("Couldn't reach gazeunlock.com."),
            "ordinary network failure still reports offline")
        try require(
            suite.object(forKey: lastCheckKey) == nil, "failed check advances no timestamp")
    }

    @MainActor
    static func futureTimestampStillChecks() async throws {
        // A clock jump that leaves lastReleaseCheck in the future must not
        // suppress checks indefinitely: negative elapsed proceeds to check.
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        let future = Date(timeIntervalSinceNow: 60 * 60 * 24 * 30)
        suite.set(future, forKey: lastCheckKey)
        await checker.checkIfDue()
        try require(StubFeedProtocol.requestCount == 1, "future timestamp still checks once")
        try require(isAvailable(checker), "future timestamp check reaches the stub feed")
        guard let stored = suite.object(forKey: lastCheckKey) as? Date else {
            throw LifecycleFailure.failed("future timestamp success replaces lastReleaseCheck")
        }
        try require(stored < future, "future timestamp success replaces lastReleaseCheck")
        try require(
            abs(Date().timeIntervalSince(stored)) < 120,
            "replacement timestamp is current")
    }

    @MainActor
    static func recentTimestampSkips() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        suite.set(Date(), forKey: lastCheckKey)
        await checker.checkIfDue()
        try require(StubFeedProtocol.requestCount == 0, "recent timestamp still skips")
        try require(checker.state == .idle, "recent timestamp skip leaves state idle")
    }

    @MainActor
    static func availableSkipsEvenWithFutureTimestamp() async throws {
        StubFeedProtocol.configure(body: feedBody())
        let (checker, suite, name) = try makeChecker()
        defer { removeSuite(suite, named: name) }
        await checker.check()
        try require(isAvailable(checker), "available setup offers the update")
        try require(StubFeedProtocol.requestCount == 1, "available setup issues one request")
        suite.set(Date(timeIntervalSinceNow: 60 * 60 * 24 * 30), forKey: lastCheckKey)
        StubFeedProtocol.configure(body: feedBody())
        await checker.checkIfDue()
        try require(
            StubFeedProtocol.requestCount == 0,
            "available release skips automatic checks even with future timestamp")
        try require(isAvailable(checker), "available state survives a skipped due-check")
    }
}
