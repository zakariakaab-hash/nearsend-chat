import SwiftUI

struct NearbyView: View {
    @EnvironmentObject var store: ChatStore
    @State private var chat: Peer?
    @State private var newPost = false
    @State private var bluetoothHelp = false

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
            .sheet(isPresented: $bluetoothHelp) { BluetoothGuideSheet().environmentObject(store) }
            // iOS shows its own "would like to use Bluetooth" alert, whose buttons apps cannot change. If the person taps
            // Close, Bluetooth stays off: open the guide once per launch so they still see where to tap.
            .onChange(of: store.bluetoothState, initial: true) { _, s in
                guard s == "off", !store.simulated, !BluetoothGuideSheet.shownThisLaunch else { return }
                BluetoothGuideSheet.shownThisLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if store.bluetoothState == "off" { bluetoothHelp = true } }
            }
            #if DEBUG
            .onAppear { if UserDefaults.standard.bool(forKey: "btGuide") { bluetoothHelp = true } }   // simulator check: -btGuide YES
            #endif
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
        if !store.simulated && store.bluetoothState == "off" { return "Turn Bluetooth on to find people nearby" }
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
                    if needsSettings {
                        // Off: only Control Center (or Settings > Bluetooth) can switch it on. Not allowed: our own Settings page has the switch.
                        if store.bluetoothState == "off" {
                            Button { bluetoothHelp = true } label: {
                                Label("How to turn on Bluetooth", systemImage: "hand.tap.fill").font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 40)
                                    .foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                            }.padding(.top, 4)
                        } else {
                            Button("Open Settings") { SystemSettings.open() }.font(.footnote.weight(.semibold)).foregroundStyle(Theme.link)
                        }
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

// MARK: - Bluetooth guide

/// Shows where to tap, because iPhone does not let apps switch Bluetooth on. Two short looping animations: Control
/// Center (fastest) and Settings > Bluetooth. Closes by itself as soon as Bluetooth is on.
struct BluetoothGuideSheet: View {
    static var shownThisLaunch = false
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var way = 0

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Theme.inkSecondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
            Text("Turn on Bluetooth").font(.title2.weight(.bold))
            Text("iPhone does not let apps switch Bluetooth on. It takes two taps:")
                .font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            Picker("", selection: $way) {
                Text("Control Center").tag(0)
                Text("Settings").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal)

            Group {
                if way == 0 { ControlCenterDemo() } else { SettingsDemo() }
            }
            .frame(height: 250)
            .accessibilityHidden(true)   // the steps below say the same in words

            VStack(alignment: .leading, spacing: 8) {
                if way == 0 {
                    step(1, "Swipe down from the top-right corner of the screen.")
                    step(2, "Tap the Bluetooth button so it turns blue.")
                } else {
                    step(1, "Open Settings and tap Bluetooth.")
                    step(2, "Turn Bluetooth on. If you see Allow New Connections, tap it.")
                }
            }.padding(.horizontal)

            if store.bluetoothState == "ready" {
                Label("Bluetooth is on", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.secure)
            }
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white).background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: Theme.rButton, style: .continuous))
                .padding(.horizontal).padding(.bottom, 8)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChange(of: store.bluetoothState) { _, s in
            guard s == "ready" else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: "\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Theme.actionBlue, in: Circle())
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The Bluetooth rune, drawn because SF Symbols has no Bluetooth logo.
struct BluetoothGlyph: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.22, 0.3)); path.addLine(to: p(0.78, 0.72)); path.addLine(to: p(0.5, 0.95))
        path.addLine(to: p(0.5, 0.05)); path.addLine(to: p(0.78, 0.28)); path.addLine(to: p(0.22, 0.7))
        return path
    }
}

/// A finger dot: grows slightly while pressing.
private struct Finger: View {
    var pressing: Bool
    var body: some View {
        Circle().fill(Color.white.opacity(0.85)).frame(width: 30, height: 30)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6)
            .scaleEffect(pressing ? 0.8 : 1)
    }
}

/// Loops every 4 s: a finger swipes down from the top-right corner, Control Center slides in, the finger taps Bluetooth,
/// and the button turns blue. With Reduce Motion it shows the last frame, still.
private struct ControlCenterDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            frame(t: reduceMotion ? 3.5 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.2))
        }
    }

    private func frame(t: Double) -> some View {
        let open = min(1, max(0, (t - 0.3) / 0.8))          // Control Center slides in
        let on = t > 2.3                                   // Bluetooth turned on
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let phoneW = min(w * 0.55, 170), phoneH = h - 8
            let px = (w - phoneW) / 2
            let btTile = CGPoint(x: px + phoneW / 2 + 48, y: 8 + 36 + 40)   // third of three centred tiles
            ZStack(alignment: .topLeading) {
                // Phone
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x1B2A4A))
                    .frame(width: phoneW, height: phoneH).offset(x: px, y: 4)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.brandBlue, Theme.nightBlue], startPoint: .top, endPoint: .bottom))
                    .frame(width: phoneW - 10, height: phoneH - 10).offset(x: px + 5, y: 9)
                // Control Center panel
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.55))
                    .frame(width: phoneW - 10, height: (phoneH - 10) * open).offset(x: px + 5, y: 9)
                // Tiles
                HStack(spacing: 8) {
                    tile(Image(systemName: "airplane"), active: false)
                    tile(Image(systemName: "wifi"), active: true)
                    tile(nil, active: on)
                }
                .opacity(open)
                .offset(x: btTile.x - 20 - 2 * (40 + 8), y: btTile.y - 20)
                // Finger: swipe from the top-right corner, then move to the Bluetooth tile and tap.
                let swipeStart = CGPoint(x: px + phoneW - 18, y: 14)
                let swipeEnd = CGPoint(x: px + phoneW - 26, y: phoneH * 0.45)
                let pos: CGPoint = {
                    if t < 0.2 { return swipeStart }
                    if t < 1.1 { let k = (t - 0.2) / 0.9; return mix(swipeStart, swipeEnd, k) }
                    if t < 1.9 { let k = (t - 1.1) / 0.8; return mix(swipeEnd, btTile, k) }
                    return btTile
                }()
                Finger(pressing: (2.0..<2.4).contains(t) || (0.15..<1.1).contains(t))
                    .position(pos)
                    .opacity(t > 3.6 ? 0 : 1)
            }
        }
    }

    private func tile(_ icon: Image?, active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Theme.actionBlue : Color.white.opacity(0.25))
            if let icon { icon.font(.system(size: 17, weight: .semibold)).foregroundStyle(.white) }
            else { BluetoothGlyph().stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)).frame(width: 14, height: 22) }
        }
        .frame(width: 40, height: 40)
    }
}

/// Loops every 4.2 s: Settings → Bluetooth, where the switch is already on but new connections were turned off from
/// Control Center. The finger taps Allow New Connections and the row goes away, as on a real iPhone.
private struct SettingsDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            frame(t: reduceMotion ? 3.5 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.2))
        }
    }

    private func frame(t: Double) -> some View {
        let onBluetoothPage = t > 1.3
        let allowed = t > 2.7
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let phoneW = min(w * 0.55, 170), phoneH = h - 8
            let px = (w - phoneW) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x1B2A4A))
                    .frame(width: phoneW, height: phoneH).offset(x: px, y: 4)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.95))
                    .frame(width: phoneW - 10, height: phoneH - 10).offset(x: px + 5, y: 9)
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if onBluetoothPage { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(height: 18) }
                        else { Text("Settings").font(.system(size: 15, weight: .bold)) }
                    }.foregroundStyle(.black)
                    if onBluetoothPage {
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack { RoundedRectangle(cornerRadius: 6).fill(Color.blue)
                                BluetoothGlyph().stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 9, height: 15) }
                                .frame(width: 24, height: 24)
                            Text(verbatim: "Bluetooth").font(.system(size: 13, weight: .bold))
                            Divider()
                            HStack { Text(verbatim: "Bluetooth").font(.system(size: 11)); Spacer(); toggle(true) }
                        }
                        .padding(8).frame(height: 89)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        if !allowed {
                            Text(verbatim: "Allow New Connections").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.blue).lineLimit(1).minimumScaleFactor(0.6)
                                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .background((2.3..<2.7).contains(t) ? Color(white: 0.85) : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(verbatim: "Turned off from Control Center").font(.system(size: 8)).foregroundStyle(.gray).padding(.horizontal, 4)
                        }
                    } else {
                        row { icon("airplane", .orange); Text(verbatim: "Airplane Mode").font(.system(size: 12)); Spacer() }
                        row { icon("wifi", .blue); Text(verbatim: "Wi-Fi").font(.system(size: 12)); Spacer() }
                        row {
                            ZStack { RoundedRectangle(cornerRadius: 5).fill(Color.blue)
                                BluetoothGlyph().stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)).frame(width: 8, height: 13) }
                                .frame(width: 20, height: 20)
                            Text(verbatim: "Bluetooth").font(.system(size: 12)); Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.gray)
                        }
                        .background((0.8..<1.2).contains(t) ? Color.gray.opacity(0.2) : .clear)
                    }
                }
                .foregroundStyle(.black)
                .padding(10).frame(width: phoneW - 10, alignment: .leading).offset(x: px + 5, y: 36)

                let rowBT = CGPoint(x: px + phoneW * 0.45, y: 36 + 10 + 28 + 2 * 36 - 8)
                let sw = CGPoint(x: px + phoneW * 0.42, y: 36 + 10 + 26 + 89 + 8 + 14)   // Allow New Connections
                let pos: CGPoint = {
                    if t < 0.4 { return CGPoint(x: px + phoneW * 0.5, y: phoneH * 0.8) }
                    if t < 0.8 { return mix(CGPoint(x: px + phoneW * 0.5, y: phoneH * 0.8), rowBT, (t - 0.4) / 0.4) }
                    if t < 1.6 { return rowBT }
                    if t < 2.2 { return mix(rowBT, sw, (t - 1.6) / 0.6) }
                    return sw
                }()
                Finger(pressing: (0.85..<1.2).contains(t) || (2.3..<2.7).contains(t)).position(pos).opacity(t > 3.7 ? 0 : 1)
            }
        }
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6, content: c).padding(.horizontal, 8).frame(height: 28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(color, in: RoundedRectangle(cornerRadius: 5))
    }
    private func toggle(_ on: Bool) -> some View {
        Capsule().fill(on ? Color.green : Color.gray.opacity(0.35)).frame(width: 36, height: 22)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 18, height: 18).padding(2) }
            .animation(.easeInOut(duration: 0.2), value: on)
    }
}

private func mix(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
    let e = k * k * (3 - 2 * k)   // smoothstep
    return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
}
