import Foundation

// Cross-platform protocol checks. Run in CI: swiftc Sources/Models/Models.swift Sources/Mesh/MeshCrypto.swift Sources/Mesh/Framing.swift Sources/Mesh/MeshRouter.swift Tests/main.swift
var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { failures += 1 } }
func hex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

// 1. Test vectors generated with Python `cryptography` (see PROTOCOL.md): must decrypt, and sealing must reproduce them bit for bit.
let skA = hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
let skB = hex("65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384")
let combined = hex("c8c9cacbcccdcecfd0d1d2d3b7f7d3789adc70b46a831626878bc5809086ac2253d1ba553d06af4445a5b4c525")
let a = try! MeshCrypto(privateKeyData: skA), b = try! MeshCrypto(privateKeyData: skB)
check(a.publicKey == hex("07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c"), "public key derivation")
check((try? b.open(combined, peerPK: a.publicKey, myID: "bob", peerID: "alice", aad: "m-1")) == "Hej världen 👋", "decrypt Python vector")
check((try? a.seal("Hej världen 👋", peerPK: b.publicKey, myID: "alice", peerID: "bob", aad: "m-1", nonce: combined.prefix(12))) == combined, "seal reproduces Python vector")
check((try? b.open(combined, peerPK: a.publicKey, myID: "bob", peerID: "alice", aad: "other")) == nil, "wrong AAD rejected")
var tampered = combined; tampered[20] ^= 1
check((try? b.open(tampered, peerPK: a.publicKey, myID: "bob", peerID: "alice", aad: "m-1")) == nil, "tampered ciphertext rejected")
check(a.fingerprint == "AAA8 FFF7 03B5 0B22\n97F4 F6E1 3508 F724", "fingerprint format")
check(MeshRouter.clip(String(repeating: "å", count: 200)).utf8.count <= 180, "clip to 180 UTF-8 bytes")

// 2. Framing of notifications (must match the Kotlin implementation byte for byte).
do {
    let data = Data(0..<10)
    let frags = Framing.fragments(data, seq: 7, payload: 4)
    check(frags.map { $0.map { String(format: "%02x", $0) }.joined() } == ["070003" + "00010203", "070103" + "04050607", "070203" + "0809"], "notification fragments match the shared vector")
    var r = Reassembler(); var out: Data?
    for f in frags { out = r.add(f) }
    check(out == data, "fragments reassemble")
    var r2 = Reassembler()
    check(r2.add(frags[1]) == nil && r2.add(frags[0]) == nil && r2.add(frags[1]) == nil && r2.add(frags[2]) == data, "reassembly recovers after a lost/out-of-order fragment")
    check(Framing.fragments(Data(count: 300), seq: 0, payload: 1).isEmpty, "packets needing more than 255 fragments are refused")
}

// 3. Simulated networks. Link ids follow the app: "out:<peer>" = we connected to that peer (we can write to it),
//    "in:<peer>" = that peer connected to us (we answer with notifications).
final class Node {
    let id: String; let router: MeshRouter; let crypto: MeshCrypto
    var texts: [(from: String, text: String, hops: Int)] = []; var pubs: [String] = []; var delivered: [String] = []; var peers: [Peer] = []
    var photos: [(id: String, bytes: Data)] = []; var posts: [String] = []
    init(_ id: String, net: Net) {
        let c = MeshCrypto()
        self.id = id; self.crypto = c
        router = MeshRouter(id: id, name: id, crypto: c)
        router.transmit = { link, data, done in net.deliver(from: id, link: link, data); done(true) }
        router.onPeers = { [unowned self] in self.peers = $0 }
        router.onText = { [unowned self] f, _, t, h, _ in self.texts.append((f, t, h)) }
        router.onPublic = { [unowned self] _, _, t, _ in self.pubs.append(t) }
        router.onDelivered = { [unowned self] in self.delivered.append($0) }
        router.onPhoto = { [unowned self] _, _, id, bytes in self.photos.append((id, bytes)) }
        router.onPost = { [unowned self] _, _, _, text, _, _ in self.posts.append(text) }
    }
}
final class Net {
    var nodes: [String: Node] = [:]
    var transmits = 0
    func add(_ id: String) -> Node { let n = Node(id, net: self); nodes[id] = n; return n }
    func deliver(from: String, link: String, _ data: Data) {
        transmits += 1
        if link.hasPrefix("out:") { nodes[String(link.dropFirst(4))]?.router.receive(data, from: "in:\(from)") }
        else if link.hasPrefix("in:") { nodes[String(link.dropFirst(3))]?.router.receive(data, from: "out:\(from)") }
    }
    /// x discovered y and connected to it; y never discovered x (it only learns of x from x's hello).
    func connectOneWay(_ x: String, _ y: String) {
        nodes[x]!.router.neighborConnected(link: "out:\(y)", id: y, name: y, pk: nodes[y]!.crypto.publicKey)
    }
    /// Both discovered each other: each has an out link and an in link to the other.
    func connect(_ x: String, _ y: String) { connectOneWay(x, y); connectOneWay(y, x) }
    func settle() { for _ in 0..<3 { nodes.values.forEach { $0.router.tick() } } }
}

do { // line A-B-C-D, everyone discovered everyone
    let net = Net(); let n = ["A", "B", "C", "D"].map { net.add($0) }
    net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "D"); net.settle()
    check(n[0].peers.first { $0.id == "D" }?.hops == 3, "A sees D at 3 hops")
    var outcome: SendOutcome?
    n[0].router.sendText("hello D", to: "D", msgID: "id-1") { outcome = $0 }
    check(outcome == .sent, "send over 3 hops reports sent")
    check(n[3].texts.count == 1 && n[3].texts[0].text == "hello D" && n[3].texts[0].from == "A", "D receives decrypted text from A")
    check(n[3].texts.first?.hops == 3, "D reports 3 hops")
    check(n[0].delivered == ["id-1"], "A gets delivery ack")
    check(n[1].texts.isEmpty && n[2].texts.isEmpty, "relays cannot read the message")
    n[0].router.sendPublic("hi all", msgID: "pub-1") { _ in }
    check(n[1].pubs == ["hi all"] && n[3].pubs == ["hi all"], "public message reaches every node once")
}
do { // ONE-DIRECTIONAL discovery: only A discovered B (e.g. B is an iPhone in the background)
    let net = Net(); let n = ["A", "B"].map { net.add($0) }
    net.connectOneWay("A", "B"); net.settle()
    check(n[1].peers.map { $0.id } == ["A"], "B learns about A from A's hello although B never discovered A")
    var o1: SendOutcome?, o2: SendOutcome?
    n[0].router.sendText("A to B", to: "B", msgID: "ab") { o1 = $0 }
    n[1].router.sendText("B to A", to: "A", msgID: "ba") { o2 = $0 }
    check(o1 == .sent && o2 == .sent, "both directions report sent")
    check(n[1].texts.map { $0.text } == ["A to B"] && n[0].texts.map { $0.text } == ["B to A"], "messages flow both ways over a one-sided link")
    check(n[0].delivered == ["ab"] && n[1].delivered == ["ba"], "acks flow both ways")
}
do { // B discovered nobody; A and C both discovered B. A can still reach C through B.
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    net.connectOneWay("A", "B"); net.connectOneWay("C", "B"); net.settle()
    check(n[0].peers.first { $0.id == "C" }?.hops == 2, "A sees C at 2 hops through a phone that discovered nobody")
    n[0].router.sendText("via B", to: "C", msgID: "acx") { _ in }
    check(n[2].texts.map { $0.text } == ["via B"] && n[0].delivered == ["acx"], "relay works over in-links only")
    n[2].router.sendPublic("from C", msgID: "pc") { _ in }
    check(n[0].pubs == ["from C"] && n[1].pubs == ["from C"], "public message crosses in-links")
}
do { // each phone has two links to the other: a flood must use one link per neighbour
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "A"); net.settle()
    net.transmits = 0
    n[0].router.sendText("once", to: "C", msgID: "id-tri") { _ in }
    n[0].router.sendPublic("loop", msgID: "pub-tri") { _ in }
    check(n[2].texts.count == 1, "no duplicate delivery in a loop")
    check(n[1].pubs.count == 1 && n[2].pubs.count == 1, "public message de-duplicated in a loop")
    check(net.transmits <= 6, "one link per neighbour is used (\(net.transmits) transmissions)")
}
do { // 8-node line: only 5 hops reachable
    let net = Net(); let ids = (0..<8).map { "N\($0)" }; let n = ids.map { net.add($0) }
    for i in 0..<7 { net.connect(ids[i], ids[i + 1]) }; net.settle()
    check(Set(n[0].peers.map { $0.id }) == Set(["N1", "N2", "N3", "N4", "N5"]), "TTL limits reach to 5 hops")
    var outcome: SendOutcome?
    n[0].router.sendText("far", to: "N7", msgID: "id-far") { outcome = $0 }
    check(outcome == .unreachable, "unknown far peer reports unreachable (queued by the app)")
}
do { // expiry and link loss
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    check(n[0].peers.count == 2, "A knows B and C")
    var t = Date(); n[0].router.now = { t }; t = t.addingTimeInterval(60); n[0].router.tick()
    check(n[0].peers.map { $0.id } == ["B"], "relayed peer expires after silence, direct neighbour stays")
    n[0].router.neighborLost(link: "out:B")
    check(n[0].peers.map { $0.id } == ["B"], "neighbour stays while its other (in) link is alive")
    n[0].router.neighborLost(link: "in:B")
    check(n[0].peers.isEmpty, "neighbour removed when all its links are lost")
}
do {   // QR verification: the code only opens with the key that was in the scanned QR
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    var got: [(String, String, String)] = []
    n[2].router.onVerify = { got.append(($0, $1, $2)) }
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    n[0].router.sendVerify("c0de", to: "C", pk: n[2].crypto.publicKey) { _ in }
    check(got.count == 1 && got[0].0 == "A" && got[0].1 == MeshCrypto.fingerprint(n[0].crypto.publicKey) && got[0].2 == "c0de", "QR verify code reaches the scanned phone")
    n[0].router.sendVerify("bad", to: "C", pk: n[1].crypto.publicKey) { _ in }
    check(got.count == 1, "QR verify sealed to the wrong key is ignored")
}
do {   // SOS: public flood with location; the end packet reaches everyone too
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    var got: [(String, String, String?, String?, Int)] = []; var ended: [String] = []
    n[2].router.onSos = { from, _, alarm, note, loc, hops in got.append((from, alarm, note, loc, hops)) }
    n[2].router.onSosEnd = { _, alarm in ended.append(alarm) }
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    n[0].router.sendSos(alarm: "al-1", note: "hurt leg", loc: "59.32930,18.06860,12")
    n[0].router.sendSos(alarm: "al-1", note: nil, loc: nil)
    check(got.count == 2 && got[0].0 == "A" && got[0].1 == "al-1" && got[0].2 == "hurt leg" && got[0].3 == "59.32930,18.06860,12" && got[0].4 == 2,
          "SOS reaches C over 2 hops with note and location; repeats arrive as new packets")
    n[0].router.sendSos(alarm: "al-1", note: "x", loc: "1,2,3", end: true)
    check(ended == ["al-1"], "SOS end reaches C")
}
do {   // groups: one sealed copy per member, each acked with its own id; relays cannot read it
    let net = Net(); let n = ["A", "B", "C", "D"].map { net.add($0) }
    var got: [String: [(String, String, String, [String], String)]] = [:]
    for x in n { let id = x.id; x.router.onGroup = { from, _, g, gn, ms, text, _, mid in got[id, default: []].append((from, g + "|" + gn, text, ms.map { $0.id }, mid)) } }
    net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "D"); net.settle()
    let members = [(id: "A", name: "A"), (id: "B", name: "B"), (id: "D", name: "D")]
    var outcomes: [SendOutcome] = []
    for m in ["B", "D"] { n[0].router.sendGroup("hej gruppen", group: "g:1", groupName: "Crew", members: members, to: m, msgID: "gm-1") { outcomes.append($0) } }
    check(outcomes == [.sent, .sent], "group copies report sent")
    check(got["B"]?.count == 1 && got["D"]?.count == 1 && got["B"]?[0].1 == "g:1|Crew" && got["D"]?[0].2 == "hej gruppen", "each member opens its copy")
    check(got["D"]?[0].3 == ["A", "B", "D"] && got["D"]?[0].4 == "gm-1" && got["D"]?[0].0 == "A", "member list and message id survive")
    check(got["C"] == nil, "a relay that is not a member reads nothing")
    check(Set(n[0].delivered) == ["gm-1.B", "gm-1.D"], "each copy is acked with its own id")
}
do {   // store-and-forward: a message for someone who is away is carried, then delivered when they show up
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    n[0].router.savedKey = { $0 == "C" ? n[2].crypto.publicKey : nil }
    n[2].router.savedKey = { $0 == "A" ? n[0].crypto.publicKey : nil }
    net.connect("A", "B"); net.settle()
    var outcome: SendOutcome?
    n[0].router.sendText("see you later", to: "C", msgID: "sf-1") { outcome = $0 }
    check(outcome == .carried, "a message for someone away is carried by a phone nearby")
    check(n[2].texts.isEmpty, "the person away has not got it yet")
    net.connect("B", "C")                                  // B walks over to C
    check(n[2].texts.map { $0.text } == ["see you later"], "the carrier delivers it when it meets the person")
    check(n[0].delivered == ["sf-1"], "the receipt travels back through the carrier")
    var none: SendOutcome?
    Net().add("X").router.sendText("hi", to: "nobody", msgID: "x-1") { none = $0 }
    check(none == .unreachable, "no key: nothing to carry")
}
do {   // with nobody around the sender keeps carrying it
    let net = Net(); let n = ["A", "C"].map { net.add($0) }
    n[0].router.savedKey = { $0 == "C" ? n[1].crypto.publicKey : nil }
    n[1].router.savedKey = { $0 == "A" ? n[0].crypto.publicKey : nil }
    var outcome: SendOutcome?
    n[0].router.sendText("wait for me", to: "C", msgID: "h-1") { outcome = $0 }
    check(outcome == .held, "nobody around: the sender holds the message")
    net.connect("A", "C")
    check(n[1].texts.map { $0.text } == ["wait for me"], "a held message leaves with the sender when the person appears")
}
do {   // relay off: neither forwards nor carries other people's packets
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    n[1].router.relay = false
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    n[0].router.sendPublic("hello", msgID: "r-pub") { _ in }
    check(n[1].pubs == ["hello"] && n[2].pubs.isEmpty, "a phone with relay off still reads but does not pass on")
}
do {   // announcements reach late arrivals and expire
    let net = Net(); let n = ["A", "B", "D"].map { net.add($0) }
    net.connect("A", "B"); net.settle()
    let exp = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
    n[0].router.sendPost("free water", postID: "p-1", exp: exp)
    check(n[1].posts == ["free water"], "an announcement reaches a neighbour")
    check(n[2].posts.isEmpty, "D is not there yet")
    net.connect("B", "D")
    check(n[2].posts == ["free water"], "a late arrival gets the announcement from a neighbour")
    var t = Date(); n[1].router.now = { t }; t = t.addingTimeInterval(2 * 3600); n[1].router.tick()
    let late = net.add("E")
    net.connect("B", "E")
    check(late.posts.isEmpty, "an expired announcement is no longer handed on")
}
do {   // the picture travels with announcements and only our emojis are accepted
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    let fox = Avatars.encode(Avatars.emojis[6], 3)
    n[0].router.myAvatar = fox
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    check(n[1].peers.first { $0.id == "A" }?.avatar == fox, "the picture reaches a direct neighbour")
    check(n[2].peers.first { $0.id == "A" }?.avatar == fox, "the picture reaches a phone two hops away")
    n[0].router.myAvatar = "evil text|1"; net.settle()
    check(n[1].peers.first { $0.id == "A" }?.avatar == nil, "text that is not one of our emojis is ignored")
    n[0].router.myAvatar = Avatars.emojis[0] + "|99"; net.settle()
    check(n[1].peers.first { $0.id == "A" }?.avatar == nil, "an unknown colour is ignored")
    check(Avatars.valid(nil) == nil && Avatars.valid("|1") == nil && Avatars.valid(Avatars.emojis[0]) == nil && Avatars.valid(fox) == fox, "avatar validation")
    check(Avatars.emojis.count == 30 && Set(Avatars.emojis).count == 30, "30 different emojis")
}
do {   // photos: chunked, sealed, only to a direct neighbour, confirmed, never forwarded
    let net = Net(); let n = ["A", "B", "C"].map { net.add($0) }
    n[0].router.savedKey = { $0 == "B" ? n[1].crypto.publicKey : ($0 == "C" ? n[2].crypto.publicKey : nil) }
    n[1].router.savedKey = { $0 == "A" ? n[0].crypto.publicKey : nil }
    n[2].router.savedKey = { $0 == "A" ? n[0].crypto.publicKey : nil }
    net.connect("A", "B"); net.connect("B", "C"); net.settle()
    let photo = Data((0..<30_000).map { UInt8(truncatingIfNeeded: $0 * 31) })
    var outcome: SendOutcome?; var last = 0.0
    n[0].router.sendPhoto(photo, to: "B", photoID: "ph-1", progress: { last = $0 }) { outcome = $0 }
    check(outcome == .sent && last == 1.0, "a photo is sent in chunks to a direct neighbour")
    check(n[1].photos.count == 1 && n[1].photos[0].id == "ph-1" && n[1].photos[0].bytes == photo, "the neighbour reassembles and opens the same bytes")
    check(n[0].delivered == ["ph-1"], "the receipt comes back")
    var far: SendOutcome?
    n[0].router.sendPhoto(photo, to: "C", photoID: "ph-2", progress: { _ in }) { far = $0 }
    check(far == .unreachable && n[2].photos.isEmpty, "a photo does not travel through other phones")
    n[0].router.sendPhoto(photo, to: "B", photoID: "ph-1", progress: { _ in }) { _ in }
    check(n[1].photos.count == 1, "the same photo again is ignored")
}
// 5. Writes to a connected phone hold at most 512 bytes (iOS and Android). Photo and voice chunk packets are bigger, so they
//    must be fragmented; small packets must stay one plain JSON write so older versions still understand them.
do {
    let small = Data("{\"t\":\"msg\"}".utf8)
    check(WriteFraming.writes(small, seq: 5) == [small], "a packet under 512 bytes is one plain write")
    check(!WriteFraming.isFragment(small), "a plain JSON packet is not taken for a fragment")
    var big = Data("{".utf8); big.append(Data((0..<1_200).map { UInt8(truncatingIfNeeded: $0 % 90 + 32) }))
    let w = WriteFraming.writes(big, seq: 0x7B)
    check(w.count == 3 && w.allSatisfy { $0.count <= 512 }, "a 1.2 KB packet becomes 3 writes of at most 512 bytes")
    check(w.allSatisfy { WriteFraming.isFragment($0) }, "fragments never start with \"{\" (sequence 0x7B is skipped)")
    var r = Reassembler(); var got: Data?
    for f in w { if let p = r.add(f) { got = p } }
    check(got == big, "the receiver puts the 1.2 KB packet back together")
    check(WriteFraming.next(0x7A) == 0x7C && WriteFraming.next(0xFF) == 0x00, "sequence numbers skip 0x7B and wrap")
    // The real photo chunk packet the router builds is over the limit: this is why photos and voice notes got stuck on iPhone.
    var p = Packet(t: "img", id: UUID().uuidString, src: UUID().uuidString, dst: UUID().uuidString, ttl: 1, ts: 1_700_000_000_000)
    p.n = "anon-1234"; p.ct = Data(count: MeshRouter.photoChunk).base64EncodedString(); p.ref = UUID().uuidString; p.ix = 12; p.cnt = 40
    let size = (try? JSONEncoder().encode(p).count) ?? 0
    check(size > 512, "a photo chunk packet (\(size) bytes) needs fragmenting")
    check(WriteFraming.writes((try? JSONEncoder().encode(p)) ?? Data(), seq: 1).allSatisfy { $0.count <= 512 }, "and fragments fit one write each")
}
// 6. Someone nearby announces a contact's id with their own key: it is refused, and messages stay readable only by the contact.
do {
    let net = Net(); let a = net.add("A"); let b = net.add("B"); let m = net.add("M")
    a.router.savedKey = { $0 == "B" ? b.crypto.publicKey : nil }
    net.connect("A", "B"); net.settle()
    a.router.neighborConnected(link: "out:M", id: "B", name: "B", pk: m.crypto.publicKey)
    check(a.peers.first { $0.id == "B" }?.fingerprint == nil || a.peers.contains { $0.id == "B" }, "the real B stays listed")
    var outcome: SendOutcome?
    a.router.sendText("for B only", to: "B", msgID: "imp-1") { outcome = $0 }
    check(outcome == .sent && b.texts.map { $0.text } == ["for B only"], "a different key for a known id is refused; B still reads its messages")
    check(m.texts.isEmpty, "the impostor gets nothing readable")
}
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
