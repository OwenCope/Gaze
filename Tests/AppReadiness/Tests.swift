import Foundation
import Synchronization
import Testing
@testable import GazeReadiness

@Suite @MainActor
struct ReleaseVersions {
    @Test(arguments: [
        ("1.0.0", "1.0.0-beta.1", true),
        ("1.0.0-beta.2", "1.0.0", false),
        ("1.0.0+2", "1.0.0+1", false),
        ("1.0.0-beta.1+2", "1.0.0-beta.1+1", false),
        ("0.10", "0.9", true), ("0.9", "0.10", false),
        (" V2.0.0 ", "v1.9", true), ("1.2", "1.2.0", false),
        ("1.2.0", "1.2", false), ("1", "1.0.0", false),
        ("2.0.0-alpha", "1.99.99", true),
        ("1.0.0-beta.10", "1.0.0-beta.9", true),
        ("1.0.0-alpha", "1.0.0-9", true),
        ("1.0.0-alpha.1", "1.0.0-alpha", true),
        ("1.0.0-beta", "1.0.0-alpha.9", true),
        ("1.0.0-alpha", "1.0.0-Alpha", true),
        ("1.0.0-rc-2", "1.0.0-rc-1", true),
        ("1.0.0+0001", "1.0.0", false),
        ("999999999999999999999999999999.0", "2", true),
        ("1.0.0-999999999999999999999999999999", "1.0.0-999999999999999999999999999998", true)
    ])
    func precedence(_ candidate: String, _ current: String, _ expected: Bool) {
        #expect(ReleaseUpdateChecker.isNewer(candidate, than: current) == expected)
    }

    @Test(arguments: ["", "v", ".", "1..2", "1.2.", "01.2.3", "1.2beta", "1.2.3.4",
                      "1.0.0-", "1.0.0-beta..1", "1.0.0-01", "1.0.0-β", "1.0.0-rc_1",
                      "1.0.0+", "1.0.0+a..b", "1.0.0+a+b", "١.0.0", "vv1.2.3"])
    func malformedVersions(_ invalid: String) {
        #expect(!ReleaseUpdateChecker.isNewer(invalid, than: "0"))
        #expect(!ReleaseUpdateChecker.isNewer("999", than: invalid))
    }

    @Test func semanticVersionSequence() {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                       "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for (index, older) in ordered.enumerated() {
            for newer in ordered.dropFirst(index + 1) {
                #expect(ReleaseUpdateChecker.isNewer(newer, than: older))
                #expect(!ReleaseUpdateChecker.isNewer(older, than: newer))
            }
        }
    }
}

struct WallpaperRequests {
    let a = URL(fileURLWithPath: "/test/wallpaper-a.png")
    let b = URL(fileURLWithPath: "/test/wallpaper-b.png")
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func coalescesPendingAndLoadedRequests() throws {
        var gate = WallpaperLoadGate()
        let initialRequest = gate.request(for: a, now: now)
        let request = try #require(initialRequest)
        let duplicateCoalesced = gate.request(for: a, now: now) == nil
        #expect(duplicateCoalesced)
        let completed = gate.complete(request, succeeded: true, now: now)
        #expect(completed)
        let cached = gate.request(for: a, now: now) == nil
        #expect(cached)
    }

    @Test func newerSelectionRejectsLateCompletion() throws {
        var gate = WallpaperLoadGate()
        let firstRequest = gate.request(for: a, now: now)
        let first = try #require(firstRequest)
        let latestRequest = gate.request(for: b, now: now)
        let latest = try #require(latestRequest)
        let oldRejected = !gate.complete(first, succeeded: true, now: now)
        #expect(oldRejected)
        #expect(gate.pendingRequest == latest)
        let latestAccepted = gate.complete(latest, succeeded: true, now: now)
        #expect(latestAccepted)
    }

    @Test func returningToCachedWallpaperInvalidatesPendingWork() throws {
        var gate = WallpaperLoadGate()
        let firstRequest = gate.request(for: a, now: now)
        let first = try #require(firstRequest)
        let firstAccepted = gate.complete(first, succeeded: true, now: now)
        #expect(firstAccepted)
        let pendingRequest = gate.request(for: b, now: now)
        let pending = try #require(pendingRequest)
        let cacheReused = gate.request(for: a, now: now) == nil
        #expect(cacheReused)
        #expect(gate.pendingRequest == nil)
        let pendingRejected = !gate.complete(pending, succeeded: true, now: now)
        #expect(pendingRejected)
        let stillCached = gate.request(for: a, now: now) == nil
        #expect(stillCached)
    }

    @Test func failureRetriesAtTenSeconds() throws {
        var gate = WallpaperLoadGate()
        let initialRequest = gate.request(for: a, now: now)
        let request = try #require(initialRequest)
        let failureRecorded = gate.complete(request, succeeded: false, now: now)
        #expect(failureRecorded)
        let cooldownActive = gate.request(for: a, now: now.addingTimeInterval(9.99)) == nil
        #expect(cooldownActive)
        let retryRequest = gate.request(for: a, now: now.addingTimeInterval(10))
        let retry = try #require(retryRequest)
        #expect(retry != request)
        let retrySucceeded = gate.complete(retry, succeeded: true, now: now.addingTimeInterval(10))
        #expect(retrySucceeded)
        let successCached = gate.request(for: a, now: now.addingTimeInterval(20)) == nil
        #expect(successCached)
    }

    @Test func failedOldRequestCannotPoisonNewSelection() throws {
        var gate = WallpaperLoadGate()
        let oldRequest = gate.request(for: a, now: now)
        let old = try #require(oldRequest)
        let latestRequest = gate.request(for: b, now: now)
        let latest = try #require(latestRequest)
        let oldFailureRejected = !gate.complete(old, succeeded: false, now: now)
        #expect(oldFailureRejected)
        let newAccepted = gate.complete(latest, succeeded: true, now: now)
        #expect(newAccepted)
        let oldCanRetry = gate.request(for: a, now: now) != nil
        #expect(oldCanRetry)
    }

    @Test func cooldownSurvivesOtherSelections() throws {
        var gate = WallpaperLoadGate()
        let failedRequest = gate.request(for: a, now: now)
        let failed = try #require(failedRequest)
        let failureRecorded = gate.complete(failed, succeeded: false, now: now)
        #expect(failureRecorded)
        let pendingRequest = gate.request(for: b, now: now)
        let pending = try #require(pendingRequest)
        let cooldownActive = gate.request(for: a, now: now.addingTimeInterval(1)) == nil
        #expect(cooldownActive)
        let pendingRejected = !gate.complete(pending, succeeded: true, now: now)
        #expect(pendingRejected)
        let cooldownExpired = gate.request(for: a, now: now.addingTimeInterval(10)) != nil
        #expect(cooldownExpired)
    }

    @Test func resetRejectsOutstandingCompletionEvenForSameURL() throws {
        var gate = WallpaperLoadGate()
        let oldRequest = gate.request(for: a, now: now)
        let old = try #require(oldRequest)
        gate.reset()
        let freshRequest = gate.request(for: a, now: now)
        let fresh = try #require(freshRequest)
        #expect(fresh != old)
        let oldRejected = !gate.complete(old, succeeded: true, now: now)
        #expect(oldRejected)
        let freshAccepted = gate.complete(fresh, succeeded: true, now: now)
        #expect(freshAccepted)
    }
}

// This protocol intercepts every request from the test configuration; nothing reaches a server.
private final class FeedProtocol: URLProtocol, @unchecked Sendable {
    struct Requests {
        var pending: [FeedProtocol] = []
        var count = 0
    }
    static let requests = Mutex(Requests())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.pending.append(self); $0.count += 1 }
    }
    override func stopLoading() {}

    static func finish(_ body: String?, status: Int = 200) {
        let pending = requests.withLock { state in
            let result = state.pending
            state.pending.removeAll()
            return result
        }
        for request in pending {
            guard let body else {
                request.client?.urlProtocol(request, didFailWithError: URLError(.notConnectedToInternet))
                continue
            }
            let response = HTTPURLResponse(url: ReleaseURLPolicy.feed, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
            request.client?.urlProtocol(request, didLoad: Data(body.utf8))
            request.client?.urlProtocolDidFinishLoading(request)
        }
    }
}

@Suite(.serialized) @MainActor
struct ReleaseScheduling {
    private func withChecker(_ body: @MainActor (ReleaseUpdateChecker, UserDefaults) async throws -> Void) async throws {
        let suite = "Gaze.ReadinessRegression.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        FeedProtocol.requests.withLock { $0 = .init() }
        let checker = ReleaseUpdateChecker(defaults: defaults) {
            let configuration = ReleaseURLPolicy.sessionConfiguration()
            configuration.protocolClasses = [FeedProtocol.self]
            return configuration
        }
        try await body(checker, defaults)
    }

    private func waitForRequest() async throws {
        for _ in 0..<200 {
            if FeedProtocol.requests.withLock({ !$0.pending.isEmpty }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }

    @Test func overlapDoesNotPostponeRetryAfterFailure() async throws {
        try await withChecker { checker, defaults in
            let first = Task { await checker.check() }
            try await waitForRequest()
            await checker.checkIfDue()
            #expect(checker.state == .checking)
            #expect(defaults.object(forKey: "lastReleaseCheck") == nil)
            #expect(FeedProtocol.requests.withLock { $0.count } == 1)
            FeedProtocol.finish(nil)
            await first.value
            guard case .failed = checker.state else { Issue.record("Expected an offline failure"); return }
            #expect(defaults.object(forKey: "lastReleaseCheck") == nil)

            let retry = Task { await checker.checkIfDue() }
            try await waitForRequest()
            #expect(FeedProtocol.requests.withLock { $0.count } == 2)
            FeedProtocol.finish("{\"latest\":null}")
            await retry.value
            #expect(checker.state == .upToDate)
            #expect(defaults.object(forKey: "lastReleaseCheck") is Date)
            await checker.checkIfDue()
            #expect(FeedProtocol.requests.withLock { $0.count } == 2)
        }
    }

    @Test func manualSuccessCountsTowardDailySchedule() async throws {
        try await withChecker { checker, defaults in
            let check = Task { await checker.check() }
            try await waitForRequest()
            FeedProtocol.finish("{\"latest\":null}")
            await check.value
            #expect(defaults.object(forKey: "lastReleaseCheck") is Date)
            await checker.checkIfDue()
            #expect(FeedProtocol.requests.withLock { $0.count } == 1)
        }
    }

    @Test(arguments: ["1..2", "1.0.0-", "1.2garbage"])
    func invalidFeedVersionDoesNotClaimUpToDate(_ tag: String) async throws {
        try await withChecker { checker, defaults in
            let check = Task { await checker.checkIfDue() }
            try await waitForRequest()
            FeedProtocol.finish("{\"latest\":{\"tag\":\"\(tag)\",\"name\":\"Test\",\"notes\":\"\"}}")
            await check.value
            #expect(checker.state == .failed("Couldn't read the release version."))
            #expect(defaults.object(forKey: "lastReleaseCheck") == nil)
        }
    }
}
