import SwiftUI

extension View {
	func glassSurface(cornerRadius: CGFloat) -> some View { self }
}
enum PasswordsBuild { static let isUIReview = true }

@main
struct WebsiteIconTests {
	@MainActor static func main() async throws {
		var checks = 0
		func check(_ value: Bool, _ name: String) {
			precondition(value, name)
			checks += 1
		}
		for site in ["https://127.0.0.1", "https://192.168.1.1", "https://[::1]", "https://printer.local", "https://host.internal",
			"https://example.test", "https://host.invalid", "https://host.home.arpa", "https://example.com:8443", "https://localhost"] {
			check(WebsiteIconPolicy.url(for: try BrowserOrigin(site)) == nil, "skip local or nonstandard origin")
		}
		let url = WebsiteIconPolicy.url(for: try BrowserOrigin("https://example.com"))
		check(url?.absoluteString == "https://example.com/favicon.ico", "only fixed path on exact origin")
		let googleOrigin = try BrowserOrigin("https://accounts.google.com")
		check(WebsiteIconPolicy.fallbackURL(for: googleOrigin)?.absoluteString == "https://www.google.com/favicon.ico", "explicit Google Accounts icon fallback")
		for site in ["https://example.com", "https://accounts.google.com.evil.com", "https://evilgoogle.com", "https://accounts.google.com:8443", "https://mail.google.com"] {
			check(WebsiteIconPolicy.fallbackURL(for: try BrowserOrigin(site)) == nil, "no inferred parent or lookalike fallback")
		}
		for address: [UInt8] in [[127, 0, 0, 1], [10, 1, 2, 3], [172, 16, 1, 1], [172, 31, 255, 255], [192, 168, 1, 1],
			[169, 254, 1, 1], [100, 64, 0, 1], [100, 127, 255, 255], [198, 18, 0, 1], [198, 19, 255, 255],
			[224, 0, 0, 1], [255, 255, 255, 255], [0, 0, 0, 0], [192, 0, 2, 1], [198, 51, 100, 1], [203, 0, 113, 1]] {
			check(!WebsiteIconPolicy.isPublicIPv4(address), "nonpublic address rejected")
		}
		check(WebsiteIconPolicy.isPublicIPv4([8, 8, 8, 8]), "public address accepted without contacting it")
		check(!WebsiteIconPolicy.isPublicIPv4([]), "missing address rejected")
		check(WebsiteIconPolicy.validImageDimensions(width: 128, height: 128, frames: 1), "normal icon accepted")
		for dimensions in [(0, 128, 1), (128, 0, 1), (4097, 128, 1), (128, 4097, 1), (128, 128, 0), (128, 128, 33)] {
			check(!WebsiteIconPolicy.validImageDimensions(width: dimensions.0, height: dimensions.1, frames: dimensions.2), "oversized or malformed image rejected")
		}
		for address in ["::1", "::ffff:8.8.8.8", "64:ff9b::808:808", "2001:db8::1", "2001::1", "2002:0808:0808::1", "3ffe::1", "3fff::1", "fc00::1", "fe80::1%en0", "ff02::1", "192.0.0.1", "192.88.99.1", "example.com"] {
			check(PublicIconAddress(address) == nil, "reject special-use or nonnumeric address: \(address)")
		}
		for address in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "2001:4860:4860::8888"] {
			check(PublicIconAddress(address) != nil, "accept global numeric address: \(address)")
		}
		func rejects(_ operation: () throws -> Void) -> Bool {
			do { try operation(); return false } catch { return true }
		}
		let request = String(decoding: try PinnedWebsiteIconRequest.requestData(hostname: "example.com"), as: UTF8.self)
		check(request.hasPrefix("GET /favicon.ico HTTP/1.1\r\nHost: example.com\r\n"), "exact-origin fixed request")
		check(!request.contains("Cookie:") && !request.contains("Authorization:") && !request.contains("Referer:"), "no credential or browsing context headers")
		for host in ["example.com\r\nCookie: secret", "user@example.com", "example.com/path", "localhost", "127.0.0.1", "example.com:8443"] {
			check(rejects { _ = try PinnedWebsiteIconRequest.requestData(hostname: host) }, "reject injected or unsafe host")
		}
		let publicAddress = PublicIconAddress("8.8.8.8")!
		for url in ["http://example.com/favicon.ico", "https://example.com/other", "https://example.com/favicon.ico?token=x", "https://user@example.com/favicon.ico", "https://example.com:8443/favicon.ico"] {
			check(rejects { _ = try PinnedWebsiteIconRequest(url: URL(string: url)!, address: publicAddress) }, "reject noncanonical icon URL")
		}
		let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n"
		let payload = Data([0, 1, 255, 128])
		let fixed = Data((header + "Content-Length: 4\r\n\r\n").utf8) + payload
		let chunked = Data((header + "Transfer-Encoding: chunked\r\n\r\n2\r\n").utf8) + payload.prefix(2)
			+ Data("\r\n2;extension=yes\r\n".utf8) + payload.suffix(2) + Data("\r\n0\r\n\r\n".utf8)
		let trailers = Data((header + "Transfer-Encoding: chunked\r\n\r\n4\r\n").utf8) + payload + Data("\r\n0\r\nX-Example: ok\r\n\r\n".utf8)
		for wire in [fixed, chunked, trailers] {
			check(try WebsiteIconHTTPResponse.decode(wire, ended: false) == payload, "complete body without connection close")
			check(try WebsiteIconHTTPResponse.decode(wire, ended: true) == payload, "complete body at close")
			for prefix in 0..<wire.count {
				check(try WebsiteIconHTTPResponse.decode(Data(wire.prefix(prefix)), ended: false) == nil, "fragmented response waits")
				check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data(wire.prefix(prefix)), ended: true) }, "truncated response rejected")
			}
		}
		let closeDelimited = Data((header + "\r\n").utf8) + payload
		check(try WebsiteIconHTTPResponse.decode(closeDelimited, ended: false) == nil, "unframed waits for EOF")
		check(try WebsiteIconHTTPResponse.decode(closeDelimited, ended: true) == payload, "unframed completes at EOF")
		let invalid = [
			"HTTP/1.1 302 Found\r\nContent-Type: image/png\r\n\r\nx",
			"HTTP/1.1 401 Unauthorized\r\nContent-Type: image/png\r\n\r\nx",
			"HTTP/2 200 OK\r\nContent-Type: image/png\r\n\r\nx",
			"HTTP/1.1 200\r\nContent-Type: image/png\r\n\r\nx",
			"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nx",
			header + "Content-Type: image/jpeg\r\n\r\nx",
			header + "Content-Encoding: gzip\r\n\r\nx",
			header + "Content-Length: 1\r\nContent-Length: 1\r\n\r\nx",
			header + "Content-Length: -1\r\n\r\nx",
			header + "Content-Length: 0\r\n\r\n",
			header + "Content-Length: 999999999999999999999999\r\n\r\nx",
			header + "Content-Length: 1\r\n\r\nxx",
			header + "Transfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n",
			header + "Transfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\nx",
			header + "Bad Name: value\r\n\r\nx",
			header + "X-Test: bad\u{0}value\r\n\r\nx",
			header + "\r\n"
		]
		for wire in invalid {
			check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data(wire.utf8), ended: true) }, "invalid status, type or framing rejected")
		}
		for chunks in ["0\r\n\r\n", "-1\r\nx\r\n0\r\n\r\n", "z\r\nx\r\n0\r\n\r\n", "1\r\nxXX0\r\n\r\n", "1;bad\u{0}\r\nx\r\n0\r\n\r\n", "1\r\nx\r\n0\r\n\r\nextra", "1\r\nx\r\n0\r\nBad Trailer\r\n\r\n", "1\r\nx\r\n0\r\nContent-Length: 1\r\n\r\n", "40001\r\n", "FFFFFFFFF\r\n"] {
			check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data((header + "Transfer-Encoding: chunked\r\n\r\n" + chunks).utf8), ended: true) }, "malformed chunked response rejected")
		}
		check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data(repeating: 65, count: 16_385), ended: false) }, "header size limit")
		check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data(repeating: 65, count: WebsiteIconHTTPResponse.maximumWireBytes + 1), ended: false) }, "wire size limit")
		check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data((header + "\r\n").utf8) + Data(repeating: 1, count: WebsiteIconPolicy.maximumBytes + 1), ended: true) }, "body size limit")
		let tooManyChunks = header + "Transfer-Encoding: chunked\r\n\r\n" + String(repeating: "1\r\nx\r\n", count: 4096) + "0\r\n\r\n"
		check(rejects { _ = try WebsiteIconHTTPResponse.decode(Data(tooManyChunks.utf8), ended: true) }, "chunk count limit")
		var loads: [String] = []
		var continuations: [CheckedContinuation<NSImage?, Never>] = []
		let cache = WebsiteIconCache { url in
			loads.append(url.host!)
			return await withCheckedContinuation { continuations.append($0) }
		}
		func waitForLoads(_ count: Int) async {
			for _ in 0..<500 where loads.count < count { try? await Task.sleep(for: .milliseconds(2)) }
			check(loads.count == count, "expected bounded request started")
		}
		let fixture = NSImage(size: NSSize(width: 16, height: 16))
		var fallbackLoads: [String] = []
		let fallbackCache = WebsiteIconCache { url in
			fallbackLoads.append(url.absoluteString)
			return url.host == "www.google.com" ? fixture : nil
		}
		check(await fallbackCache.image(for: googleOrigin) === fixture, "account icon uses explicit fallback after direct failure")
		check(fallbackLoads == ["https://accounts.google.com/favicon.ico", "https://www.google.com/favicon.ico"], "only approved URLs requested")
		check(await fallbackCache.image(for: googleOrigin) === fixture && fallbackLoads.count == 2, "fallback image cached under original origin")
		var directLoads = 0
		let directCache = WebsiteIconCache { _ in directLoads += 1; return fixture }
		check(await directCache.image(for: googleOrigin) === fixture && directLoads == 1, "no fallback when direct icon succeeds")
		let firstOrigin = try BrowserOrigin("https://example.com")
		let first = Task { await cache.image(for: firstOrigin) }
		await waitForLoads(1)
		let shared = Task { await cache.image(for: firstOrigin) }
		await Task.yield()
		first.cancel()
		continuations[0].resume(returning: fixture)
		check(await first.value == nil, "cancelled row receives no image")
		check(await shared.value === fixture, "shared request survives row cancellation")
		check(await cache.image(for: firstOrigin) === fixture, "completed shared request cached")
		check(loads.count == 1, "same origin coalesced")
		for index in 1...5 {
			let origin = try BrowserOrigin("https://site\(index).example.com")
			let pending = Task { await cache.image(for: origin) }
			await waitForLoads(index + 1)
			pending.cancel()
			continuations[index].resume(returning: nil)
			check(await pending.value == nil, "cancelled request finishes without exhausting slots")
		}
		cache.clear()
		let old = Task { await cache.image(for: firstOrigin) }
		await waitForLoads(7)
		cache.clear()
		let fresh = Task { await cache.image(for: firstOrigin) }
		await waitForLoads(8)
		continuations[6].resume(returning: fixture)
		check(await old.value == nil, "lock invalidates in-flight image")
		continuations[7].resume(returning: fixture)
		check(await fresh.value === fixture, "old completion cannot remove new generation request")
		cache.clear()
		var gatedLoads: [String] = []
		var gatedGates: [CheckedContinuation<NSImage?, Never>] = []
		let gatedCache = WebsiteIconCache { url in
			gatedLoads.append(url.absoluteString)
			return await withCheckedContinuation { gatedGates.append($0) }
		}
		func waitForGatedLoads(_ count: Int) async {
			for _ in 0..<500 where gatedLoads.count < count { try? await Task.sleep(for: .milliseconds(2)) }
			check(gatedLoads.count == count, "expected bounded gated request started")
		}
		actor GateResult {
			var value: NSImage?? = nil
			func set(_ image: NSImage?) { value = image }
			func get() -> NSImage?? { value }
		}
		func boundedImage(_ task: Task<NSImage?, Never>) async -> NSImage?? {
			let box = GateResult()
			Task { await box.set(await task.value) }
			for _ in 0..<1000 {
				if let result = await box.get() { return result }
				try? await Task.sleep(for: .milliseconds(2))
			}
			return nil
		}
		let cachedOrigin = try BrowserOrigin("https://cached.example.com")
		let seed = Task { await gatedCache.image(for: cachedOrigin) }
		await waitForGatedLoads(1)
		gatedGates[0].resume(returning: fixture)
		check(await seed.value === fixture, "seed icon cached")
		check(gatedLoads.count == 1, "seed performed one network load")
		var held: [Task<NSImage?, Never>] = []
		for index in 1...4 {
			let origin = try BrowserOrigin("https://held\(index).example.com")
			held.append(Task { await gatedCache.image(for: origin) })
			await waitForGatedLoads(index + 1)
		}
		let cachedLookup = Task { await gatedCache.image(for: cachedOrigin) }
		let gatedResult = await boundedImage(cachedLookup)
		check(gatedResult != nil, "cached icon resolves while download slots are full")
		check((gatedResult ?? nil) === fixture, "cached icon returns seeded image without new load")
		check(gatedLoads.count == 5, "cached lookup performs no network load")
		let cancelledLookup = Task { await gatedCache.image(for: cachedOrigin) }
		cancelledLookup.cancel()
		let cancelledResult = await boundedImage(cancelledLookup)
		check(cancelledResult != nil, "cancelled cached lookup finishes while slots are full")
		check(cancelledResult! == nil, "cancelled cached lookup returns nil")
		check(gatedLoads.count == 5, "cancelled cached lookup performs no network load")
		for gate in gatedGates.suffix(4) { gate.resume(returning: nil) }
		for task in held { check(await task.value == nil, "held request finishes after gates released") }
		print("Website icon policy, parser and cache: \(checks) checks passed. No network or vault accessed.")
	}
}
