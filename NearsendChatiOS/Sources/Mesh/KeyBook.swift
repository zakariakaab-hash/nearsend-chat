import Foundation

/// Keys of saved contacts. The router asks for them from the Bluetooth thread while a message arrives, so this is not
/// tied to the main actor.
final class KeyBook: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Data] = [:]
    func key(_ id: String) -> Data? { lock.lock(); defer { lock.unlock() }; return keys[id] }
    func set(_ id: String, _ key: Data) { lock.lock(); keys[id] = key; lock.unlock() }
    func all() -> [String: Data] { lock.lock(); defer { lock.unlock() }; return keys }
    func replace(_ new: [String: Data]) { lock.lock(); keys = new; lock.unlock() }
}
