import AppKit
import Darwin
import ImageIO
import SwiftUI

enum WebsiteIconPolicy {
	static let maximumBytes = 262_144
	static func validImageDimensions(width: Int, height: Int, frames: Int) -> Bool {
		(1...4096).contains(width) && (1...4096).contains(height) && (1...32).contains(frames)
	}
	static func url(for origin: BrowserOrigin) -> URL? {
		guard var parts = URLComponents(string: origin.value), let host = parts.host,
			parts.port == nil, host.contains("."), ![".local", ".localhost", ".internal", ".test", ".invalid", ".home.arpa"].contains(where: host.hasSuffix),
			!host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
		parts.path = "/favicon.ico"
		return parts.url
	}
	static func fallbackURL(for origin: BrowserOrigin) -> URL? {
		guard origin.value == "https://accounts.google.com" else { return nil }
		return URL(string: "https://www.google.com/favicon.ico")
	}
	static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
		guard bytes.count == 4 else { return false }
		return ![0, 10, 127].contains(bytes[0]) && bytes[0] < 224
			&& !(bytes[0] == 169 && bytes[1] == 254)
			&& !(bytes[0] == 172 && (16...31).contains(bytes[1]))
			&& !(bytes[0] == 192 && bytes[1] == 168)
			&& !(bytes[0] == 100 && (64...127).contains(bytes[1]))
			&& !(bytes[0] == 198 && (18...19).contains(bytes[1]))
			&& !(bytes[0] == 192 && bytes[1] == 0 && [0, 2].contains(bytes[2]))
			&& !(bytes[0] == 192 && bytes[1] == 88 && bytes[2] == 99)
			&& !(bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100)
			&& !(bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113)
	}
	static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
		guard bytes.count == 16, bytes[0] & 0xe0 == 0x20 else { return false }
		return !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2)
			&& !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
			&& !(bytes[0] == 0x20 && bytes[1] == 0x02)
			&& !(bytes[0] == 0x3f && bytes[1] == 0xfe)
			&& !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] < 0x10)
	}
	static func publicAddresses(_ host: String) -> [PublicIconAddress] {
		var hints = addrinfo()
		hints.ai_socktype = SOCK_STREAM
		var result: UnsafeMutablePointer<addrinfo>?
		guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
		defer { freeaddrinfo(first) }
		var current: UnsafeMutablePointer<addrinfo>? = first
		var addresses: [PublicIconAddress] = []
		while let address = current {
			guard let socketAddress = address.pointee.ai_addr, [AF_INET, AF_INET6].contains(address.pointee.ai_family), addresses.count < 32 else { return [] }
			var numeric = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			guard getnameinfo(socketAddress, address.pointee.ai_addrlen, &numeric, socklen_t(numeric.count), nil, 0, NI_NUMERICHOST) == 0,
				let endpoint = PublicIconAddress(String(cString: numeric)) else { return [] }
			if !addresses.contains(endpoint) { addresses.append(endpoint) }
			current = address.pointee.ai_next
		}
		return addresses
	}
}

@MainActor
final class WebsiteIconCache: ObservableObject {
	static let shared = WebsiteIconCache()
	private var images: [BrowserOrigin: NSImage] = [:]
	private var attempted = Set<BrowserOrigin>()
	private var requests: [BrowserOrigin: Task<NSImage?, Never>] = [:]
	@Published private(set) var generation = UUID()
	private let load: @MainActor (URL) async -> NSImage?
	init(load: @escaping @MainActor (URL) async -> NSImage? = { await WebsiteIconCache.download($0) }) {
		self.load = load
	}
	func clear() {
		generation = UUID()
		requests.values.forEach { $0.cancel() }
		requests = [:]; images = [:]; attempted = []
	}
	func image(for origin: BrowserOrigin) async -> NSImage? {
		let token = generation
		guard !Task.isCancelled else { return nil }
		if let image = images[origin] { return image }
		if attempted.contains(origin), requests[origin] == nil { return nil }
		while requests.count >= 4 && requests[origin] == nil {
			do { try await Task.sleep(for: .milliseconds(80)) } catch { return nil }
			guard generation == token else { return nil }
		}
		guard !Task.isCancelled, generation == token else { return nil }
		if let image = images[origin] { return image }
		if let request = requests[origin] {
			let image = await request.value
			return generation == token && !Task.isCancelled ? image : nil
		}
		guard !attempted.contains(origin), attempted.count < 1000, let url = WebsiteIconPolicy.url(for: origin) else { return nil }
		attempted.insert(origin)
		let task = Task<NSImage?, Never> {
			if let image = await load(url) { return image }
			guard !Task.isCancelled, let fallback = WebsiteIconPolicy.fallbackURL(for: origin) else { return nil }
			return await load(fallback)
		}
		requests[origin] = task
		let image = await task.value
		guard generation == token else { return nil }
		requests[origin] = nil
		images[origin] = image
		return Task.isCancelled ? nil : image
	}
	private static func download(_ url: URL) async -> NSImage? {
		guard let host = url.host else { return nil }
		let addresses = await Task.detached(priority: .utility) { WebsiteIconPolicy.publicAddresses(host) }.value
		guard let address = addresses.first, !Task.isCancelled else { return nil }
		do {
			let data = try await PinnedWebsiteIconRequest(url: url, address: address).data()
			try Task.checkCancellation()
			guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
				let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
				let width = properties[kCGImagePropertyPixelWidth] as? Int,
				let height = properties[kCGImagePropertyPixelHeight] as? Int,
				WebsiteIconPolicy.validImageDimensions(width: width, height: height, frames: CGImageSourceGetCount(source)),
				let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
			return NSImage(cgImage: thumbnail, size: NSSize(width: 48, height: 48))
		} catch { return nil }
	}
}

struct WebsiteIcon: View {
	let origin: BrowserOrigin
	var size: CGFloat = 34
	@AppStorage("passwords.downloadWebsiteIcons") private var enabled = false
	@State private var image: NSImage?
	@ObservedObject private var cache = WebsiteIconCache.shared
	private var host: String { URLComponents(string: origin.value)?.host ?? "" }
	var body: some View {
		Group {
			if let image, enabled { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.15) }
			else if let first = host.first, first.isLetter { Text(String(first).uppercased()).font(.system(size: size * 0.48, weight: .semibold, design: .rounded)) }
			else { Image(systemName: "network").font(.system(size: size * 0.45)) }
		}.frame(width: size, height: size).glassSurface(cornerRadius: size * 0.28).accessibilityHidden(true)
		.task(id: "\(origin.value)-\(enabled)-\(cache.generation)") {
			image = nil
			guard enabled, !PasswordsBuild.isUIReview else { return }
			let loaded = await cache.image(for: origin)
			guard !Task.isCancelled else { return }
			image = loaded
		}
	}
}
