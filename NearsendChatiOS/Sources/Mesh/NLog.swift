import Foundation
import os

/// Debug log for real-phone tests: every line goes to the system log (Xcode console / Console.app, subsystem
/// "app.nearsend.chat") and to a small in-memory list of the last `maxLines` lines, so a log screen or "share log"
/// button can show it later without a computer.
///
/// Never put message text, photos or keys in here. Only short ids, packet types, sizes and results.
enum NLog {
    private static let logger = Logger(subsystem: "app.nearsend.chat", category: "mesh")
    private static let lock = NSLock()
    private static var saved: [String] = []
    private static let maxLines = 500
    private static let start = Date()

    static func i(_ area: String, _ msg: String) {
        let t = Int(Date().timeIntervalSince(start) * 1000)
        let ms = String(format: "%03d", t % 1000)
        let line = "+\(t / 1000).\(ms) \(area): \(msg)"
        lock.lock()
        saved.append(line)
        if saved.count > maxLines { saved.removeFirst(saved.count - maxLines) }
        lock.unlock()
        logger.info("\(line, privacy: .public)")
    }

    /// The saved lines, oldest first.
    static func dump() -> String {
        lock.lock(); defer { lock.unlock() }
        return saved.joined(separator: "\n")
    }

    /// Short form of a peer id for the log (first 6 characters).
    static func s(_ id: String?) -> String { id.map { String($0.prefix(6)) } ?? "-" }

    /// Short form of a link id such as "out:6E1F...-...-ABCD" (kind and last 5 characters).
    static func l(_ link: String?) -> String { link.map { String($0.prefix(3)) + ".." + String($0.suffix(5)) } ?? "-" }
}
