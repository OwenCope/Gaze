import AppKit
import Foundation
import Observation
import os

/// Checks GitHub Releases for a newer build.
///
/// **What survives an update, and what does not.**
///
/// Settings survive: they live in `UserDefaults` keyed to the bundle identifier, which is
/// untouched by replacing the application.
///
/// The enrolled face survives *only if the update is signed with the same certificate*.
/// Faceprints are sealed under a Secure Enclave key whose Keychain ACL is bound to the
/// app's code identity — a build signed by a different certificate is a different
/// application as far as macOS is concerned, and cannot open the vault. It would not
/// error, it would simply find nothing and ask the user to enrol again.
///
/// So this deliberately does not replace the app on its own. It tells the user a release
/// exists and opens it; installing is a step they take knowingly, because getting the
/// signing identity wrong silently costs them their enrolment.
@Observable
@MainActor
final class UpdateChecker {

	static let shared = UpdateChecker()

	/// Public API endpoint. Returns 404 while the repository is private, which is
	/// reported as "couldn't check" rather than "up to date" — claiming the latter
	/// without having looked would be worse than admitting we don't know.
	private static let releasesURL = URL(
		string: "https://api.github.com/repos/OwenCope/FaceID/releases/latest")!

	private static let logger = Logger(subsystem: "app.faceid.FaceID", category: "Updates")

	enum State: Equatable {
		case idle
		case checking
		case upToDate
		case available(version: String, url: URL)
		case failed(String)
	}

	private(set) var state: State = .idle

	var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
			?? "0"
	}

	private struct Release: Decodable {
		let tagName: String
		let htmlURL: URL

		enum CodingKeys: String, CodingKey {
			case tagName = "tag_name"
			case htmlURL = "html_url"
		}
	}

	func check() async {
		state = .checking

		do {
			var request = URLRequest(url: Self.releasesURL)
			request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
			request.timeoutInterval = 15

			let (data, response) = try await URLSession.shared.data(for: request)
			guard let http = response as? HTTPURLResponse else {
				state = .failed("No response from GitHub.")
				return
			}

			switch http.statusCode {
			case 200:
				let release = try JSONDecoder().decode(Release.self, from: data)
				let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

				if Self.isNewer(latest, than: currentVersion) {
					Self.logger.notice("Update available: \(latest).")
					state = .available(version: latest, url: release.htmlURL)
				} else {
					state = .upToDate
				}

			case 404:
				// Either no releases yet, or the repository is private.
				state = .failed("No releases published yet.")

			default:
				state = .failed("GitHub returned \(http.statusCode).")
			}
		} catch {
			state = .failed(error.localizedDescription)
		}
	}

	func openLatest() {
		guard case .available(_, let url) = state else { return }
		NSWorkspace.shared.open(url)
	}

	/// Compares dotted version strings numerically.
	///
	/// String comparison gets this wrong in the case that matters: "0.10" sorts before
	/// "0.9" lexically, so an update would be offered as a downgrade exactly when the
	/// project has shipped ten releases.
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
		let b = current.split(separator: ".").map { Int($0) ?? 0 }
		for i in 0..<max(a.count, b.count) {
			let left = i < a.count ? a[i] : 0
			let right = i < b.count ? b[i] : 0
			if left != right { return left > right }
		}
		return false
	}
}
