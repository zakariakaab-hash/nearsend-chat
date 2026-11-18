import Foundation

/// `carried`: a phone nearby took a copy for someone who is away. `held`: nobody is around, so we keep carrying it ourselves.
/// `unreachable` means we have no key for the person (nothing to carry).
enum SendOutcome { case sent, unreachable, failed, carried, held }

/// Wire packet (JSON). See PROTOCOL.md. Optional fields are omitted when nil.
struct Packet: Codable {
    var v: Int = 2
    var t: String            // "hi" | "ann" | "msg" | "gm" | "pub" | "post" | "img" | "sos" | "sosx" | "ack" | "vfy"
    var id: String
    var src: String
    var dst: String? = nil
    var ttl: Int
    var ts: Int64
    var n: String? = nil     // sender nickname
    var pk: String? = nil    // ann: base64 X25519 public key
    var ct: String? = nil    // msg: base64 sealed text; img: base64 chunk of a sealed photo
    var tx: String? = nil    // pub / post: plain text
    var ref: String? = nil   // ack: id of the message being acknowledged; sos/sosx: alarm id; post: post id; img: photo id
    var loc: String? = nil   // sos: "lat,lon,accuracyMeters"
    var exp: Int64? = nil    // post: expiry, ms since epoch
    var av: String? = nil    // ann: avatar "<emoji>|<colour index>"
    var ix: Int? = nil       // img: index of this chunk
    var cnt: Int? = nil      // img: number of chunks in the photo
}

/// Sealed body of a "gm" packet: group id ("g:..."), group name, members (id + name, sender included) and the text.
struct GroupBody: Codable {
    struct Member: Codable { var id: String; var n: String }
    var g: String
    var gn: String?
    var m: [Member]?
    var tx: String
}

/// Multi-hop relay. Transport independent: the BLE layer (or a test harness) feeds packets in and
/// provides `transmit`. Peers announce themselves every few seconds; announcements, public messages and
/// direct messages are flooded with a hop limit and de-duplicated by packet id. Packets for someone who is away are
/// carried (up to 24 hours) and handed over when that person comes into range.
final class MeshRouter {
    static let startTTL = 5
    static let maxTextBytes = 180
    static let peerTimeout: TimeInterval = 40
    static let holdTime: TimeInterval = 24 * 3600      // carried packets and announcements live at most a day
    static let maxHeld = 200
    static let maxPosts = 50
    static let photoChunk = 700                         // bytes of sealed photo per packet
    static let maxPhotoChunks = 90                      // about 60 KB sealed, the most we accept

    /// `via`: the neighbour a relayed peer's announcement came through (network view).
    private struct PeerInfo { var name: String; var pk: Data; var hops: Int; var lastSeen: Date; var direct: Bool; var via: String? = nil; var avatar: String? = nil }

    private final class Incoming {
        let src: String; let cnt: Int; var parts: [Data?]; var last: Date
        init(src: String, cnt: Int, last: Date) { self.src = src; self.cnt = cnt; parts = Array(repeating: nil, count: cnt); self.last = last }
    }

    let myID: String
    var myName: String
    private let crypto: MeshCrypto
    var now: () -> Date = { Date() }

    /// Link ids are "out:<id>" (we connected to that phone and can write to it) or "in:<id>" (it connected to us and we reply
    /// with notifications). A neighbour can have both; direct sends prefer "out:".
    var transmit: ((_ link: String, _ data: Data, _ done: @escaping (Bool) -> Void) -> Void)?
    var onPeers: (([Peer]) -> Void)?
    var onText: ((_ from: String, _ name: String, _ text: String, _ hops: Int, _ msgID: String) -> Void)?
    var onPublic: ((_ from: String, _ name: String, _ text: String, _ id: String) -> Void)?
    var onDelivered: ((_ msgID: String) -> Void)?
    /// QR verification arrived: `from` proved it holds the key we know for it (`fingerprint`) and echoed `code`.
    var onVerify: ((_ from: String, _ fingerprint: String, _ code: String) -> Void)?
    var onGroup: ((_ from: String, _ name: String, _ group: String, _ groupName: String, _ members: [(id: String, name: String)],
                   _ text: String, _ hops: Int, _ msgID: String) -> Void)?
    var onSos: ((_ from: String, _ name: String, _ alarm: String, _ note: String?, _ loc: String?, _ hops: Int) -> Void)?
    var onSosEnd: ((_ from: String, _ alarm: String) -> Void)?
    /// Announcement `post` (stable id) from `from`, shown until `exp` (ms since epoch). Called once per post.
    var onPost: ((_ from: String, _ name: String, _ post: String, _ text: String, _ exp: Int64, _ hops: Int) -> Void)?
    /// A photo from a contact arrived complete and was opened: (from, name, photo id, image bytes).
    var onPhoto: ((_ from: String, _ name: String, _ photo: String, _ bytes: Data) -> Void)?
    /// Keys of people met before who are not in range now (saved contacts): to seal to them and to open what they sent through a carrier.
    var savedKey: ((_ id: String) -> Data?)?
    /// A peer's key was seen (direct or announced); the app saves it for contacts.
    var onKey: ((_ id: String, _ pk: Data) -> Void)?
    /// Privacy settings: pass on and carry other people's packets; confirm messages we receive.
    var relay = true
    var sendAcks = true
    /// Our own picture (emoji and colour), announced to everyone nearby.
    var myAvatar: String?

    private var links: [String: String] = [:]      // link id -> peer id (direct neighbours; possibly two links per peer)
    private var peers: [String: PeerInfo] = [:]
    private var rssi: [String: Int] = [:]
    private var seen = Set<String>()
    private var seenOrder: [String] = []
    private var held: [String: (packet: Packet, until: Date)] = [:]   // packet id -> packet for someone away
    private var heldOrder: [String] = []                              // oldest first
    private var posts: [String: Packet] = [:]                         // post id -> announcement
    private var incoming: [String: Incoming] = [:]                    // photo id -> chunks received so far
    private var donePhotos: [String] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(id: String, name: String, crypto: MeshCrypto) { myID = id; myName = name; self.crypto = crypto }

    static func clip(_ s: String) -> String {
        var out = ""; var n = 0
        for ch in s { let c = ch.utf8.count; if n + c > maxTextBytes { break }; out.append(ch); n += c }
        return out
    }

    // MARK: neighbours

    /// `sayHello`: when we opened the link ("out:") we tell the other phone who we are, so it can answer over the same
    /// connection even though it never discovered us (the one-directional link problem).
    func neighborConnected(link: String, id: String, name: String, pk: Data, sayHello: Bool = true) {
        guard id != myID, pk.count == 32 else { return }
        links[link] = id
        peers[id] = PeerInfo(name: name, pk: pk, hops: 1, lastSeen: now(), direct: true)
        NLog.i("mesh", "neighbour up \(NLog.s(id)) link=\(NLog.l(link)) sayHello=\(sayHello) (\(links.count) link(s))")
        onKey?(id, pk)
        emitPeers()
        if sayHello { sendHello(to: link) }
        sendAnnounce(to: [link])
        shareStored(link: link, id: id)
    }

    func neighborLost(link: String) {
        guard let id = links.removeValue(forKey: link) else { return }
        NLog.i("mesh", "neighbour down \(NLog.s(id)) link=\(NLog.l(link)) (\(links.count) link(s) left)")
        if !links.values.contains(id) { peers.removeValue(forKey: id); rssi.removeValue(forKey: id) }
        emitPeers()
    }

    private func sendHello(to link: String) {
        var p = Packet(t: "hi", id: UUID().uuidString, src: myID, ttl: 1, ts: ms())
        p.n = myName; p.pk = crypto.publicKey.base64EncodedString()
        remember(p.id)
        write(p, on: link)
    }

    func updateRSSI(link: String, rssi value: Int) {
        guard let id = links[link] else { return }
        if let old = rssi[id], abs(old - value) < 4 { return }      // small wobble: nothing to redraw
        rssi[id] = value
        emitPeers()
    }

    private func write(_ p: Packet, on link: String) {
        guard let data = try? encoder.encode(p) else { return }
        transmit?(link, data) { _ in }
    }

    // MARK: carrying packets for people who are away

    /// A phone came into range: deliver what we carry for it, give it a copy of the rest to carry too, and show it the
    /// announcements it may have missed.
    private func shareStored(link: String, id: String) {
        expire()
        deliverHeld(to: id)
        for p in heldPackets() where p.dst != id && (relay || p.src == myID) {
            var q = p; q.ttl = Self.startTTL
            write(q, on: link)
        }
        for p in Array(posts.values) where relay || p.src == myID {
            var copy = Packet(t: "post", id: UUID().uuidString, src: p.src, ttl: 1, ts: p.ts)
            copy.n = p.n; copy.tx = p.tx; copy.ref = p.ref; copy.exp = p.exp
            remember(copy.id)
            write(copy, on: link)
        }
    }

    /// `id` became reachable: send what we hold for it. Copies handed straight to it are done; flooded ones stay until acked.
    private func deliverHeld(to id: String) {
        for p in heldPackets() where p.dst == id {
            let direct = bestLink(for: id) != nil
            NLog.i("mesh", "deliver held \(p.t) \(NLog.s(p.id)) to \(NLog.s(id)) direct=\(direct)")
            var q = p; q.ttl = Self.startTTL
            route(q, except: nil) { [weak self] r in if r == .sent && direct { self?.dropHeld(p.id) } }
        }
    }

    private func hold(_ p: Packet) {
        guard let dst = p.dst, dst != myID else { return }
        dropHeld(p.id)
        NLog.i("mesh", "hold \(p.t) \(NLog.s(p.id)) for \(NLog.s(dst)) (\(held.count + 1) held)")
        let sent = Date(timeIntervalSince1970: Double(p.ts) / 1000)
        held[p.id] = (p, min(sent, now()).addingTimeInterval(Self.holdTime))   // a sender clock in the future cannot keep it longer
        heldOrder.append(p.id)
        while heldOrder.count > Self.maxHeld { held.removeValue(forKey: heldOrder.removeFirst()) }
    }

    private func dropHeld(_ id: String) {
        if held.removeValue(forKey: id) != nil { heldOrder.removeAll { $0 == id } }
    }

    private func heldPackets() -> [Packet] { heldOrder.compactMap { held[$0]?.packet } }

    private func expire() {
        let t = now()
        for (id, h) in held where h.until < t { dropHeld(id) }
        let nowMs = ms()
        posts = posts.filter { ($0.value.exp ?? 0) > nowMs }
    }

    private func keyOf(_ id: String) -> Data? {
        if let k = peers[id]?.pk { return k }
        if let k = savedKey?(id), k.count == 32 { return k }
        return nil
    }

    // MARK: periodic

    /// Call every ~8 seconds: floods our announcement and forgets relayed peers we stopped hearing about.
    func tick() {
        let cutoff = now().addingTimeInterval(-Self.peerTimeout)
        let before = peers.count
        peers = peers.filter { $0.value.direct || $0.value.lastSeen > cutoff }
        if peers.count != before { emitPeers() }
        expire()
        let t = now()
        incoming = incoming.filter { t.timeIntervalSince($0.value.last) <= 120 }
        sendAnnounce(to: allBestLinks(except: nil))
    }

    private func sendAnnounce(to targets: [String]) {
        var p = Packet(t: "ann", id: UUID().uuidString, src: myID, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.pk = crypto.publicKey.base64EncodedString(); p.av = myAvatar
        remember(p.id)
        guard let data = try? encoder.encode(p) else { return }
        for l in targets { transmit?(l, data) { _ in } }
    }

    // MARK: sending

    /// Sends now if `dst` is reachable. If not, but we know its key (a contact), the message is stored and carried:
    /// `.carried` when a phone nearby took a copy, `.held` when nobody is around yet. `.unreachable` only without a key.
    func sendText(_ text: String, to dst: String, msgID: String, completion: @escaping (SendOutcome) -> Void) {
        guard let pk = keyOf(dst) else { completion(.unreachable); return }
        guard let ct = try? crypto.seal(Self.clip(text), peerPK: pk, myID: myID, peerID: dst, aad: msgID) else { completion(.failed); return }
        var p = Packet(t: "msg", id: msgID, src: myID, dst: dst, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.ct = ct.base64EncodedString()
        sendOrCarry(p, completion: completion)
    }

    private func sendOrCarry(_ p: Packet, completion: @escaping (SendOutcome) -> Void) {
        remember(p.id)
        if let dst = p.dst, peers[dst] != nil { route(p, except: nil, completion: completion); return }
        hold(p)
        route(p, except: nil) { r in completion(r == .sent ? .carried : .held) }
    }

    /// Public announcement, kept by every phone until `exp` (at most a day) and shown to phones that arrive later.
    func sendPost(_ text: String, postID: String, exp: Int64) {
        var p = Packet(t: "post", id: UUID().uuidString, src: myID, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.tx = Self.clip(text); p.ref = postID
        p.exp = min(exp, ms() + Int64(Self.holdTime * 1000))
        remember(p.id); keepPost(p)
        route(p, except: nil, completion: nil)
    }

    private func keepPost(_ p: Packet) {
        guard let ref = p.ref else { return }
        posts[ref] = p
        while posts.count > Self.maxPosts, let victim = posts.min(by: { ($0.value.exp ?? 0) < ($1.value.exp ?? 0) })?.key { posts.removeValue(forKey: victim) }
    }

    func sendPublic(_ text: String, msgID: String, completion: @escaping (SendOutcome) -> Void) {
        var p = Packet(t: "pub", id: msgID, src: myID, dst: nil, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.tx = Self.clip(text)
        remember(msgID)
        route(p, except: nil, completion: completion)
    }

    /// After scanning `dst`'s QR code: send back its one-time `code`, sealed to the key `pk` taken from the QR.
    func sendVerify(_ code: String, to dst: String, pk: Data, completion: @escaping (SendOutcome) -> Void) {
        let id = UUID().uuidString
        guard let ct = try? crypto.seal(code, peerPK: pk, myID: myID, peerID: dst, aad: id) else { completion(.failed); return }
        var p = Packet(t: "vfy", id: id, src: myID, dst: dst, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.ct = ct.base64EncodedString()
        remember(id)
        route(p, except: nil, completion: completion)
    }

    /// One sealed copy of a group message for member `dst`; the packet id is "<msgID>.<dst>" so each copy is acked on its own.
    func sendGroup(_ text: String, group: String, groupName: String, members: [(id: String, name: String)], to dst: String,
                   msgID: String, completion: @escaping (SendOutcome) -> Void) {
        guard let pk = keyOf(dst) else { completion(.unreachable); return }
        let id = "\(msgID).\(dst)"
        let body = GroupBody(g: group, gn: groupName, m: members.map { GroupBody.Member(id: $0.id, n: $0.name) }, tx: Self.clip(text))
        guard let json = try? encoder.encode(body), let str = String(data: json, encoding: .utf8),
              let ct = try? crypto.seal(str, peerPK: pk, myID: myID, peerID: dst, aad: id) else { completion(.failed); return }
        var p = Packet(t: "gm", id: id, src: myID, dst: dst, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.ct = ct.base64EncodedString()
        sendOrCarry(p, completion: completion)
    }

    /// SOS goes to everyone, unencrypted, like "pub". The app repeats it while the alarm is on; `alarm` ties repeats together.
    func sendSos(alarm: String, note: String?, loc: String?, end: Bool = false) {
        var p = Packet(t: end ? "sosx" : "sos", id: UUID().uuidString, src: myID, ttl: Self.startTTL, ts: ms())
        p.n = myName; p.ref = alarm
        if !end, let note, !note.trimmingCharacters(in: .whitespaces).isEmpty { p.tx = Self.clip(note) }
        if !end { p.loc = loc }
        remember(p.id)
        route(p, except: nil, completion: nil)
    }

    // MARK: photos: sealed, cut into chunks, sent one by one to a neighbour, never passed on (PROTOCOL.md section 11)

    /// Sends `bytes` (an already compressed image) to `dst`, which must be a direct Bluetooth neighbour we have the key of.
    /// Completion: `.sent` when every chunk was handed to Bluetooth (the receipt comes later through `onDelivered`),
    /// `.unreachable` when the person is not in direct range (or walked away), `.failed` on a write error.
    func sendPhoto(_ bytes: Data, to dst: String, photoID: String, progress: @escaping (Double) -> Void, completion: @escaping (SendOutcome) -> Void) {
        guard let pk = keyOf(dst) else { completion(.unreachable); return }
        guard peers[dst]?.direct == true, bestLink(for: dst) != nil else { completion(.unreachable); return }
        guard let sealed = try? crypto.sealData(bytes, peerPK: pk, myID: myID, peerID: dst, aad: photoID) else { completion(.failed); return }
        let cnt = (sealed.count + Self.photoChunk - 1) / Self.photoChunk
        NLog.i("photo", "send to \(NLog.s(dst)): \(bytes.count) bytes, \(cnt) chunk(s)")
        guard cnt <= Self.maxPhotoChunks else { completion(.failed); return }
        func next(_ i: Int) {
            if i == cnt { NLog.i("photo", "send done, \(cnt) chunk(s) handed to Bluetooth"); completion(.sent); return }
            guard let link = bestLink(for: dst) else { NLog.i("photo", "send stopped at chunk \(i)/\(cnt): peer gone"); completion(.unreachable); return }
            let lo = i * Self.photoChunk, hi = min(sealed.count, (i + 1) * Self.photoChunk)
            var p = Packet(t: "img", id: UUID().uuidString, src: myID, dst: dst, ttl: 1, ts: ms())
            p.n = myName; p.ct = sealed.subdata(in: lo..<hi).base64EncodedString(); p.ref = photoID; p.ix = i; p.cnt = cnt
            remember(p.id)
            guard let data = try? encoder.encode(p), let t = transmit else { completion(.failed); return }
            t(link, data) { ok in
                if ok { progress(Double(i + 1) / Double(cnt)); next(i + 1) } else { NLog.i("photo", "chunk \(i)/\(cnt) write failed"); completion(.failed) }
            }
        }
        next(0)
    }

    private func receiveImg(_ p: Packet) {
        guard let ref = p.ref, let ix = p.ix, let cnt = p.cnt,
              (1...Self.maxPhotoChunks).contains(cnt), (0..<cnt).contains(ix), !donePhotos.contains(ref),
              let pk = keyOf(p.src),                                   // only from people whose key we have
              let s = p.ct, let part = Data(base64Encoded: s), !part.isEmpty, part.count <= Self.photoChunk + 16 else { return }
        let inc: Incoming
        if let existing = incoming[ref] { inc = existing }
        else {
            guard incoming.count < 4 else { return }
            inc = Incoming(src: p.src, cnt: cnt, last: now())
            incoming[ref] = inc
        }
        guard inc.src == p.src, inc.cnt == cnt else { return }
        inc.parts[ix] = part; inc.last = now()
        guard !inc.parts.contains(where: { $0 == nil }) else { return }
        incoming.removeValue(forKey: ref)
        var sealed = Data()
        for piece in inc.parts { if let piece { sealed.append(piece) } }
        guard let bytes = try? crypto.openData(sealed, peerPK: pk, myID: myID, peerID: p.src, aad: ref) else {
            NLog.i("photo", "from \(NLog.s(p.src)): all \(cnt) chunk(s) arrived but could not be opened"); return
        }
        NLog.i("photo", "received from \(NLog.s(p.src)): \(bytes.count) bytes in \(cnt) chunk(s)")
        donePhotos.append(ref); if donePhotos.count > 100 { donePhotos.removeFirst() }
        onPhoto?(p.src, p.n ?? peers[p.src]?.name ?? "?", ref, bytes)
        // A photo is confirmed even when delivery receipts are off: without it the sender cannot tell a lost chunk from success.
        sendAck(to: p.src, ref: ref)
    }

    // MARK: receiving

    func receive(_ data: Data, from link: String?) {
        guard let p = try? decoder.decode(Packet.self, from: data), p.v == 2, p.src != myID, !seen.contains(p.id) else { return }
        remember(p.id)
        let hops = max(1, Self.startTTL + 1 - p.ttl)
        if p.t != "ann" {
            NLog.i("mesh", "rx \(p.t) \(NLog.s(p.id)) from \(NLog.s(p.src)) to \(p.dst == nil ? "all" : (p.dst == myID ? "me" : NLog.s(p.dst))) ttl=\(p.ttl) hops=\(hops) via \(NLog.l(link))")
        }
        switch p.t {
        case "hi":                       // a phone that connected to us introduces itself; we can now reply over that connection
            guard let link, let s = p.pk, let pk = Data(base64Encoded: s), pk.count == 32 else { return }
            neighborConnected(link: link, id: p.src, name: p.n ?? "?", pk: pk, sayHello: false)
        case "ann":
            guard let s = p.pk, let pk = Data(base64Encoded: s), pk.count == 32 else { return }
            let direct = peers[p.src]?.direct ?? false
            let wasKnown = peers[p.src] != nil
            peers[p.src] = PeerInfo(name: p.n ?? "?", pk: pk, hops: direct ? 1 : hops, lastSeen: now(), direct: direct,
                                    via: direct ? nil : link.flatMap { links[$0] }, avatar: Avatars.valid(p.av))
            onKey?(p.src, pk)
            emitPeers()
            if !wasKnown { NLog.i("mesh", "new peer \(NLog.s(p.src)) via announcement, \(hops) hop(s)"); deliverHeld(to: p.src) }
            forward(p, from: link)
        case "msg":
            if p.dst == myID {
                guard let pk = keyOf(p.src), let s = p.ct, let ct = Data(base64Encoded: s),
                      let text = try? crypto.open(ct, peerPK: pk, myID: myID, peerID: p.src, aad: p.id) else {
                    NLog.i("mesh", "msg \(NLog.s(p.id)) from \(NLog.s(p.src)) dropped: no key, wrong key or damaged"); return
                }
                onText?(p.src, p.n ?? peers[p.src]?.name ?? "?", text, hops, p.id)
                ack(p)
            } else { passOn(p, from: link) }
        case "img":
            if p.dst == myID { receiveImg(p) }      // photos only ever go to one neighbour: never forwarded
        case "post":
            guard let ref = p.ref, let tx = p.tx, let e = p.exp else { return }
            let exp = min(e, ms() + Int64(Self.holdTime * 1000))
            if exp <= ms() { return }
            let fresh = posts[ref] == nil
            var kept = p; kept.dst = nil; kept.exp = exp
            keepPost(kept)
            if fresh { onPost?(p.src, p.n ?? "?", ref, tx, exp, hops) }
            forward(p, from: link)
        case "gm":
            if p.dst == myID {
                guard let pk = keyOf(p.src), let s = p.ct, let ct = Data(base64Encoded: s),
                      let str = try? crypto.open(ct, peerPK: pk, myID: myID, peerID: p.src, aad: p.id),
                      let body = try? decoder.decode(GroupBody.self, from: Data(str.utf8)),
                      body.g.hasPrefix("g:"), !body.tx.isEmpty else {
                    NLog.i("mesh", "group msg \(NLog.s(p.id)) from \(NLog.s(p.src)) dropped: no key, wrong key or damaged"); return
                }
                let members = (body.m ?? []).filter { !$0.id.isEmpty }.map { (id: $0.id, name: $0.n) }
                let gn = body.gn.flatMap { $0.isEmpty ? nil : $0 } ?? "?"
                onGroup?(p.src, p.n ?? peers[p.src]?.name ?? "?", body.g, gn, members, body.tx, hops, String(p.id.split(separator: ".").first ?? ""))
                ack(p)
            } else { passOn(p, from: link) }
        case "pub":
            if let tx = p.tx { onPublic?(p.src, p.n ?? "?", tx, p.id) }
            forward(p, from: link)
        case "sos":
            if let alarm = p.ref { onSos?(p.src, p.n ?? "?", alarm, p.tx, p.loc, hops) }
            forward(p, from: link)
        case "sosx":
            if let alarm = p.ref { onSosEnd?(p.src, alarm) }
            forward(p, from: link)
        case "ack":
            if let ref = p.ref { dropHeld(ref) }            // delivered: carriers drop their copy as the ack passes
            if p.dst == myID, let ref = p.ref { onDelivered?(ref) } else { passOn(p, from: link) }
        case "vfy":
            if p.dst == myID {
                guard let info = peers[p.src], let s = p.ct, let ct = Data(base64Encoded: s),
                      let code = try? crypto.open(ct, peerPK: info.pk, myID: myID, peerID: p.src, aad: p.id) else { return }
                onVerify?(p.src, MeshCrypto.fingerprint(info.pk), code)
            } else { passOn(p, from: link) }
        default: break
        }
    }

    // MARK: internals

    private func ack(_ p: Packet) {
        guard sendAcks else { return }
        sendAck(to: p.src, ref: p.id)
    }

    private func sendAck(to dst: String, ref: String) {
        var ack = Packet(t: "ack", id: UUID().uuidString, src: myID, dst: dst, ttl: Self.startTTL, ts: ms())
        ack.ref = ref
        remember(ack.id)
        sendOrCarry(ack) { _ in }
    }

    /// A packet for someone else: pass it on, and keep a copy to carry if that person is not reachable now.
    private func passOn(_ p: Packet, from link: String?) {
        guard relay else { return }
        if let dst = p.dst, peers[dst] == nil { hold(p) }
        forward(p, from: link)
    }

    private func forward(_ p: Packet, from link: String?) {
        guard relay, p.ttl > 1 else { return }
        var q = p; q.ttl -= 1
        route(q, except: link, completion: nil)
    }

    private func bestLink(for peer: String) -> String? {
        let ls = links.filter { $0.value == peer }.map { $0.key }.sorted()
        return ls.first { $0.hasPrefix("out:") } ?? ls.first
    }

    /// One link per neighbouring phone (never both of its links), skipping the phone a packet came from.
    private func allBestLinks(except exceptPeer: String?) -> [String] {
        Set(links.values).filter { $0 != exceptPeer }.sorted().compactMap { bestLink(for: $0) }
    }

    /// Sends straight to the destination if it is a neighbour, otherwise floods to all other neighbours.
    private func route(_ p: Packet, except: String?, completion: ((SendOutcome) -> Void)?) {
        var targets = allBestLinks(except: except.flatMap { links[$0] })
        if let dst = p.dst, let direct = bestLink(for: dst) { targets = [direct] }
        guard !targets.isEmpty, let data = try? encoder.encode(p) else {
            if p.t != "ann" { NLog.i("mesh", "tx \(p.t) \(NLog.s(p.id)): \(targets.isEmpty ? "nobody in range" : "could not encode")") }
            completion?(targets.isEmpty ? .unreachable : .failed); return
        }
        if p.t != "ann" { NLog.i("mesh", "tx \(p.t) \(NLog.s(p.id)) to \(p.dst == nil ? "all" : NLog.s(p.dst)) ttl=\(p.ttl) over \(targets.count) link(s)") }
        var pending = targets.count; var ok = false
        for l in targets {
            transmit?(l, data) { success in
                if !success { NLog.i("mesh", "tx \(p.t) \(NLog.s(p.id)) failed on \(NLog.l(l))") }
                if success { ok = true }
                pending -= 1
                if pending == 0 { completion?(ok ? .sent : .failed) }
            }
        }
    }

    private func emitPeers() {
        onPeers?(peers.map { id, i in
            let r = i.direct ? (rssi[id] ?? -80) : -70 - 8 * i.hops
            return Peer(id: id, name: i.name, hops: i.hops, rssi: min(-40, max(-95, r)), fingerprint: MeshCrypto.fingerprint(i.pk), via: i.via, avatar: i.avatar)
        }.sorted { $0.id < $1.id })
    }

    private func remember(_ id: String) {
        seen.insert(id); seenOrder.append(id)
        if seenOrder.count > 1500 { seen.remove(seenOrder.removeFirst()) }
    }
    private func ms() -> Int64 { Int64(now().timeIntervalSince1970 * 1000) }
}
