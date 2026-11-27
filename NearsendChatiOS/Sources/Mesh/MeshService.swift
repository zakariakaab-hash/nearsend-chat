import Combine
import CommonCrypto
import CryptoKit
import CoreLocation
import Foundation
import SwiftUI
import UIKit

private struct SavedState: Codable {
    var nickname: String
    var conversations: [Conversation]
    var verified: [String]
    var leftGroups: [String]?
    var keys: [String: String]?     // contacts' public keys (base64), to message them while they are away
    var blocked: [String]?          // phones whose messages are ignored
}

/// UI-facing state. On a real iPhone it is driven by `BLETransport` + `MeshRouter`; the iOS Simulator has no
/// Bluetooth, so there it shows demo data instead. Conversations are saved on the device.
@MainActor
final class ChatStore: ObservableObject {
    /// One store per process. The app delegate starts it on a background relaunch, before any screen exists.
    static let shared = ChatStore()

    @Published var peers: [Peer] = []
    @Published var conversations: [Conversation] = []
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "nickname"); save() }
    }
    @Published var meshActive = true {
        didSet {
            guard !simulated, oldValue != meshActive else { return }
            // Paused: stop the radio and forget everyone, also people known only through relays (they would come back on
            // the next announcement round otherwise).
            if meshActive { transport?.start() } else { transport?.stop(); router?.forgetEveryone(); peers = [] }
        }
    }
    @Published var bluetoothState = "starting"   // starting | ready | off | unauthorized | unsupported
    @Published private(set) var myFingerprint = "A3F1 9C02 7BD4 E58A\n11C0 4F6E 92AB 3D77"
    @Published private(set) var verified: Set<String> = []
    @Published private(set) var blocked: Set<String> = []      // peer ids: everything new from them is dropped

    /// Demo data instead of Bluetooth, in the simulator only (it has no Bluetooth). Real iPhones always use Bluetooth.
    @Published private(set) var simulated: Bool
    var activeConversation: String?
    private var deviceID: String
    private var transport: BLETransport?
    private var router: MeshRouter?
    private var started = false
    private var timer: Timer?
    private var saverWatch: AnyCancellable?
    private var inflight = Set<String>()
    private var leftGroups = Set<String>()                  // group ids we left: their messages are dropped
    private var groupPending: [String: Set<String>] = [:]   // group message id -> members not sent to yet
    private var groupAcks: [String: Set<String>] = [:]      // group message id -> members who confirmed
    private let keyBook = KeyBook()                         // contacts' keys, also read by the router
    private var handed = Set<String>()                      // message ids the router carries for us this session
    private var receiptTries: [String: (at: Date, count: Int)] = [:]   // our sent messages with no delivery receipt yet
    private var photoSentAt: [String: Date] = [:]           // photo message id -> when all chunks last went out
    private var photoTries: [String: Int] = [:]
    private let photoCache = NSCache<NSString, UIImage>()     // decoded pictures, so a redraw does not decode them again
    private var tickCount = 0
    private var savePending = false

    // Announcements, pictures, photos and privacy settings
    @Published private(set) var posts: [Post] = []          // newest first (not saved)
    @Published private(set) var photoProgress: [String: Double] = [:]
    @Published var photoError = false
    @Published private(set) var myAvatar: String? = Avatars.valid(UserDefaults.standard.string(forKey: "avatar"))
    @Published var relayOthers: Bool = UserDefaults.standard.object(forKey: "relay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(relayOthers, forKey: "relay"); router?.relay = relayOthers }
    }
    @Published var receipts: Bool = UserDefaults.standard.object(forKey: "receipts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(receipts, forKey: "receipts"); router?.sendAcks = receipts }
    }
    @Published var hidePreviews = UserDefaults.standard.bool(forKey: "hidePreviews") {
        didSet { UserDefaults.standard.set(hidePreviews, forKey: "hidePreviews") }
    }
    /// Off: announcements are hidden on the Nearby tab and give no notifications (phones still pass them on for others).
    @Published var showAnnouncements: Bool = UserDefaults.standard.object(forKey: "announcements") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAnnouncements, forKey: "announcements") }
    }
    @Published var autoDeleteDays = UserDefaults.standard.integer(forKey: "autoDelete") {
        didSet { UserDefaults.standard.set(autoDeleteDays, forKey: "autoDelete"); prune() }
    }
    /// Private messages from someone with no chat here yet: shown as they come, held as a request, or dropped.
    enum StrangerPolicy: String, CaseIterable { case allow, ask, block }
    @Published var strangers = StrangerPolicy(rawValue: UserDefaults.standard.string(forKey: "strangers") ?? "") ?? .ask {
        didSet { UserDefaults.standard.set(strangers.rawValue, forKey: "strangers") }
    }
    /// On: the name and picture we announce to everyone nearby are replaced by `hiddenName`. People who already have
    /// a chat with us keep seeing the name they know (this build and later); a contact code still carries the real name.
    @Published var hideFromStrangers = UserDefaults.standard.bool(forKey: "hideMe") {
        didSet { UserDefaults.standard.set(hideFromStrangers, forKey: "hideMe"); applyNickname() }
    }
    static let hiddenName = "Nearsend user"
    private var announcedName: String { hideFromStrangers ? Self.hiddenName : nickname }
    /// A notification when someone we chat with comes back in range after 30 minutes away (at most every 2 hours each).
    @Published var friendNearbyAlerts: Bool = UserDefaults.standard.object(forKey: "friendNearby") as? Bool ?? true {
        didSet { UserDefaults.standard.set(friendNearbyAlerts, forKey: "friendNearby") }
    }
    private var lastSeen: [String: Date] = (UserDefaults.standard.dictionary(forKey: "lastSeen") as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    private var friendAlertAt: [String: Date] = [:]
    private var lastSeenSaved = Date.distantPast

    // SOS
    @Published private(set) var alerts: [SosAlert] = []    // alarms heard, newest first (not saved)
    @Published private(set) var mySos: String?             // our alarm id while SOS is on
    @Published var sosNote = ""
    @Published var shareLocation = UserDefaults.standard.bool(forKey: "sosLocation") {
        didSet { UserDefaults.standard.set(shareLocation, forKey: "sosLocation") }
    }
    @Published private(set) var myLocation: CLLocation?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private let location = LocationFeed()
    private var locationUsers = 0
    private var sosTimer: Timer?

    init() {
        let d = UserDefaults.standard
        // A new user gets a random name once; it is saved now (didSet does not run in init), so it stays the same next launch.
        if d.string(forKey: "nickname") == nil { d.set("anon-\(Int.random(in: 1000...9999))", forKey: "nickname") }
        nickname = d.string(forKey: "nickname") ?? "anon"
        if d.string(forKey: "deviceID") == nil { d.set(UUID().uuidString, forKey: "deviceID") }
        deviceID = d.string(forKey: "deviceID") ?? UUID().uuidString
        #if targetEnvironment(simulator)
        simulated = !d.bool(forKey: "realBluetooth")   // the simulator has no Bluetooth: demo data, unless testing the prompts
        #else
        simulated = false
        d.removeObject(forKey: "demoMode")   // the Demo mode switch is gone: phones that had it on go back to real chats
        #endif
        if simulated { seed() } else { load() }
        drift()
        if myAvatar == nil && UserDefaults.standard.object(forKey: "avatarChosen") == nil {
            // Everyone starts with a picture instead of a blank initial; it can be changed any time on the You tab.
            changeAvatar(Avatars.random(avoiding: Set(peers.compactMap(\.avatar) + conversations.compactMap(\.peer.avatar))))
        }
        ensurePublicChannel()
        locationStatus = location.status
        location.onUpdate = { [weak self] l in Task { @MainActor in self?.myLocation = l } }
        location.onStatus = { [weak self] s in Task { @MainActor in self?.locationChanged(s) } }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.saveNow() } }
        }
    }

    var relayedCount: Int { peers.filter { $0.hops > 1 }.count }
    /// Bluetooth's state in a word or two, for Settings.
    var bluetoothLabel: String {
        if simulated { return "Demo data" }
        switch bluetoothState {
        case "ready": return meshActive ? "On" : "Paused"
        case "off": return "Off"
        case "unauthorized": return "Not allowed"
        case "unsupported": return "Unsupported"
        default: return "Starting…"
        }
    }
    var unreadTotal: Int { conversations.reduce(0) { $0 + $1.unread } }

    // MARK: lifecycle

    /// Called once onboarding is done, so the Bluetooth permission prompt appears at a sensible moment.
    func startIfNeeded() {
        guard !simulated, !started else { return }
        started = true
        let crypto = KeyStore.loadOrCreate()
        myFingerprint = crypto.fingerprint
        myPublicKey = crypto.publicKey
        let r = MeshRouter(id: deviceID, name: announcedName, crypto: crypto)
        let t = BLETransport(id: deviceID, name: announcedName, publicKey: crypto.publicKey)
        r.transmit = { [weak t] link, data, done in if let t { t.write(link: link, data: data, done: done) } else { done(false) } }
        r.onPeers = { [weak self] p in Task { @MainActor in self?.setPeers(p) } }
        r.onRepeat = { [weak self] from, id in Task { @MainActor in self?.resendRead(from: from, id: id) } }
        r.onText = { [weak self] from, name, text, hops, id in Task { @MainActor in self?.receiveText(from: from, name: name, text: text, hops: hops, id: id) } }
        r.onPublic = { [weak self] from, name, text, id in Task { @MainActor in self?.receivePublic(from: from, name: name, text: text, id: id) } }
        r.onDelivered = { [weak self] id in Task { @MainActor in self?.markDelivered(id) } }
        r.onGroup = { [weak self] from, name, g, gn, ms, text, hops, id in
            let members = ms.map { Member(id: $0.id, name: $0.name) }
            Task { @MainActor in self?.receiveGroup(from: from, name: name, group: g, groupName: gn, members: members, text: text, hops: hops, id: id) }
        }
        r.onSos = { [weak self] from, name, alarm, note, loc, hops in
            Task { @MainActor in self?.receiveSos(from: from, name: name, alarm: alarm, note: note, loc: loc, hops: hops) }
        }
        r.onSosEnd = { [weak self] from, alarm in Task { @MainActor in self?.endSos(from: from, alarm: alarm) } }
        r.onPost = { [weak self] from, name, post, text, exp, hops in
            Task { @MainActor in self?.receivePost(from: from, name: name, post: post, text: text, exp: exp, hops: hops) }
        }
        r.onPhoto = { [weak self] from, name, photo, bytes in Task { @MainActor in self?.receivePhoto(from: from, name: name, photo: photo, bytes: bytes) } }
        r.onKey = { [weak self] id, pk in Task { @MainActor in self?.learnKey(id, pk) } }
        let book = keyBook
        r.savedKey = { id in book.key(id) }
        r.relay = relayOthers; r.sendAcks = receipts; r.myAvatar = hideFromStrangers ? nil : myAvatar
        t.onNeighbor = { link, id, name, pk in r.neighborConnected(link: link, id: id, name: name, pk: pk) }
        t.onLost = { r.neighborLost(link: $0) }
        t.onPacket = { data, link in r.receive(data, from: link) }
        t.onRSSI = { r.updateRSSI(link: $0, rssi: $1) }
        t.onState = { [weak self, weak r] s in
            Task { @MainActor in
                self?.bluetoothState = s
                if s != "ready" { r?.forgetEveryone() }   // Bluetooth off: show nobody in range
            }
        }
        router = r; transport = t
        // Battery saver also makes Bluetooth scan less (see BLETransport.dutyCycleScan).
        t.saver = PowerMode.shared.saver
        saverWatch = PowerMode.shared.$saver.sink { [weak t] on in t?.saver = on }
        if meshActive { t.start() }
        // Announce every 8 s, or every 16 s in Low Power Mode (relayed people are forgotten after 40 s of silence).
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickCount += 1
                if self.tickCount % (ProcessInfo.processInfo.isLowPowerModeEnabled ? 4 : 2) == 0 { self.router?.tick() }
                self.prune(); self.flushOutbox(); self.rememberSeen()
            }
        }
    }

    func applyNickname() {
        router?.myName = announcedName
        router?.myAvatar = hideFromStrangers ? nil : myAvatar
        transport?.setName(announcedName)
    }

    /// Panic wipe: forget every message, key and setting. The phone gets a brand-new identity.
    func wipeAll() {
        stopSos()
        leftGroups = []; groupPending = [:]; groupAcks = [:]; alerts = []
        keyBook.replace([:]); handed = []; posts = []; photoSentAt = [:]; photoTries = [:]; photoProgress = [:]
        try? FileManager.default.removeItem(at: Self.photosDir); photoCache.removeAllObjects()
        transport?.stop(); timer?.invalidate()
        router = nil; transport = nil; started = false; inflight = []
        KeyStore.wipe()
        try? FileManager.default.removeItem(at: Self.fileURL)
        let d = UserDefaults.standard
        ["nickname", "deviceID", "onboarded", "tab", "relay", "receipts", "hidePreviews", "autoDelete", "avatar", "announcements", "avatarChosen",
         "strangers", "hideMe", "friendNearby", "lastSeen", "appLock"].forEach { d.removeObject(forKey: $0) }
        strangers = .ask; hideFromStrangers = false; friendNearbyAlerts = true; lastSeen = [:]; friendAlertAt = [:]
        relayOthers = true; receipts = true; hidePreviews = false; autoDeleteDays = 0; myAvatar = nil; showAnnouncements = true
        deviceID = UUID().uuidString; d.set(deviceID, forKey: "deviceID")
        verified = []; blocked = []; peers = []; conversations = []
        myFingerprint = simulated ? myFingerprint : ""
        nickname = "anon-\(Int.random(in: 1000...9999))"
        changeAvatar(Avatars.random(avoiding: []))   // a fresh picture for the fresh identity, as on first launch
        d.removeObject(forKey: "avatarChosen")
        ensurePublicChannel()
        // Bluetooth starts again only from the onboarding's last page ("Allow Bluetooth & start"), as on a first launch,
        // so iOS does not ask about Bluetooth while page 1 is showing.
        if simulated { seed() }
    }

    // MARK: conversations

    private func index(_ id: String) -> Int? { conversations.firstIndex { $0.id == id } }

    func ensureConversation(_ peer: Peer) {
        if index(peer.id) == nil { conversations.append(Conversation(id: peer.id, peer: peer, messages: [])) }
    }

    // MARK: strangers and friends nearby

    /// Someone with no chat on this phone wrote to us. nil = drop it (Block), true = keep it as a request (Ask me),
    /// false = a normal chat (Allow, or we already have a chat with them).
    private func strangerGate(_ from: String) -> Bool? {
        if index(from) != nil { return false }
        switch strangers {
        case .allow: return false
        case .ask: return true
        case .block: NLog.i("chat", "dropped a message from a stranger (\(NLog.s(from)))"); return nil
        }
    }

    /// "Accept" on a message request: it becomes a normal chat, and read receipts start working.
    func acceptRequest(_ id: String) {
        guard let i = index(id) else { return }
        conversations[i].request = nil
        save()
        markRead(id)
    }

    /// People we chat with who just came in range: a notification when they were away 30 minutes or more.
    private func friendsArrived(_ arrived: [Peer]) {
        let now = Date()
        if friendNearbyAlerts {
            for p in arrived {
                guard let c = conversations.first(where: { $0.id == p.id }), !c.isGroup, !c.isRequest, !c.isMuted, !c.messages.isEmpty
                else { continue }
                let away = lastSeen[p.id].map { now.timeIntervalSince($0) } ?? .infinity
                let since = friendAlertAt[p.id].map { now.timeIntervalSince($0) } ?? .infinity
                guard away > 30 * 60, since > 2 * 3600 else { continue }
                friendAlertAt[p.id] = now
                Notifier.notify(title: String(format: localized("%@ is nearby"), p.name), body: localized("Say hi, or agree where to meet."))
            }
        }
        rememberSeen(now)
    }

    /// When each person was last in range, saved at most once a minute (it decides who counts as "back").
    private func rememberSeen(_ now: Date = .now) {
        for p in peers { lastSeen[p.id] = now }
        guard now.timeIntervalSince(lastSeenSaved) > 60 else { return }
        lastSeenSaved = now
        let week = now.addingTimeInterval(-7 * 86400)
        lastSeen = lastSeen.filter { $0.value > week }
        UserDefaults.standard.set(lastSeen.mapValues { $0.timeIntervalSince1970 }, forKey: "lastSeen")
    }

    /// The chat is on screen: clear the badge and, in a private chat, send read receipts for their messages
    /// (only when Delivery receipts are on; the router checks).
    /// They sent a message again because our receipts did not reach them: if we already read it, say so again.
    private func resendRead(from: String, id: String) {
        guard receipts, let router, let c = conversations.first(where: { $0.id == from }),
              c.messages.contains(where: { $0.id == id && $0.readSent == true }) else { return }
        router.sendRead(to: from, ref: id)
    }

    func markRead(_ id: String) {
        guard let i = index(id) else { return }
        var changed = false
        if conversations[i].unread > 0 { conversations[i].unread = 0; changed = true }
        if !simulated, !conversations[i].isGroup, !conversations[i].isRequest, id != publicChannelID, receipts, let router {
            for j in conversations[i].messages.indices where !conversations[i].messages[j].mine && conversations[i].messages[j].readSent != true {
                router.sendRead(to: id, ref: conversations[i].messages[j].id)
                conversations[i].messages[j].readSent = true; changed = true
            }
        }
        if changed { save() }
    }

    /// What "Show my code" puts in the QR code: our fingerprint, so a friend can verify us by scanning instead of reading digits.
    /// Our public key, once Bluetooth has started (it is made then); part of the contact card.
    @Published private(set) var myPublicKey: Data?

    /// What "Show my code" shows: our contact card (id, public key, name), so a friend can add us from anywhere and
    /// verify us at the same time. Before the key exists, just the fingerprint.
    var myCodePayload: String { myContactCode ?? "nearsend:fp:" + Self.compact(myFingerprint) }

    /// "nearsend:c:" + base64url JSON {i: id, k: public key, n: name}. Also shared as text for pasting.
    var myContactCode: String? {
        guard let pk = myPublicKey,
              let json = try? JSONSerialization.data(withJSONObject: ["i": deviceID, "k": pk.base64EncodedString(), "n": nickname], options: [.sortedKeys])
        else { return nil }
        return "nearsend:c:" + json.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func parseContact(_ code: String) -> (id: String, key: Data, name: String)? {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t.range(of: "nearsend:c:") else { return nil }
        var b = String(t[r.upperBound...]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b = String(b.prefix { !$0.isWhitespace })
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b), data.count < 2_000,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = o["i"], !id.isEmpty, id.count <= 64, let ks = o["k"], let key = Data(base64Encoded: ks), key.count == 32
        else { return nil }
        return (id, key, String((o["n"] ?? "?").prefix(24)))
    }

    enum AddContactResult: Equatable { case added(id: String, name: String), itsYou, invalid }

    /// A contact card scanned or pasted: saves their key and opens a chat with them, even when they are far away
    /// (phones in between carry the messages). Scanning in person also verifies them.
    func addContact(code: String, inPerson: Bool) -> AddContactResult {
        guard let c = Self.parseContact(code) else { return .invalid }
        guard c.id != deviceID else { return .itsYou }
        let fp = MeshCrypto.fingerprint(c.key)
        var all = keyBook.all(); all[c.id] = c.key; keyBook.replace(all)
        if inPerson { verified.insert(fp) }
        let peer = Peer(id: c.id, name: c.name, hops: 2, rssi: -100, verified: verified.contains(fp), fingerprint: fp)
        if let i = index(c.id) { conversations[i].peer.fingerprint = fp; conversations[i].peer.verified = peer.verified }
        else { ensureConversation(peer) }
        peers = peers.map { var p = $0; p.verified = verified.contains(p.fingerprint); return p }
        save()
        flushOutbox()
        return .added(id: c.id, name: c.name)
    }
    private static func compact(_ fp: String) -> String { fp.filter { $0.isHexDigit }.uppercased() }

    /// A scanned code: marks the matching person as verified and returns their name, or nil when nobody here has that fingerprint.
    func verifyScanned(_ payload: String) -> String? {
        if let c = Self.parseContact(payload) {    // a contact card verifies too: its key gives the fingerprint
            if case .added(_, let name) = addContact(code: payload, inPerson: true) { return name }
            return c.id == deviceID ? nil : c.name
        }
        guard payload.hasPrefix("nearsend:fp:") else { return nil }
        let fp = Self.compact(String(payload.dropFirst("nearsend:fp:".count)))
        let candidates = peers + conversations.map(\.peer)
        guard fp.count >= 16, let match = candidates.first(where: { !$0.fingerprint.isEmpty && Self.compact($0.fingerprint) == fp }) else { return nil }
        verified.insert(match.fingerprint)
        peers = peers.map { var p = $0; p.verified = verified.contains(p.fingerprint); return p }
        save()
        return match.name
    }

    func toggleVerified(_ peer: Peer) {
        guard !peer.fingerprint.isEmpty else { return }
        if verified.contains(peer.fingerprint) { verified.remove(peer.fingerprint) } else { verified.insert(peer.fingerprint) }
        peers = peers.map { var p = $0; p.verified = verified.contains(p.fingerprint); return p }
        save()
    }

    /// Blocks (or unblocks) a phone. Blocking drops everything new from it and removes what it already put on the public
    /// channel, in groups, as announcements and as SOS alerts. Direct chats stay (hidden messages would confuse), but nothing new arrives.
    func toggleBlocked(_ id: String) {
        if blocked.contains(id) { blocked.remove(id); save(); return }
        blocked.insert(id)
        for i in conversations.indices where conversations[i].id == publicChannelID || conversations[i].isGroup {
            conversations[i].messages.removeAll { $0.senderID == id }
        }
        posts.removeAll { $0.from == id }
        alerts.removeAll { $0.from == id }
        peers.removeAll { $0.id == id }
        save()
    }

    func send(_ text: String, in id: String) {
        guard let i = index(id) else { return }
        let m = Message(text: text, date: .now, mine: true, state: .sending)
        conversations[i].messages.append(m)
        save()
        if simulated {
            Task {
                try? await Task.sleep(for: .milliseconds(600)); update(m.id, in: id, .sent)
                try? await Task.sleep(for: .milliseconds(900)); update(m.id, in: id, .delivered)
            }
        } else if id.hasPrefix("g:") {
            groupPending[m.id] = Set(groupTargets(id))
            flushGroup(m, in: id)
        } else if id == publicChannelID {
            if let router {
                router.sendPublic(text, msgID: m.id) { [weak self] outcome in
                    Task { @MainActor in self?.update(m.id, in: id, outcome == .sent ? .sent : .failed) }
                }
            } else { update(m.id, in: id, .failed) }
        } else {
            trySend(m, to: id)
        }
    }

    func retry(_ messageID: String, in id: String) {
        guard let i = index(id), let j = conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[i].messages[j].state = .sending
        conversations[i].messages[j].date = .now
        photoTries[messageID] = nil; photoSentAt[messageID] = nil
        if id.hasPrefix("g:") { groupPending[messageID] = Set(groupTargets(id)).subtracting(groupAcks[messageID] ?? []) }
        flushOutbox()
    }

    private func trySend(_ m: Message, to id: String) {
        guard let router, !inflight.contains(m.id) else { return }
        inflight.insert(m.id)
        router.sendText(m.text, to: id, msgID: m.id) { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                self.inflight.remove(m.id)
                switch outcome {
                case .sent: self.update(m.id, in: id, .sent)
                case .failed: self.update(m.id, in: id, .failed)
                case .carried: self.handed.insert(m.id); self.update(m.id, in: id, .relayed)   // a phone nearby carries it
                case .held: self.handed.insert(m.id)                                            // we carry it ourselves
                case .unreachable: break          // stays queued until the person comes into range
                }
            }
        }
    }

    /// Sends queued messages whose recipient is now reachable; gives up after 10 minutes.
    private func flushOutbox() {
        guard !simulated else { return }
        for c in conversations where c.id != publicChannelID {
            if c.isGroup {
                for m in c.messages where m.mine && !(groupPending[m.id]?.isEmpty ?? true) {
                    if Date().timeIntervalSince(m.date) > 600 {
                        groupPending[m.id] = nil
                        if m.state == .sending { update(m.id, in: c.id, .failed) }
                    } else { flushGroup(m, in: c.id) }
                }
                continue
            }
            // Sent but no receipt: the receipt (or the message) was lost. Send it again while they are in range; the
            // receiver answers a repeat with a fresh receipt. Every 20 s, at most 5 times.
            for m in c.messages where m.mine && m.state == .sent && m.photo == nil && peers.contains(where: { $0.id == c.id }) {
                let last = receiptTries[m.id]
                guard (last?.count ?? 0) < 5, Date().timeIntervalSince(last?.at ?? m.date) > 20 else { continue }
                receiptTries[m.id] = (.now, (last?.count ?? 0) + 1)
                trySend(m, to: c.id)
            }
            // Photos and voice notes: sent again (every 30 s, at most 4 times) until their receipt arrives.
            for m in c.messages where m.mine && m.photo != nil && (m.state == .sending || m.state == .sent) { flushPhoto(m, in: c.id) }
            for m in c.messages where m.mine && m.state == .sending {
                if m.photo != nil { continue }
                // Contacts whose key we have get a day (phones nearby carry the message); others 10 minutes.
                let carried = keyBook.key(c.id) != nil
                if Date().timeIntervalSince(m.date) > (carried ? MeshRouter.holdTime : 600) { update(m.id, in: c.id, .failed) }
                else if peers.contains(where: { $0.id == c.id }) || (carried && !handed.contains(m.id)) { trySend(m, to: c.id) }
            }
        }
    }

    private func setPeers(_ list: [Peer]) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        let known = Set(peers.map { $0.id })
        var mapped = list.filter { !blocked.contains($0.id) }.map { p -> Peer in
            var q = p; q.verified = verified.contains(q.fingerprint)
            // Someone who hides from strangers: we have a chat with them, so keep the name and picture we know.
            if q.name == Self.hiddenName, let c = conversations.first(where: { $0.id == q.id }), c.peer.name != Self.hiddenName {
                q.name = c.peer.name; q.avatar = q.avatar ?? c.peer.avatar
            }
            return q
        }
        mapped.sort { $0.hops == $1.hops ? $0.rssi > $1.rssi : $0.hops < $1.hops }
        if mapped.contains(where: { !known.contains($0.id) }) { Notifier.peerHaptic() }
        friendsArrived(mapped.filter { !known.contains($0.id) })
        peers = mapped
        for p in mapped { if let i = index(p.id) { conversations[i].peer = p } }
        flushOutbox()
    }

    private func receiveText(from: String, name: String, text: String, hops: Int, id: String) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from), let request = strangerGate(from) else { return }
        let peer = peers.first { $0.id == from } ?? Peer(id: from, name: name, hops: hops, rssi: -80)
        ensureConversation(peer)
        guard let i = index(from), !conversations[i].messages.contains(where: { $0.id == id }) else { return }
        if request { conversations[i].request = true }
        conversations[i].messages.append(Message(id: id, text: text, date: .now, mine: false, hops: hops))
        if activeConversation != from { conversations[i].unread += 1 }
        if conversations[i].isRequest { alert(from, title: localized("Message request"), body: peer.name) }
        else { alert(from, title: name, body: preview(text)) }
        if conversations.first(where: { $0.id == from })?.isMuted != true { Notifier.messageHaptic() }
        save()
    }

    private func receivePublic(from: String, name: String, text: String, id: String) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from), let i = index(publicChannelID), !conversations[i].messages.contains(where: { $0.id == id }) else { return }
        conversations[i].messages.append(Message(id: id, text: text, date: .now, mine: false, sender: name, senderID: from))
        if activeConversation != publicChannelID { conversations[i].unread += 1 }
        alert(publicChannelID, title: "#nearby · \(name)", body: preview(text))
        save()
    }

    private func markDelivered(_ id: String) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        if id.hasPrefix("r:") {   // read receipt for one of our private messages
            let mid = String(id.dropFirst(2))
            for c in conversations where !c.isGroup && c.messages.contains(where: { $0.id == mid }) { update(mid, in: c.id, .read) }
            return
        }
        if id.contains(".") {   // a group copy "<message id>.<member>": delivered once every member confirmed
            let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, let c = conversations.first(where: { $0.messages.contains { $0.id == parts[0] } }) else { return }
            groupAcks[parts[0], default: []].insert(parts[1])
            if Set(groupTargets(c.id)).isSubset(of: groupAcks[parts[0]] ?? []) { update(parts[0], in: c.id, .delivered); groupAcks[parts[0]] = nil }
            return
        }
        for c in conversations where c.messages.contains(where: { $0.id == id }) { update(id, in: c.id, .delivered) }
    }

    private func update(_ mid: String, in id: String, _ s: DeliveryState) {
        guard let i = index(id), let j = conversations[i].messages.firstIndex(where: { $0.id == mid }) else { return }
        let now = conversations[i].messages[j].state
        if now == .read { return }                                    // never downgrade
        if now == .delivered && s != .delivered && s != .read { return }
        conversations[i].messages[j].state = s
        if (s == .delivered || s == .read) && conversations[i].messages[j].deliveredAt == nil { conversations[i].messages[j].deliveredAt = .now }
        if s == .read && conversations[i].messages[j].readAt == nil { conversations[i].messages[j].readAt = .now }
        save()
    }

    // MARK: keys, announcements, pictures, photos, privacy

    private func preview(_ text: String) -> String { hidePreviews ? localized("New message") : text }

    /// True when phones nearby can carry messages to this person while they are away (we have their key).
    func canCarryTo(_ id: String) -> Bool { keyBook.key(id) != nil }

    private func keepKeysFor() -> Set<String> {
        var ids = Set<String>()
        for c in conversations { ids.insert(c.id); for m in c.members ?? [] { ids.insert(m.id) } }
        ids.remove(deviceID); ids.remove(publicChannelID)
        return ids
    }

    /// A key was seen: keep it for people we have a chat or a group with, so we can still write to them when they are away.
    private func learnKey(_ id: String, _ pk: Data) {
        guard keyBook.key(id) == nil, keepKeysFor().contains(id) else { return }
        var all = keyBook.all(); all[id] = pk; keyBook.replace(all)
        save()
    }

    func post(_ text: String, hours: Int) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let id = UUID().uuidString
        let exp = Date().addingTimeInterval(Double(hours) * 3600)
        router?.sendPost(clean, postID: id, exp: Int64(exp.timeIntervalSince1970 * 1000))
        posts.insert(Post(id: id, from: deviceID, name: nickname, text: MeshRouter.clip(clean), exp: exp, mine: true), at: 0)
    }

    private func receivePost(from: String, name sent: String, post: String, text: String, exp: Int64, hops: Int) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from), !posts.contains(where: { $0.id == post }) else { return }
        let name = peers.first { $0.id == from }?.name ?? sent
        posts.insert(Post(id: post, from: from, name: name, text: text, exp: Date(timeIntervalSince1970: Double(exp) / 1000), mine: false, hops: hops), at: 0)
        if showAnnouncements { Notifier.notify(title: "\u{1F4E2} \(name)", body: preview(text)) }
    }

    /// Drops expired announcements and, if auto-delete is on, messages older than the chosen number of days.
    private func prune() {
        let now = Date()
        if posts.contains(where: { $0.exp <= now }) { posts.removeAll { $0.exp <= now } }
        guard autoDeleteDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(autoDeleteDays) * 86400)
        guard conversations.contains(where: { $0.messages.contains { $0.date < cutoff } }) else { return }
        for c in conversations { for m in c.messages where m.date < cutoff { if let p = m.photo { try? FileManager.default.removeItem(at: Self.photoURL(p)); photoCache.removeObject(forKey: p as NSString) } } }
        for i in conversations.indices { conversations[i].messages.removeAll { $0.date < cutoff } }
        save()
    }

    /// Sets our picture ("<emoji>|<colour>", see Avatars) or clears it (nil = show the initial). Goes out with the next announcement.
    func changeAvatar(_ a: String?) {
        myAvatar = a; router?.myAvatar = a
        UserDefaults.standard.set(true, forKey: "avatarChosen")   // a picture removed on purpose stays removed
        if let a { UserDefaults.standard.set(a, forKey: "avatar") } else { UserDefaults.standard.removeObject(forKey: "avatar") }
    }

    private static var photosDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("photos", isDirectory: true)
    }
    private static func photoURL(_ id: String) -> URL {
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        return photosDir.appendingPathComponent(id + ".img")
    }

    /// Bytes of a stored photo (what went over Bluetooth), or nil when it is missing.
    func photoSize(_ id: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: Self.photoURL(id).path))?[.size] as? Int
    }

    func loadPhoto(_ id: String) -> UIImage? {
        if let cached = photoCache.object(forKey: id as NSString) { return cached }
        guard let img = UIImage(contentsOfFile: Self.photoURL(id).path) else { return nil }
        photoCache.setObject(img, forKey: id as NSString)
        return img
    }

    /// Shrinks the picture, keeps it on this phone and sends it as soon as the contact is in direct range.
    func sendPhoto(_ data: Data, in id: String) {
        guard id != publicChannelID, !id.hasPrefix("g:"), index(id) != nil else { return }
        // Shrinking a big picture takes a moment: do it off the main thread so the screen does not stall.
        Task { [weak self] in
            let bytes = await Task.detached(priority: .userInitiated) { Photos.compress(data) }.value
            self?.addPhoto(bytes, in: id)
        }
    }

    /// A recorded voice note (an .m4a file): sent to the contact like a photo.
    func sendVoice(_ bytes: Data, in id: String) {
        guard id != publicChannelID, !id.hasPrefix("g:"), VoiceNote.looksLikeAudio(bytes) else { return }
        addPhoto(bytes, in: id, voice: true)
    }

    /// Where a voice note's bytes are kept, for playing it.
    func mediaData(_ id: String) -> Data? { try? Data(contentsOf: Self.photoURL(id)) }

    private func addPhoto(_ bytes: Data?, in id: String, voice: Bool = false) {
        guard let i = index(id) else { return }
        guard let bytes else { photoError = true; return }
        let pid = UUID().uuidString
        guard (try? bytes.write(to: Self.photoURL(pid), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { photoError = true; return }
        var m = Message(id: pid, text: "", date: .now, mine: true, state: .sending, photo: pid)
        if voice { m.voice = true }
        conversations[i].messages.append(m)
        save()
        if simulated {
            Task {
                try? await Task.sleep(for: .milliseconds(900)); update(m.id, in: id, .sent)
                try? await Task.sleep(for: .milliseconds(900)); update(m.id, in: id, .delivered)
            }
        } else { flushPhoto(m, in: id) }
    }

    /// Sends a waiting photo when its person is a direct neighbour; sends it again if no receipt came, then gives up.
    private func flushPhoto(_ m: Message, in cid: String) {
        guard let router, let pid = m.photo else { return }
        if Date().timeIntervalSince(m.date) > MeshRouter.holdTime { update(m.id, in: cid, .failed); return }
        guard peers.contains(where: { $0.id == cid && $0.hops == 1 }) else { return }
        if let last = photoSentAt[m.id], Date().timeIntervalSince(last) < 30 { return }           // chunks are out, waiting for the receipt
        if (photoTries[m.id] ?? 0) >= 4 { update(m.id, in: cid, .failed); return }
        guard let bytes = try? Data(contentsOf: Self.photoURL(pid)) else { update(m.id, in: cid, .failed); return }
        let key = "photo." + m.id
        guard !inflight.contains(key) else { return }
        inflight.insert(key); photoTries[m.id, default: 0] += 1
        router.sendPhoto(bytes, to: cid, photoID: m.id, progress: { [weak self] f in Task { @MainActor in self?.photoProgress[m.id] = f } }) { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                self.inflight.remove(key); self.photoProgress[m.id] = nil
                switch outcome {
                case .sent: self.photoSentAt[m.id] = Date(); self.update(m.id, in: cid, .sent)   // all pieces out; receipt next
                case .failed: self.photoSentAt[m.id] = Date().addingTimeInterval(-20)             // try again soon
                default: self.photoTries[m.id, default: 1] -= 1                                    // person walked away: not a try
                }
            }
        }
    }

    private func receivePhoto(from: String, name sent: String, photo: String, bytes: Data) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from), let request = strangerGate(from) else { return }
        let peer = peers.first { $0.id == from } ?? Peer(id: from, name: sent, hops: 1, rssi: -80)
        ensureConversation(peer)
        guard let i = index(from), !conversations[i].messages.contains(where: { $0.id == photo }) else { return }
        if request { conversations[i].request = true }
        guard (try? bytes.write(to: Self.photoURL(photo), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return }
        var m = Message(id: photo, text: "", date: .now, mine: false, photo: photo)
        if VoiceNote.looksLikeAudio(bytes) { m.voice = true }
        conversations[i].messages.append(m)
        if activeConversation != from { conversations[i].unread += 1 }
        alert(from, title: peer.name, body: hidePreviews ? localized("New message") : (m.mediaLabel ?? ""))
        if conversations.first(where: { $0.id == from })?.isMuted != true { Notifier.messageHaptic() }
        save()
    }

    /// Sends our last known position as a map link. `done(false)` when there is no permission or no position yet.
    func sendLocation(in id: String, done: @escaping (Bool) -> Void) {
        guard hasLocationPermission else { requestLocation(); done(false); return }
        useLocation(true)
        Task {
            for _ in 0..<10 where myLocation == nil { try? await Task.sleep(for: .milliseconds(500)) }
            var ok = false
            if let l = myLocation {
                send(String(format: "\u{1F4CD} https://www.openstreetmap.org/?mlat=%.5f&mlon=%.5f", locale: Locale(identifier: "en_US_POSIX"),
                            l.coordinate.latitude, l.coordinate.longitude), in: id)
                ok = true
            }
            useLocation(false)
            done(ok)
        }
    }

    // MARK: groups

    func createGroup(name: String, people: [Peer]) -> String {
        let id = "g:" + UUID().uuidString
        let members = [Member(id: deviceID, name: nickname)] + people.map { Member(id: $0.id, name: $0.name) }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations.append(Conversation(id: id, peer: Peer(id: id, name: title, hops: 1, rssi: -50), messages: [], members: members))
        save()
        return id
    }

    /// Local only: this phone forgets the group and ignores its new messages. The others are not told.
    func leaveGroup(_ id: String) {
        conversations.removeAll { $0.id == id }
        leftGroups.insert(id)
        save()
    }

    // MARK: chat list and message actions (local only, nothing is sent)

    func togglePin(_ id: String) {
        guard let i = index(id) else { return }
        if conversations[i].isPinned { conversations[i].pinnedAt = nil }
        else {
            // like WhatsApp: at most 3 pinned chats, the oldest pin makes room
            let pinned = conversations.indices.filter { conversations[$0].isPinned }.sorted { conversations[$0].pinnedAt! < conversations[$1].pinnedAt! }
            if pinned.count >= 3 { conversations[pinned[0]].pinnedAt = nil }
            conversations[i].pinnedAt = .now
        }
        save()
    }
    func toggleMute(_ id: String) { guard let i = index(id) else { return }; conversations[i].muted = conversations[i].isMuted ? nil : true; save() }
    func toggleLock(_ id: String) { guard let i = index(id) else { return }; conversations[i].locked = conversations[i].isLocked ? nil : true; save() }
    func toggleFavorite(_ id: String) { guard let i = index(id) else { return }; conversations[i].favorite = conversations[i].isFavorite ? nil : true; save() }
    func toggleUnread(_ id: String) { guard let i = index(id) else { return }; conversations[i].unread = conversations[i].unread > 0 ? 0 : 1; save() }

    /// Empties a chat but keeps it in the list.
    func clearChat(_ id: String) {
        guard let i = index(id) else { return }
        for m in conversations[i].messages { if let p = m.photo { try? FileManager.default.removeItem(at: Self.photoURL(p)); photoCache.removeObject(forKey: p as NSString) } }
        conversations[i].messages.removeAll(); conversations[i].unread = 0; conversations[i].pinnedMessage = nil
        save()
    }

    /// Deletes one message from this phone ("Delete for me").
    func deleteMessage(_ mid: String, in id: String) {
        guard let i = index(id), let j = conversations[i].messages.firstIndex(where: { $0.id == mid }) else { return }
        if let p = conversations[i].messages[j].photo { try? FileManager.default.removeItem(at: Self.photoURL(p)); photoCache.removeObject(forKey: p as NSString) }
        conversations[i].messages.remove(at: j)
        if conversations[i].pinnedMessage == mid { conversations[i].pinnedMessage = nil }
        save()
    }

    func pinMessage(_ mid: String?, in id: String) { guard let i = index(id) else { return }; conversations[i].pinnedMessage = mid; save() }

    /// Notification for a new message, unless the chat is muted; locked chats never show the text.
    private func alert(_ cid: String, title: String, body: String) {
        let c = conversations.first { $0.id == cid }
        guard c?.isMuted != true else { return }
        let appLocked = UserDefaults.standard.bool(forKey: "appLock")   // App lock: no message text on the Lock Screen
        Notifier.notify(title: c?.isLocked == true ? localized("Locked chat") : title,
                        body: c?.isLocked == true || appLocked ? localized("New message") : body)
    }

    /// Local only. A private chat or group is removed from this phone (a group is left, so its new messages are ignored);
    /// the Nearby channel always stays, so it is only emptied. New messages from the same person start a new chat.
    func deleteConversation(_ id: String) {
        if id == publicChannelID {
            guard let i = index(id) else { return }
            conversations[i].messages.removeAll()
            conversations[i].unread = 0
            save()
        } else if id.hasPrefix("g:") {
            leaveGroup(id)
        } else {
            conversations.removeAll { $0.id == id }
            save()
        }
    }

    func isMe(_ id: String) -> Bool { id == deviceID }

    private func groupTargets(_ id: String) -> [String] {
        (conversations.first { $0.id == id }?.members ?? []).map(\.id).filter { $0 != deviceID }
    }

    /// Sends the copies of `m` whose member is in range now; the rest wait in `groupPending`.
    private func flushGroup(_ m: Message, in gid: String) {
        guard let router, let c = conversations.first(where: { $0.id == gid }), let pending = groupPending[m.id] else { return }
        let members = (c.members ?? []).map { (id: $0.id, name: $0.id == deviceID ? nickname : $0.name) }
        for member in pending where peers.contains(where: { $0.id == member }) || keyBook.key(member) != nil {
            let key = "\(m.id).\(member)"
            guard !inflight.contains(key) else { continue }
            inflight.insert(key)
            router.sendGroup(m.text, group: gid, groupName: c.peer.name, members: members, to: member, msgID: m.id) { [weak self] outcome in
                Task { @MainActor in
                    guard let self else { return }
                    self.inflight.remove(key)
                    if outcome != .unreachable { self.groupPending[m.id]?.remove(member) }
                    let sending = self.conversations.first { $0.id == gid }?.messages.first { $0.id == m.id }?.state == .sending
                    if outcome == .sent { self.update(m.id, in: gid, .sent) }
                    else if outcome == .carried, sending { self.update(m.id, in: gid, .relayed) }
                    else if outcome == .failed, sending, self.groupPending[m.id]?.isEmpty ?? true { self.update(m.id, in: gid, .failed) }
                }
            }
        }
    }

    private func receiveGroup(from: String, name sent: String, group gid: String, groupName: String, members: [Member], text: String, hops: Int, id: String) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from), !leftGroups.contains(gid), members.contains(where: { $0.id == deviceID }) else { return }
        let name = peers.first { $0.id == from }?.name ?? sent
        if index(gid) == nil {
            // A new group from someone we have no chat with follows the strangers setting too.
            guard let request = strangerGate(from) else { return }
            conversations.append(Conversation(id: gid, peer: Peer(id: gid, name: groupName, hops: 1, rssi: -50), messages: [], members: members,
                                              request: request ? true : nil))
        }
        guard let i = index(gid), !conversations[i].messages.contains(where: { $0.id == id }) else { return }
        conversations[i].peer.name = groupName
        conversations[i].members = members
        conversations[i].messages.append(Message(id: id, text: text, date: .now, mine: false, hops: hops, sender: name, senderID: from))
        if activeConversation != gid { conversations[i].unread += 1 }
        alert(gid, title: "\(groupName) · \(name)", body: preview(text))
        Notifier.messageHaptic()
        save()
    }

    // MARK: SOS

    var activeAlerts: Int { alerts.filter(\.active).count }
    var hasLocationPermission: Bool { locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways }
    func requestLocation() { location.request() }

    func startSos() {
        guard mySos == nil else { return }
        mySos = UUID().uuidString
        useLocation(true)
        sendSosNow()
        sosTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.sendSosNow() } }
    }

    func stopSos() {
        guard let alarm = mySos else { return }
        mySos = nil
        sosTimer?.invalidate(); sosTimer = nil
        router?.sendSos(alarm: alarm, note: nil, loc: nil, end: true)
        useLocation(false)
    }

    private func sendSosNow() {
        guard let alarm = mySos else { return }
        router?.sendSos(alarm: alarm, note: sosNote, loc: sharedLocation)
    }

    /// "lat,lon,accuracy" when the user chose to attach it and we have a fix.
    private var sharedLocation: String? {
        guard shareLocation, let l = myLocation else { return nil }
        return String(format: "%.5f,%.5f,%ld", locale: Locale(identifier: "en_US_POSIX"),
                      l.coordinate.latitude, l.coordinate.longitude, Int(l.horizontalAccuracy.rounded()))
    }

    /// The SOS screen (for distances) and an active alarm each hold a "use"; GPS runs only while someone needs it.
    func useLocation(_ on: Bool) {
        locationUsers = max(0, locationUsers + (on ? 1 : -1))
        if locationUsers > 0 && hasLocationPermission { location.start() } else { location.stop() }
    }

    private func locationChanged(_ s: CLAuthorizationStatus) {
        locationStatus = s
        if locationUsers > 0 && hasLocationPermission { location.start() }
    }

    private func receiveSos(from: String, name sent: String, alarm: String, note: String?, loc: String?, hops: Int) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        guard !blocked.contains(from) else { return }
        let parts = loc?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let p = parts?.count == 3 ? parts : nil
        let name = peers.first { $0.id == from }?.name ?? sent
        let a = SosAlert(alarm: alarm, from: from, name: name, note: note, lat: p?[0], lon: p?[1], accuracy: p.map { Int($0[2].rounded()) },
                         hops: hops, date: .now)
        if let i = alerts.firstIndex(where: { $0.alarm == alarm && $0.from == from }) {
            let wasActive = alerts[i].active
            alerts[i] = a
            if !wasActive { Notifier.alarm(title: "SOS · \(name)", body: note ?? "") }
        } else {
            alerts.insert(a, at: 0)
            Notifier.alarm(title: "SOS · \(name)", body: note ?? "")
        }
    }

    private func endSos(from: String, alarm: String) {
        guard !simulated else { return }   // demo mode: Bluetooth input is ignored
        for i in alerts.indices where alerts[i].from == from && alerts[i].alarm == alarm { alerts[i].active = false }
    }

    private func ensurePublicChannel() {
        if index(publicChannelID) == nil {
            conversations.insert(Conversation(id: publicChannelID, peer: Peer(id: publicChannelID, name: "Nearby", hops: 1, rssi: -50), messages: []), at: 0)
        }
    }

    // MARK: persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat.json")
    }

    /// Writes the chat file soon (after a short pause), so a burst of changes is one write instead of many.
    private func save() {
        guard !simulated, !savePending else { return }
        savePending = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            savePending = false
            saveNow()
        }
    }

    /// Writes the chat file now. Also runs when the app goes to the background or is closed.
    func saveNow() {
        guard !simulated else { return }
        let keep = keepKeysFor()
        let keys = keyBook.all().filter { keep.contains($0.key) }.mapValues { $0.base64EncodedString() }
        let state = SavedState(nickname: nickname, conversations: conversations, verified: Array(verified), leftGroups: Array(leftGroups), keys: keys, blocked: Array(blocked))
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL), let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        conversations = s.conversations
        verified = Set(s.verified)
        leftGroups = Set(s.leftGroups ?? [])
        blocked = Set(s.blocked ?? [])
        keyBook.replace((s.keys ?? [:]).compactMapValues { Data(base64Encoded: $0) })
        prune()
        // Group messages still "sending" go to every member again (who is pending is not saved).
        for c in conversations where c.isGroup {
            for m in c.messages where m.mine && m.state == .sending { groupPending[m.id] = Set(groupTargets(c.id)) }
        }
        // Messages still marked "sending" stay queued; they are retried when the person is next in range.
    }

    // MARK: demo data (simulator)

    private func seed() {
        peers = [
            Peer(id: "a", name: "Maja", hops: 1, rssi: -48, verified: true, fingerprint: "DEMO", avatar: Avatars.encode(Avatars.emojis[6], 1)),
            Peer(id: "b", name: "Erik", hops: 1, rssi: -66, avatar: Avatars.encode(Avatars.emojis[21], 3)),
            Peer(id: "c", name: "Noor", hops: 2, rssi: -78, via: "b", avatar: Avatars.encode(Avatars.emojis[13], 2)),
            Peer(id: "d", name: "Luca", hops: 3, rssi: -88, via: "c"),
            Peer(id: "e", name: "Sofia", hops: 2, rssi: -72, verified: true, via: "a", avatar: Avatars.encode(Avatars.emojis[9], 5)),
        ]
        let now = Date()
        conversations = [
            Conversation(id: publicChannelID, peer: Peer(id: publicChannelID, name: "Nearby", hops: 1, rssi: -50), messages: [
                Message(text: "Anyone near the main stage?", date: now.addingTimeInterval(-300), mine: false, sender: "Luca"),
                Message(text: "Yes, by the left speaker", date: now.addingTimeInterval(-240), mine: true, state: .sent)], unread: 0),
            Conversation(id: "a", peer: peers[0], messages: [
                Message(text: "Are you at the north gate?", date: now.addingTimeInterval(-900), mine: false),
                Message(text: "Yes, by the water stand", date: now.addingTimeInterval(-840), mine: true),
                Message(text: "Coming now 👋", date: now.addingTimeInterval(-60), mine: false)], unread: 1),
            Conversation(id: "c", peer: peers[2], messages: [
                Message(text: "Relayed through Erik, nice range", date: now.addingTimeInterval(-7200), mine: false, hops: 2)]),
            Conversation(id: "g:demo", peer: Peer(id: "g:demo", name: "Festival crew", hops: 1, rssi: -50), messages: [
                Message(text: "Meet at the food trucks at 8?", date: now.addingTimeInterval(-1500), mine: false, sender: "Maja"),
                Message(text: "Works for me", date: now.addingTimeInterval(-1400), mine: false, hops: 2, sender: "Erik"),
                Message(text: "See you there", date: now.addingTimeInterval(-1300), mine: true)],
                members: [Member(id: deviceID, name: nickname), Member(id: "a", name: "Maja"), Member(id: "b", name: "Erik")]),
        ]
        // Near the simulator's default position (Apple Park), so the SOS tab shows a distance and direction.
        myLocation = CLLocation(latitude: 37.3349, longitude: -122.0090)
        posts = [
            Post(id: "demo-p1", from: "e", name: "Sofia", text: "Free water refills at the info tent until 18:00", exp: now.addingTimeInterval(5 * 3600), mine: false, hops: 2),
            Post(id: "demo-p2", from: "d", name: "Luca", text: "Found: blue backpack near stage B. Ask at the info tent.", exp: now.addingTimeInterval(40 * 60), mine: false, hops: 3),
        ]
        alerts = [SosAlert(alarm: "demo-sos", from: "c", name: "Noor", note: "Twisted ankle by the lake path",
                           lat: 37.3372, lon: -122.0071, accuracy: 9, hops: 2, date: now.addingTimeInterval(-120))]
    }

    private func drift() {
        Task { while true {
            try? await Task.sleep(for: .seconds(2.5))
            guard simulated else { continue }
            for i in peers.indices { peers[i].rssi = max(-95, min(-40, peers[i].rssi + Int.random(in: -3...3))) }
        } }
    }
}

// MARK: - Move to another phone

/// A transfer file holds this phone's identity (private key, id, name, picture), its chats and, optionally, photos and
/// voice notes, sealed with a key made from a password (PBKDF2-SHA256, 600,000 rounds; ChaCha20-Poly1305). Without the
/// password nobody can open it. Layout: "NSXFER1" | salt (16 bytes) | rounds (UInt32, big-endian) | sealed box.
extension ChatStore {
    enum TransferError: LocalizedError {
        case wrongPassword, notATransferFile, noIdentity, simulator
        var errorDescription: String? {
            switch self {
            case .wrongPassword: localized("Wrong password, or the file is damaged.")
            case .notATransferFile: localized("This is not a Nearsend transfer file.")
            case .noIdentity: localized("This phone has no identity to move yet.")
            case .simulator: "Moving to another phone needs a real iPhone."   // simulator only, never shown to users
            }
        }
    }

    private struct Transfer: Codable {
        var v = 1
        var deviceID: String
        var nickname: String
        var avatar: String?
        var key: Data
        var state: Data?
        var photos: [String: Data]
    }

    private static let transferMagic = Data("NSXFER1".utf8)
    private static let transferAAD = Data("nearsend-transfer-v1".utf8)
    private static let transferRounds: UInt32 = 600_000

    private static func transferKey(_ password: String, salt: Data, rounds: UInt32) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        salt.withUnsafeBytes { s in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &out, out.count)
        }
        return SymmetricKey(data: out)
    }

    /// Writes the transfer file to a temporary folder and returns it, to be shared (AirDrop, Files…).
    func makeTransferFile(password: String, includePhotos: Bool) throws -> URL {
        guard !simulated else { throw TransferError.simulator }
        saveNow()
        guard let key = KeyStore.exportKey() else { throw TransferError.noIdentity }
        var photos: [String: Data] = [:]
        if includePhotos, let files = try? FileManager.default.contentsOfDirectory(at: Self.photosDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "img" { photos[f.deletingPathExtension().lastPathComponent] = try? Data(contentsOf: f) }
        }
        let t = Transfer(deviceID: deviceID, nickname: nickname, avatar: myAvatar, key: key,
                         state: try? Data(contentsOf: Self.fileURL), photos: photos)
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let box = try ChaChaPoly.seal(try JSONEncoder().encode(t), using: Self.transferKey(password, salt: salt, rounds: Self.transferRounds),
                                      authenticating: Self.transferAAD)
        var rounds = Self.transferRounds.bigEndian
        let file = Self.transferMagic + salt + Data(bytes: &rounds, count: 4) + box.combined
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nearsend transfer \(day).nearsend")
        try file.write(to: url, options: [.atomic, .completeFileProtection])
        NLog.i("app", "transfer file made (\(photos.count) photos)")
        return url
    }

    /// Replaces this phone's identity, chats and settings with the ones in the file. Bluetooth restarts as that identity.
    func restoreTransfer(from url: URL, password: String) throws {
        guard !simulated else { throw TransferError.simulator }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try Data(contentsOf: url)
        let head = Self.transferMagic.count
        guard file.count > head + 20, file.prefix(head) == Self.transferMagic else { throw TransferError.notATransferFile }
        let salt = file.subdata(in: head..<head + 16)
        let rounds = file.subdata(in: head + 16..<head + 20).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard (100_000...5_000_000).contains(rounds) else { throw TransferError.notATransferFile }
        let plain: Data
        do {
            plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: file.subdata(in: head + 20..<file.count)),
                                        using: Self.transferKey(password, salt: salt, rounds: rounds), authenticating: Self.transferAAD)
        } catch { throw TransferError.wrongPassword }
        let t = try JSONDecoder().decode(Transfer.self, from: plain)
        try KeyStore.replace(with: t.key)

        stopSos()
        transport?.stop(); timer?.invalidate()
        router = nil; transport = nil; started = false; inflight = []
        handed = []; posts = []; alerts = []; peers = []; photoProgress = [:]; photoCache.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.photosDir)
        for (id, data) in t.photos { try? data.write(to: Self.photoURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        if let state = t.state { try state.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        else { try? FileManager.default.removeItem(at: Self.fileURL) }
        deviceID = t.deviceID; UserDefaults.standard.set(t.deviceID, forKey: "deviceID")
        nickname = t.nickname
        if let a = t.avatar { changeAvatar(a) }
        conversations = []
        load()
        ensurePublicChannel()
        NLog.i("app", "transfer restored (\(t.photos.count) photos)")
        startIfNeeded()
    }
}
