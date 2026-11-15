import Foundation

/// A notification carries at most (MTU − 3) bytes, so packets sent from a phone's GATT server to a connected phone are
/// split into fragments: [seq][index][count][chunk…]. See PROTOCOL.md.
enum Framing {
    static func fragments(_ data: Data, seq: UInt8, payload: Int) -> [Data] {
        guard payload > 0, !data.isEmpty else { return [] }
        let count = (data.count + payload - 1) / payload
        guard count <= 255 else { return [] }
        return (0..<count).map { i in
            var f = Data([seq, UInt8(i), UInt8(count)])
            f.append(data.subdata(in: (data.startIndex + i * payload)..<(data.startIndex + min(data.count, (i + 1) * payload))))
            return f
        }
    }
}

/// Puts fragments back together (they arrive in order on one connection). Returns the packet when the last fragment arrives.
struct Reassembler {
    private var seq: UInt8 = 0
    private var count = 0
    private var next = 0
    private var buf = Data()
    private var active = false

    mutating func add(_ frag: Data) -> Data? {
        guard frag.count >= 4 else { reset(); return nil }
        let s = frag[frag.startIndex], i = Int(frag[frag.startIndex + 1]), c = Int(frag[frag.startIndex + 2])
        if i == 0 { reset(); active = true; seq = s; count = c; next = 0 }
        guard active, s == seq, i == next, c == count, c > 0 else { reset(); return nil }
        buf.append(frag.dropFirst(3))
        next += 1
        if next == count { let out = buf; reset(); return out }
        return nil
    }

    private mutating func reset() { active = false; buf = Data(); next = 0; count = 0 }
}
