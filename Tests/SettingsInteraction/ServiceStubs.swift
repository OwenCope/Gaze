import Foundation
import Observation
import AVFoundation
import SwiftUI

@MainActor enum FixtureCameraAuthorization {
    static func authorizationStatus(for _: AVMediaType) -> AVAuthorizationStatus { .authorized }
    static func requestAccess(for _: AVMediaType, completionHandler: @escaping (Bool) -> Void) {
        fatalError("Capture recovery fixtures must never request camera permission")
    }
}

@MainActor final class FixtureDriver {
    var changeLoginItem: ((Bool) -> Void)?
    var refresh: (() -> Void)?
}

@Observable @MainActor final class Preferences {
    static let shared = Preferences()
    var tamperProtection = false
}

@MainActor enum LoginItem {
    enum Status { case disabled, enabled, requiresApproval }
    static var status = Status.disabled
    static var failNext = false
    static var approvalNext = false
    static var requests: [Bool] = []
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }
    static func setEnabled(_ enabled: Bool) -> Bool {
        requests.append(enabled)
        if failNext { failNext = false; return false }
        status = enabled ? (approvalNext ? .requiresApproval : .enabled) : .disabled
        return true
    }
}

@MainActor enum SMAppService {
    static var openCount = 0
    static func openSystemSettingsLoginItems() { openCount += 1 }
}

/// The app renamed this to `RepoRevealHelper`; the stub keeps the old name the tests use.
typealias RepoRevealHelper = UpdateChecker

@Observable @MainActor final class UpdateChecker {
    static let shared = UpdateChecker()
    var repositoryURL: URL?
    let currentVersion = "1.2.3"
    var revealCount = 0
    func revealRepository() { revealCount += 1 }
}

@Observable @MainActor final class ReleaseUpdateChecker {
    static let shared = ReleaseUpdateChecker()
    struct Release: Equatable {
        let tag: String
        let name: String
        let notes: String
        var downloadURL: URL? = URL(string: "https://gazeunlock.com/dl/Gaze.dmg")
    }
    enum State: Equatable {
        case idle, checking, upToDate, available(Release), failed(String)
    }
    var state = State.idle
    var checkCount = 0
    var downloadCount = 0
    func check() async { checkCount += 1; state = .upToDate }
    func openDownload() { downloadCount += 1 }
    let installer = UpdateInstaller()
    var installCount = 0
    func install() { installCount += 1 }
}

@Observable @MainActor final class UpdateInstaller {
    enum State: Equatable {
        case idle, downloading(fraction: Double), installing, failed(String)
    }
    var state = State.idle
}

/// The camera-access figure draws the Metal companion; the fixture only needs its layout.
struct GazeLookingCompanion: View {
    var look: Double
    var happy: Bool
    var body: some View { Circle().fill(.white.opacity(0.2)) }
}
