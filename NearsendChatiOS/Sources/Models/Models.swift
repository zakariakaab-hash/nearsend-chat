import Foundation

struct Peer: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var hops: Int          // 1 = direct BLE link, >1 = relayed through other phones
    var rssi: Int          // dBm, used for radar distance
    var verified: Bool = false
    var fingerprint: String = ""
    var via: String? = nil      // relayed peers: the neighbour their announcement came through (network view)
    var avatar: String? = nil   // the emoji and colour they chose, see Avatars

    /// What to draw: their own picture, else a stable one made from their id. Groups and the Nearby channel keep their letter.
    var shownAvatar: String? {
        if avatar != nil || id.hasPrefix("g:") || id == publicChannelID { return avatar }
        return Avatars.fallback(for: id)
    }
}

/// Profile "pictures" are an emoji plus one of a few colours, written "<emoji>|<colour index>" (PROTOCOL.md section 10).
/// Same list, same order as the Android app. Anything that is not exactly one of ours is ignored on receipt.
enum Avatars {
    static let emojis: [String] = [
        "\u{1F600}", "\u{1F60E}", "\u{1F920}", "\u{1F973}", "\u{1F63A}", "\u{1F436}",
        "\u{1F98A}", "\u{1F43C}", "\u{1F438}", "\u{1F984}", "\u{1F419}", "\u{1F98B}",
        "\u{1F335}", "\u{1F33B}", "\u{1F340}", "\u{2B50}", "\u{1F525}", "\u{26A1}",
        "\u{1F308}", "\u{1F355}", "\u{1F3B8}", "\u{26BD}", "\u{1F680}", "\u{1F9ED}",
        "\u{26FA}", "\u{1F3A7}", "\u{1F4F7}", "\u{1F3C4}", "\u{1F6B2}", "\u{1F30A}",
    ]
    static let colors = 8

    static func encode(_ emoji: String, _ color: Int) -> String { "\(emoji)|\(color)" }

    /// (emoji, colour) when `s` is exactly one of our emojis and a known colour, else nil.
    static func parse(_ s: String?) -> (emoji: String, color: Int)? {
        guard let s, let bar = s.lastIndex(of: "|") else { return nil }
        let emoji = String(s[s.startIndex..<bar])
        guard !emoji.isEmpty, let color = Int(String(s[s.index(after: bar)...])),
              emojis.contains(emoji), (0..<colors).contains(color) else { return nil }
        return (emoji, color)
    }

    /// `s` itself when it is a valid avatar, otherwise nil.
    static func valid(_ s: String?) -> String? { parse(s) != nil ? s : nil }

    /// A stable picture for someone who sent none (older versions): the same id always gets the same emoji and colour,
    /// and different ids are spread over all 240 combinations. Only shown here, never sent.
    static func fallback(for id: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325                       // FNV-1a, stable across launches (unlike hashValue)
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return encode(emojis[Int(h % UInt64(emojis.count))], Int((h / UInt64(emojis.count)) % UInt64(colors)))
    }

    /// A random picture for a new user, avoiding the emojis already used by people around when possible.
    static func random(avoiding used: Set<String>) -> String {
        let taken = Set(used.compactMap { parse($0)?.emoji })
        let free = emojis.filter { !taken.contains($0) }
        return encode((free.isEmpty ? emojis : free).randomElement()!, Int.random(in: 0..<colors))
    }
}

enum DeliveryState: String, Codable { case sending, sent, relayed, delivered, read, failed }

struct Message: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var date: Date
    var mine: Bool
    var state: DeliveryState = .delivered
    var hops: Int = 1
    var sender: String? = nil      // shown on public-channel and group messages
    var photo: String? = nil       // id of a photo kept on this phone (the message shows the picture, text is empty)
    var senderID: String? = nil    // who sent a public-channel or group message, so they can be blocked
    var deliveredAt: Date? = nil   // our messages: when the delivery receipt arrived (shown under Info)
    var readAt: Date? = nil        // our messages: when the read receipt arrived
    var readSent: Bool? = nil      // their messages: we already told them we read it
    var voice: Bool? = nil         // `photo` holds a voice note (AAC in .m4a), not a picture; it travels the same way
    var isVoice: Bool { voice == true }
}

/// Voice notes are sent like photos (PROTOCOL.md section 11): the receiver tells them apart by the MPEG-4 "ftyp" box.
enum VoiceNote {
    static let maxSeconds: TimeInterval = 12
    static func looksLikeAudio(_ d: Data) -> Bool { d.count > 12 && d.subdata(in: 4..<8) == Data("ftyp".utf8) }

    /// Drops the empty "free" padding Apple's writer puts before the audio (about 23 KB, more than the sound itself) and moves
    /// the sample offsets ("stco") back by the same amount. Returns the input unchanged when the layout is not the expected one.
    static func stripPadding(_ d: Data) -> Data {
        let b = [UInt8](d)
        func u32(_ i: Int) -> Int { i + 4 <= b.count ? Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) : 0 }
        func type(_ i: Int) -> String { i + 8 <= b.count ? String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? "" : "" }
        var atoms: [(type: String, start: Int, size: Int)] = []
        var i = 0
        while i + 8 <= b.count { let n = u32(i); guard n >= 8, i + n <= b.count else { return d }; atoms.append((type(i), i, n)); i += n }
        guard let free = atoms.first(where: { $0.type == "free" }), let mdat = atoms.first(where: { $0.type == "mdat" }),
              let moov = atoms.first(where: { $0.type == "moov" }), free.start < mdat.start, moov.start < free.start else { return d }
        var out = b
        // Every stco inside moov: version/flags (4), count (4), then 32-bit offsets.
        var j = moov.start + 8
        var patched = 0
        while j + 8 <= moov.start + moov.size {
            if type(j) == "stco" {
                let count = u32(j + 12)
                for k in 0..<count {
                    let at = j + 16 + k * 4
                    let v = u32(at) - free.size
                    guard v >= 0 else { return d }
                    out[at] = UInt8(v >> 24 & 0xFF); out[at + 1] = UInt8(v >> 16 & 0xFF); out[at + 2] = UInt8(v >> 8 & 0xFF); out[at + 3] = UInt8(v & 0xFF)
                }
                patched += 1
            }
            if type(j) == "co64" { return d }
            j += 1
        }
        guard patched > 0 else { return d }
        out.removeSubrange(free.start..<(free.start + free.size))
        return Data(out)
    }
}

/// A public announcement, kept by phones nearby until `exp`.
struct Post: Identifiable, Hashable {
    var id: String
    var from: String
    var name: String
    var text: String
    var exp: Date
    var mine: Bool
    var hops: Int = 1
}

/// Someone in a group (the creator included).
struct Member: Codable, Hashable { var id: String; var name: String }

struct Conversation: Identifiable, Codable {
    let id: String
    var peer: Peer
    var messages: [Message]
    var unread: Int = 0
    var members: [Member]? = nil   // groups only (ids start with "g:")
    // Local settings for this chat, never sent. Optional so chats saved by older versions still decode.
    var pinnedAt: Date? = nil          // pinned to the top of the list (newest pin first)
    var muted: Bool? = nil             // no notifications
    var locked: Bool? = nil            // Face ID / passcode to open, text hidden in the list and in notifications
    var favorite: Bool? = nil          // shown under the Favourites filter
    var pinnedMessage: String? = nil   // id of the message shown at the top of the chat
    var last: Message? { messages.last }
    var isGroup: Bool { members != nil }
    var isPinned: Bool { pinnedAt != nil }
    var isMuted: Bool { muted == true }
    var isLocked: Bool { locked == true }
    var isFavorite: Bool { favorite == true }
}

/// Replies are sent as plain text with a first line "↪ name: quoted text", so every version (and Android) shows them;
/// this app draws that first line as a quote.
enum Reply {
    static let mark = "\u{21AA} "
    static func compose(quoting m: Message, from name: String, text: String) -> String {
        let q = (m.photo != nil ? (m.isVoice ? "\u{1F3A4}" : "\u{1F4F7}") : m.text.replacingOccurrences(of: "\n", with: " "))
        let short = q.count > 60 ? String(q.prefix(60)) + "\u{2026}" : q
        return mark + name + ": " + short + "\n" + text
    }
    /// (quote line, rest) when `text` starts with a reply line.
    static func split(_ text: String) -> (quote: String, body: String)? {
        guard text.hasPrefix(mark), let nl = text.firstIndex(of: "\n") else { return nil }
        return (String(text[text.index(text.startIndex, offsetBy: mark.count)..<nl]), String(text[text.index(after: nl)...]))
    }
}

/// "Send location" travels as "📍 <openstreetmap.org link>", which any phone (and the Android app) can open.
/// This app draws such a message as a map card that opens Apple Maps.
enum SharedLocation {
    static let prefix = "\u{1F4CD} https://www.openstreetmap.org/?"
    static func parse(_ text: String) -> (lat: Double, lon: Double)? {
        guard text.hasPrefix(prefix), !text.contains("\n"),
              let q = URLComponents(string: String(text.dropFirst(2)))?.queryItems,
              let lat = q.first(where: { $0.name == "mlat" })?.value.flatMap(Double.init),
              let lon = q.first(where: { $0.name == "mlon" })?.value.flatMap(Double.init),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }
}

/// An SOS alarm heard from someone nearby. Repeats of one alarm update the same entry.
struct SosAlert: Identifiable, Hashable {
    var alarm: String
    var from: String
    var name: String
    var note: String?
    var lat: Double?
    var lon: Double?
    var accuracy: Int?
    var hops: Int
    var date: Date
    var active = true
    var id: String { from + "|" + alarm }
}

/// The public "everyone nearby" channel lives in a conversation with this id.
let publicChannelID = "public"
