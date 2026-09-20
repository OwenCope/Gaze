import Foundation

enum ReleaseURLPolicy {
	static let feed = URL(string: "https://gazeunlock.com/api/latest")!
	static let releases = URL(string: "https://gazeunlock.com/releases")!
	static let maximumFeedBytes = 512 * 1024

	static func isTrusted(_ url: URL) -> Bool {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			components.scheme?.lowercased() == "https",
			components.host?.lowercased() == "gazeunlock.com",
			components.user == nil, components.password == nil,
			components.port == nil || components.port == 443,
			components.fragment == nil else { return false }
		return true
	}

	static func download(_ value: String?) -> URL? {
		guard let value, value.utf8.count <= 4096, let url = URL(string: value), isTrusted(url) else { return nil }
		return url
	}

	static func sessionConfiguration() -> URLSessionConfiguration {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		configuration.urlCache = nil
		configuration.timeoutIntervalForRequest = 12
		configuration.timeoutIntervalForResource = 20
		return configuration
	}
}

final class ReleaseFeedRedirectPolicy: NSObject, URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
		guard let url = request.url, ReleaseURLPolicy.isTrusted(url) else {
			completionHandler(nil)
			return
		}
		completionHandler(request)
	}
}
