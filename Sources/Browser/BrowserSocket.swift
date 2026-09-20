import Darwin
import Foundation

final class BrowserSocket: @unchecked Sendable {
	private let lock = NSLock()
	private var descriptor: Int32
	static let maximumMessageBytes = 65_536

	init(descriptor: Int32) {
		self.descriptor = descriptor
		let flags = fcntl(descriptor, F_GETFL)
		if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
		var noSignal: Int32 = 1
		setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
		var timeout = timeval(tv_sec: 90, tv_usec: 0)
		setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
		setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
	}

	deinit { close() }

	func close() {
		lock.lock()
		let previous = descriptor
		descriptor = -1
		lock.unlock()
		if previous >= 0 { shutdown(previous, SHUT_RDWR); Darwin.close(previous) }
	}

	func verifyPeer(identifier: String) throws {
		try withDescriptor { try BrowserPeerTrust.verify(socket: $0, identifier: identifier) }
	}

	var isConnected: Bool {
		(try? withDescriptor { descriptor in
			var byte: UInt8 = 0
			let result = recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
			return result > 0 || (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
		}) ?? false
	}

	func read() throws -> BrowserMessage {
		try withDescriptor { descriptor in
			let lengthData = try Self.readExactly(4, from: descriptor)
			let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
			guard length > 0, length <= Self.maximumMessageBytes else { throw BrowserBridgeError.tooLarge }
			return try JSONDecoder().decode(BrowserMessage.self, from: Self.readExactly(Int(length), from: descriptor))
		}
	}

	func write(_ message: BrowserMessage) throws {
		let data = try JSONEncoder().encode(message)
		guard data.count <= Self.maximumMessageBytes else { throw BrowserBridgeError.tooLarge }
		var length = UInt32(data.count).littleEndian
		let packet = withUnsafeBytes(of: &length) { Data($0) } + data
		try withDescriptor { descriptor in
			try packet.withUnsafeBytes { buffer in
				var offset = 0
				while offset < buffer.count {
					let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
					if written < 0 && errno == EINTR { continue }
					guard written > 0 else { throw BrowserBridgeError.cancelled }
					offset += written
				}
			}
		}
	}

	static func connect(path: String, peer: String) throws -> BrowserSocket {
		let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw BrowserBridgeError.unavailable }
		let connection = BrowserSocket(descriptor: descriptor)
		do {
			var address = try address(path)
			let result = withUnsafePointer(to: &address) { pointer in
				pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
			}
			guard result == 0 else { throw BrowserBridgeError.unavailable }
			try connection.verifyPeer(identifier: peer)
			return connection
		} catch { connection.close(); throw error }
	}

	static func address(_ path: String) throws -> sockaddr_un {
		var address = sockaddr_un()
		let bytes = Array(path.utf8) + [0]
		guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BrowserBridgeError.tooLarge }
		address.sun_family = sa_family_t(AF_UNIX)
		address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
		withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
		return address
	}

	private func withDescriptor<Result>(_ operation: (Int32) throws -> Result) throws -> Result {
		lock.lock()
		let duplicate = descriptor >= 0 ? dup(descriptor) : -1
		lock.unlock()
		guard duplicate >= 0 else { throw BrowserBridgeError.cancelled }
		defer { Darwin.close(duplicate) }
		return try operation(duplicate)
	}

	private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
		var data = Data(count: count)
		try data.withUnsafeMutableBytes { buffer in
			var offset = 0
			while offset < count {
				let received = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset)
				if received < 0 && errno == EINTR { continue }
				guard received > 0 else { throw BrowserBridgeError.cancelled }
				offset += received
			}
		}
		return data
	}
}

final class BrowserSocketListener: @unchecked Sendable {
	private let source: DispatchSourceRead
	private let path: String
	private let capacity = DispatchSemaphore(value: 4)
	private let stateLock = NSLock()
	private var clients: [UUID: BrowserSocket] = [:]

	init(name: String, peer: String, handler: @escaping @Sendable (BrowserMessage) async throws -> BrowserMessage) throws {
		guard ["passwords.sock", "gaze.sock"].contains(name) else { throw BrowserBridgeError.invalidRequest }
		let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gaze-browser", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		var folderInfo = stat()
		guard lstat(folder.path, &folderInfo) == 0, folderInfo.st_uid == geteuid(),
			(folderInfo.st_mode & S_IFMT) == S_IFDIR, (folderInfo.st_mode & 0o077) == 0 else {
			throw BrowserBridgeError.untrustedPeer
		}
		path = folder.appendingPathComponent(name).path
		var existing = stat()
		if lstat(path, &existing) == 0 {
			guard existing.st_uid == geteuid(), (existing.st_mode & S_IFMT) == S_IFSOCK else { throw BrowserBridgeError.untrustedPeer }
			let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
			defer { if probe >= 0 { Darwin.close(probe) } }
			var address = try BrowserSocket.address(path)
			let active = withUnsafePointer(to: &address) { pointer in
				pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
			}
			guard !active, errno == ECONNREFUSED else { throw BrowserBridgeError.unavailable }
			guard unlink(path) == 0 else { throw BrowserBridgeError.unavailable }
		}
		let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw BrowserBridgeError.unavailable }
		var initialized = false
		defer { if !initialized { Darwin.close(descriptor) } }
		var address = try BrowserSocket.address(path)
		let bound = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
		}
		guard bound else { throw BrowserBridgeError.unavailable }
		let boundPath = path
		defer { if !initialized { unlink(boundPath) } }
		guard chmod(path, 0o600) == 0, Darwin.listen(descriptor, 4) == 0,
			fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw BrowserBridgeError.unavailable }
		source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
		let capacity = self.capacity
		source.setEventHandler { [weak self] in
			guard let self else { return }
			while true {
				let incoming = Darwin.accept(descriptor, nil, nil)
				if incoming < 0 { if errno == EINTR { continue }; return }
				let connection = BrowserSocket(descriptor: incoming)
				guard capacity.wait(timeout: .now()) == .success else { connection.close(); continue }
				let identifier = UUID()
				self.stateLock.lock()
				self.clients[identifier] = connection
				self.stateLock.unlock()
				DispatchQueue.global(qos: .userInitiated).async { [weak self] in
					let timeout = DispatchWorkItem { connection.close() }
					DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)
					defer {
						timeout.cancel()
						connection.close()
						self?.removeClient(identifier)
						capacity.signal()
					}
					do {
						try connection.verifyPeer(identifier: peer)
						let request = try connection.read()
						let done = DispatchSemaphore(value: 0)
						let task = Task {
							defer { done.signal() }
							do {
								let response = try await handler(request)
								try Task.checkCancellation()
								try connection.write(response)
							} catch { try? connection.write(request.response(operation: "error", error: "Approval cancelled or unavailable.")) }
						}
						let deadline = ContinuousClock.now.advanced(by: .seconds(90))
						while done.wait(timeout: .now() + 0.15) != .success {
							if !connection.isConnected || ContinuousClock.now >= deadline { task.cancel(); break }
						}
					} catch { connection.close() }
				}
			}
		}
		let path = self.path
		source.setCancelHandler { Darwin.close(descriptor); unlink(path) }
		initialized = true
		source.resume()
	}

	private func removeClient(_ identifier: UUID) {
		stateLock.lock()
		clients.removeValue(forKey: identifier)
		stateLock.unlock()
	}

	deinit {
		source.cancel()
		for client in clients.values { client.close() }
	}
}
