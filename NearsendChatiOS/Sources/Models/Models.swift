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
}

enum DeliveryState: String, Codable { case sending, sent, relayed, delivered, failed }

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
    var last: Message? { messages.last }
    var isGroup: Bool { members != nil }
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
