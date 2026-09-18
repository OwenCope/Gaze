import Foundation

// The capture app has no access to the owner's enrollment or credentials.
enum Keychain {
    static func read(_ account: String) -> Data? { nil }
    static func load(_ account: String) throws -> Data? { nil }
    static func write(_ data: Data, to account: String) -> Bool {
        fatalError("Product capture cannot write credentials")
    }
    static func delete(_ account: String) -> Bool {
        fatalError("Product capture cannot delete credentials")
    }
}
