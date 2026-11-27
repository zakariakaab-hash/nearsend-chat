import SwiftUI

struct NearbyView: View {
    @EnvironmentObject var store: ChatStore
    @State private var chat: Peer?
    @State private var newPost = false
    @State private var ask: PermissionAsk?
    private static var toldThisLaunch = Set<String>()

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        PageTitle(text: "Nearby").padding(.top, 8)
                        header
                        if showEmpty { emptyCard }
                        Card(padding: 12) {
                            VStack(spacing: 8) {
                                RadarView(peers: store.peers).frame(height: 250)
                                legend
                                Text("Rings show signal strength, not direction.")
                                    .font(.caption).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                            }
                        }
                        peerList
                        if store.showAnnouncements { announcements }
                    }.padding(.horizontal, 20).padding(.bottom, 24).readableWidth()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $chat) { p in ThreadView(conversationID: p.id, peer: p) }
            .sheet(isPresented: $newPost) { NewPostSheet().environmentObject(store) }
            .sheet(item: $ask) { a in PermissionSheet(ask: a) { if a == .bluetoothDenied { SystemSettings.open() } } }
            // Bluetooth off or not allowed: say so once per launch, in a sheet like iOS's own prompts.
            .onChange(of: store.bluetoothState, initial: true) { _, s in
                guard !store.simulated, ["off", "unauthorized"].contains(s), !Self.toldThisLaunch.contains(s) else { return }
                Self.toldThisLaunch.insert(s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if store.bluetoothState == s { ask = s == "off" ? .bluetoothOff : .bluetoothDenied }
                }
            }
        }
    }

    private var statusOK: Bool { store.meshActive && (store.simulated || store.bluetoothState == "ready") }
    private var needsSettings: Bool { !store.simulated && ["off", "unauthorized"].contains(store.bluetoothState) }
    private var statusText: String {
        if !store.meshActive { return "Mesh paused" }
        if store.simulated { return "Demo data" }
        switch store.bluetoothState {
        case "ready": return "Bluetooth live · offline"
        case "off": return "Bluetooth is off"
        case "unauthorized": return "Bluetooth not allowed"
        case "unsupported": return "Bluetooth unsupported"
        default: return "Starting Bluetooth…"
        }
    }
    private var subtitle: String {
        if !store.simulated && store.bluetoothState == "unauthorized" { return "Allow Bluetooth for Nearsend Chat in Settings" }
        if !store.simulated && store.bluetoothState == "off" { return "Bluetooth is off. Turn it on in Control Center to find people nearby." }
        if store.peers.isEmpty && !store.simulated { return "Open the app on another phone to connect" }
        return ""
    }

    private var header: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: LocalizedStringKey(statusText), color: statusOK ? Theme.secure : Theme.inkSecondary)
                    // In range = a direct Bluetooth link. People reached through other phones are counted apart.
                    let direct = max(0, store.peers.count - store.relayedCount)
                    if direct == 1 { Text("1 person in range").font(.title3.weight(.semibold)) }
                    else { Text("\(direct) people in range").font(.title3.weight(.semibold)) }
                    if !subtitle.isEmpty { Text(LocalizedStringKey(subtitle)).font(.footnote).foregroundStyle(Theme.inkSecondary) }
                    else if store.relayedCount > 0 { Text("Plus \(store.relayedCount) through other phones").font(.footnote).foregroundStyle(Theme.inkSecondary) }
                    // Off: only Control Center or Settings can switch Bluetooth on, and the subtitle says so.
                    // Not allowed: our own page in Settings has the switch.
                    if needsSettings && store.bluetoothState == "unauthorized" {
                        Button("Open Settings") { SystemSettings.open() }.font(.footnote.weight(.semibold)).foregroundStyle(Theme.link)
                    }
                }
                Spacer()
                VStack(spacing: 4) {
                    Toggle("Mesh", isOn: $store.meshActive).labelsHidden().tint(Theme.actionBlue)
                    Text(store.meshActive ? "On" : "Paused").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private var announcements: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Announcements").textCase(.uppercase).font(Theme.display(24)).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { newPost = true } label: {
                    HStack(spacing: 2) { Image(systemName: "plus"); Text("Post") }.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
            if store.posts.isEmpty { Card { Text("No announcements nearby.").font(.subheadline).foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity, alignment: .leading) } }
            ForEach(store.posts) { PostCard(post: $0) }
        }
    }

    /// Nobody in range on a working phone: say what is happening and what helps. Bluetooth off is handled by the header.
    private var showEmpty: Bool { store.peers.isEmpty && !store.simulated && store.meshActive && store.bluetoothState == "ready" }
    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("No one in range yet").font(.headline)
                Text("Nearsend Chat reaches phones about 10 to 50 metres away. People show up here when they come close.")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bluetooth is on", systemImage: "checkmark.circle.fill")
                    Label("Your friends need Nearsend Chat too", systemImage: "person.2.fill")
                    Label("Open the app on both phones to connect faster", systemImage: "iphone.radiowaves.left.and.right")
                }.font(.footnote).foregroundStyle(Theme.ink)
                ShareLink(item: URL(string: "https://chat.nearsend.app")!) {
                    Label("Invite friends", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(.white).background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: Theme.rButton, style: .continuous))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Filled dot = direct link, ring = relayed: told apart by shape, not colour alone.
    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) { Circle().fill(Theme.actionBlue).frame(width: 10, height: 10); Text("Direct link") }
            HStack(spacing: 5) { Circle().stroke(Theme.actionBlue, lineWidth: 2).frame(width: 9, height: 9); Text("Via relay") }
        }
        .font(.caption).foregroundStyle(Theme.inkSecondary)
        .accessibilityElement(children: .combine)
    }

    /// People first: direct links before relayed ones, strongest signal first.
    private var sortedPeers: [Peer] { store.peers.sorted { ($0.hops, -$0.rssi) < ($1.hops, -$1.rssi) } }

    private var peerList: some View {
        VStack(spacing: 10) {
            if !store.peers.isEmpty {
                Text("People nearby").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(sortedPeers) { p in
                Button { store.ensureConversation(p); chat = p } label: {
                    Card(padding: 12) {
                        HStack(spacing: 12) {
                            Avatar(name: p.name, online: true, avatar: p.shownAvatar).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(verbatim: p.name).font(.headline)
                                    if p.verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.actionBlue).font(.caption).accessibilityLabel("Verified") }
                                }
                                Text(p.closeness).font(.footnote).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            SignalBars(rssi: p.rssi, hops: p.hops)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct SignalBars: View {
    let rssi: Int
    var hops = 1
    private var level: Int { rssi > -55 ? 4 : rssi > -70 ? 3 : rssi > -82 ? 2 : 1 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= level ? Theme.actionBlue : Theme.inkSecondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal \(level) of 4")
    }
}

/// What Bluetooth can honestly tell: roughly how strong the signal is, never the direction or the exact distance.
extension Peer {
    /// 0 very close, 1 close, 2 far, 3 reached through other phones.
    var band: Int { hops > 1 ? 3 : rssi > -60 ? 0 : rssi > -75 ? 1 : 2 }
    var closeness: LocalizedStringKey {
        switch band {
        case 0: "Very close"
        case 1: "Near"
        case 2: "Far"
        default: hops == 2 ? "Through 1 other phone" : "Through \(hops - 1) other phones"
        }
    }
}

/// Rings by signal strength. People are spread evenly on their ring: where they sit around it means nothing,
/// which the caption under the radar says, so nobody walks off in a direction the app made up.
struct RadarView: View {
    let peers: [Peer]
    @State private var sweep = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var power = PowerMode.shared
    private let tail = 0.16 // fraction of a turn the fading tail covers
    private static let rings: [CGFloat] = [0.34, 0.58, 0.80, 1.0]
    private static let ringNames: [LocalizedStringKey] = ["Very close", "Near", "Far", "Through other phones"]

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle().stroke(Theme.ink.opacity(i == 3 ? 0.06 : 0.12), style: StrokeStyle(lineWidth: 1, dash: i == 3 ? [3, 4] : []))
                        .frame(width: size * Self.rings[i], height: size * Self.rings[i])
                }

                // Thin sweep: shows the app is looking for phones. It says nothing about where they are.
                ZStack {
                    AngularGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 1 - tail),
                        .init(color: Theme.actionBlue.opacity(0.35), location: 0.999),
                        .init(color: .clear, location: 1),
                    ], center: .center)
                    .mask(Circle())
                }
                .frame(width: size, height: size)
                .rotationEffect(.degrees(sweep))

                // Ring names at the top of each ring, where no one is placed.
                ForEach(0..<4, id: \.self) { i in
                    Text(Self.ringNames[i]).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 4).background(Capsule().fill(Theme.glassFill))
                        .position(x: c.x, y: c.y - size * Self.rings[i] / 2)
                }

                Circle().fill(Theme.actionBlue).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: Theme.actionBlue.opacity(0.6), radius: 8)

                ForEach(placed, id: \.peer.id) { item in
                    let r = Self.rings[item.peer.band] * size / 2
                    VStack(spacing: 3) {
                        Circle().fill(item.peer.hops == 1 ? Theme.actionBlue : Color.white)
                            .overlay(Circle().stroke(Theme.actionBlue, lineWidth: 2))
                            .frame(width: 13, height: 13)
                        Text(verbatim: item.peer.name).font(.caption2.weight(.medium)).foregroundStyle(Theme.ink)
                            .dynamicTypeSize(...DynamicTypeSize.large)   // the list below shows every name at full size
                    }
                    .position(x: c.x + cos(item.angle) * r, y: c.y + sin(item.angle) * r)
                    .animation(.easeInOut(duration: 0.6), value: item.peer.band)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radar")
        .accessibilityValue(peers.count == 1 ? "1 person nearby" : "\(peers.count) people nearby")
        .onAppear { updateSweep() }
        .onChange(of: power.lowPower) { _, _ in updateSweep() }
    }

    /// Everyone on a ring gets an equal share of it, leaving the top free for the ring's name. Sorted by id so
    /// people keep their place while the signal changes.
    private var placed: [(peer: Peer, angle: CGFloat)] {
        var out: [(peer: Peer, angle: CGFloat)] = []
        for band in 0..<4 {
            let group = peers.filter { $0.band == band }.sorted { $0.id < $1.id }
            let start = -60.0 + Double(band) * 17, span = 300.0   // degrees, 0 = right, 90 = down; skips the top
            for (k, p) in group.enumerated() {
                let deg = start + span * (Double(k) + 0.5) / Double(group.count)
                out.append((p, CGFloat(deg * .pi / 180)))
            }
        }
        return out
    }

    /// The sweep turns only when motion is allowed and the phone is not in Low Power Mode.
    private func updateSweep() {
        if reduceMotion || power.lowPower { withAnimation(.linear(duration: 0.01)) { sweep = 0 } }
        else { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { sweep = 360 } }
    }
}
