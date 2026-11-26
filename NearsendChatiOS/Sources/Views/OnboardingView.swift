import SwiftUI

struct OnboardingView: View {
    var done: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: ChatStore
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let pages: [(icon: String, title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("nosignal", "Chat without internet", "Messages hop phone to phone over Bluetooth. No signal, no SIM, no account."),
        ("relay", "Every phone is a relay", "The more people nearby, the further your message travels."),
        ("lock.shield.fill", "Private by design", "Direct messages are end-to-end encrypted. Nothing is stored on a server."),
    ]

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 0) {
                HStack {
                    Text(verbatim: "NEARSEND").font(Theme.display(22)).foregroundStyle(.white)
                    Spacer()
                }.padding(.horizontal, 24).padding(.top, 8)
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(spacing: 28) {
                            ZStack {
                                RingWaves(animate: !reduceMotion && !PowerMode.shared.lowPower && page == i)
                                Group {
                                    if pages[i].icon == "nosignal" { NoSignalIcon().frame(width: 50, height: 50) }
                                    else if pages[i].icon == "relay" { RelayIcon(animate: !reduceMotion && !PowerMode.shared.lowPower && page == i).frame(width: 56, height: 56) }
                                    else { Image(systemName: pages[i].icon).font(.system(size: 46, weight: .regular)) }
                                }
                                    .foregroundStyle(Theme.actionBlue)
                                    .frame(width: 112, height: 112)
                                    .glass(radius: 56)
                            }.frame(height: 270).accessibilityHidden(true)
                            VStack(spacing: 16) {
                                Text(pages[i].title).textCase(.uppercase).font(Theme.display(40)).foregroundStyle(.white)
                                    .multilineTextAlignment(.center).shadow(color: Color(hex: 0x0C2444, opacity: 0.35), radius: 8, y: 2)
                                    .accessibilityAddTraits(.isHeader)
                                SkyPill { Text(pages[i].body).font(.body.weight(.medium)).multilineTextAlignment(.center) }
                            }.padding(.horizontal, 24)
                        }.tag(i)
                    }
                    namePage.tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                PrimaryButton(title: page == pages.count ? "Allow Bluetooth & start" : "Continue") {
                    if page == pages.count { finish() } else { withAnimation { page += 1 } }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }

    }

    /// Page 4: the name people nearby see. Prefilled with the random one, so skipping it is fine.
    private var namePage: some View {
        VStack(spacing: 24) {
            Avatar(name: name.isEmpty ? store.nickname : name, size: 112, avatar: store.myAvatar).accessibilityHidden(true)
                .frame(height: 200)
            VStack(spacing: 16) {
                Text("Your name on the radar").textCase(.uppercase).font(Theme.display(40)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .shadow(color: Color(hex: 0x0C2444, opacity: 0.35), radius: 8, y: 2).accessibilityAddTraits(.isHeader)
                // Empty with the random name as the hint: leaving it empty keeps that name.
                TextField(text: $name, prompt: Text(verbatim: store.nickname)) { Text("Your name") }
                    .font(.system(.title2, design: .rounded, weight: .semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink).focused($nameFocused).submitLabel(.done)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
                    .onSubmit { nameFocused = false }
                    .padding(.vertical, 14).padding(.horizontal, 16).glass(radius: Theme.rField)
                SkyPill { Text("People nearby see this name. No account, no phone number. You can change it any time on the You tab.").font(.body.weight(.medium)).multilineTextAlignment(.center) }
            }.padding(.horizontal, 24)
        }
    }

    private func finish() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty, n != store.nickname { store.nickname = n; store.applyNickname() }
        nameFocused = false
        done()
    }
}

/// Page 1's picture: signal bars with a line through them, "no network".
struct NoSignalIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            for (x, top) in [(4.0, 17.0), (9.0, 14.0), (14.0, 11.0), (19.0, 5.0)] {
                p.move(to: CGPoint(x: x * s, y: 20 * s)); p.addLine(to: CGPoint(x: x * s, y: top * s))
            }
            p.move(to: CGPoint(x: 3 * s, y: 3 * s)); p.addLine(to: CGPoint(x: 21 * s, y: 21 * s))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Page 2's picture: three phones joined by dashed links. A message dot hops from phone to phone, and each phone lights up
/// as it arrives. Still (no dot) with Reduce Motion, in Low Power Mode or Battery saver, and when the page is not shown.
struct RelayIcon: View {
    var animate: Bool
    private let a = CGPoint(x: 12, y: 4.5), b = CGPoint(x: 4.5, y: 18), c = CGPoint(x: 19.5, y: 18)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { tl in
            Canvas { ctx, size in draw(&ctx, size: size, t: phase(tl.date)) }
        }
        .accessibilityHidden(true)
    }

    /// 0..<1 through the 3-second loop, or -1 when still.
    private func phase(_ date: Date) -> Double {
        animate ? date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 : -1
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let k = size.width / 24
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }
        var links = Path()
        for (p, q) in [(a, b), (b, c), (c, a)] {
            // stop short of the circles so the dashes do not cross them
            let dx = q.x - p.x, dy = q.y - p.y, len = (dx * dx + dy * dy).squareRoot(), r = 3.2 / len
            links.move(to: pt(CGPoint(x: p.x + dx * r, y: p.y + dy * r)))
            links.addLine(to: pt(CGPoint(x: q.x - dx * r, y: q.y - dy * r)))
        }
        ctx.stroke(links, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, dash: [2 * k, 2.2 * k]))
        for (p, arrive) in [(a, 0.0), (b, 0.25), (c, 0.583)] {
            let circle = Path(ellipseIn: CGRect(x: (p.x - 2.2) * k, y: (p.y - 2.2) * k, width: 4.4 * k, height: 4.4 * k))
            if t >= 0 {
                let d = min(abs(t - arrive), abs(t - arrive - 1), abs(t - arrive + 1))
                let glow = max(0, 1 - d / 0.12)
                if glow > 0 {   // the phone lights up as the message arrives
                    var lit = ctx
                    lit.opacity = glow
                    lit.fill(circle, with: .foreground)
                }
            }
            ctx.stroke(circle, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * k))
        }
        if t >= 0, let m = messagePoint(t) {
            ctx.fill(Path(ellipseIn: CGRect(x: (m.x - 1.2) * k, y: (m.y - 1.2) * k, width: 2.4 * k, height: 2.4 * k)), with: .foreground)
        }
    }

    /// Where the message is: moving A→B, B→C, C→A with a short rest at each phone (rests show no dot).
    private func messagePoint(_ t: Double) -> CGPoint? {
        func lerp(_ p: CGPoint, _ q: CGPoint, _ f: Double) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f) }
        switch t {
        case 0..<0.25: return lerp(a, b, t / 0.25)
        case 0.333..<0.583: return lerp(b, c, (t - 0.333) / 0.25)
        case 0.667..<0.917: return lerp(c, a, (t - 0.667) / 0.25)
        default: return nil
        }
    }
}

/// The rings behind the onboarding icons. Animated, waves ripple out from the icon like a signal and fade at the edge. Still: three plain rings (Reduce Motion, Low Power, Battery saver).
struct RingWaves: View {
    var animate: Bool
    var body: some View {
        if animate {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { ctx, size in draw(&ctx, size: size, time: tl.date.timeIntervalSinceReferenceDate) }
            }
            .frame(width: 270, height: 270)
        } else {
            ZStack {
                ForEach(0..<3) { r in
                    Circle().stroke(.white.opacity(0.5 - Double(r) * 0.14), lineWidth: 1)
                        .frame(width: 130 + CGFloat(r) * 56, height: 130 + CGFloat(r) * 56)
                }
            }
        }
    }
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        // Three waves, one every 1.2 s: from just outside the icon (r 60) to the edge (r 134), fading out.
        for i in 0..<3 {
            let f = ((time / 3.6) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let r = 60 + 74 * f
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.stroke(ring, with: .color(.white.opacity(0.55 * (1 - f))), lineWidth: 1.2)
        }
        let outer: CGFloat = 121
        let faint = Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
        ctx.stroke(faint, with: .color(.white.opacity(0.18)), lineWidth: 1)
    }
}
