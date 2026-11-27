import AVFoundation
import SwiftUI

/// A small selectable pill (time choices, auto-delete choices).
struct ChipButton<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    var body: some View {
        Button(action: action) {
            label().font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Self.idleText)
                .background(selected ? Theme.actionBlue : Self.idleFill, in: Capsule())
        }.buttonStyle(.plain)
    }
    // Unselected: glass with white text at night (blue on grey failed 4.5:1), deep blue on white by day.
    private static var idleText: Color { Color.adaptive(day: Theme.actionBlueDeep, night: .white) }
    private static var idleFill: Color { Color.adaptive(day: Color.white.opacity(0.7), night: Color.white.opacity(0.16)) }
}

/// Reporting and contact (App Store guideline 1.2). The app has no server, so a report is an email the user sends themself.
enum Support {
    /// PLACEHOLDER: replace with the real support address before release (also in docs/nearsend-chat/PRIVACY.md).
    static let email = "support@nearsend.app"

    static var contactURL: URL? { mail(subject: "Nearsend Chat", body: "") }
    static var feedbackURL: URL? {
        mail(subject: "Nearsend Chat feedback", body: "\n\n---\nApp \(HelpSettingsView.version), iOS \(UIDevice.current.systemVersion)")
    }

    /// A prefilled email reporting `text` (or a whole person when `text` is nil) sent by `name` / `id`.
    static func reportURL(name: String, id: String?, text: String?, date: Date? = nil) -> URL? {
        var body = "Reported person: \(name)\nTheir id: \(id ?? "unknown")\n"
        if let date { body += "Time: \(ISO8601DateFormatter().string(from: date))\n" }
        if let text { body += "Content:\n\(text)\n" }
        body += "\nWhy I am reporting this:\n"
        return mail(subject: "Nearsend Chat report", body: body)
    }

    private static func mail(subject: String, body: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"; c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: subject)] + (body.isEmpty ? [] : [URLQueryItem(name: "body", value: body)])
        return c.url
    }
}

private struct MailOpener: ViewModifier {
    @Binding var pending: URL?
    @Environment(\.openURL) private var openURL
    @State private var noMail = false
    func body(content: Content) -> some View {
        content
            .onChange(of: pending) { _, url in
                guard let url else { return }
                pending = nil
                openURL(url) { ok in if !ok { noMail = true } }
            }
            .alert("No email app. Write to us at:", isPresented: $noMail) {
                Button("Copy address") { UIPasteboard.general.string = Support.email }
                Button("Close", role: .cancel) {}
            } message: { Text(verbatim: Support.email) }
    }
}

extension View {
    /// Opens the mail URL put in `pending` (a report or "Contact us"); if there is no mail app, shows the address instead.
    func opensMail(_ pending: Binding<URL?>) -> some View { modifier(MailOpener(pending: pending)) }

    /// Asks before blocking the phone whose id is in `target`, then blocks it (see `ChatStore.toggleBlocked`).
    @MainActor func blockConfirmation(for target: Binding<String?>, store: ChatStore) -> some View {
        bottomConfirm(isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
                      title: "Block this person?",
                      message: "Their messages and announcements are hidden and ignored. You can unblock them in their contact info.",
                      action: "Block", icon: "hand.raised.fill") { if let id = target.wrappedValue { store.toggleBlocked(id) } }
    }

    /// WhatsApp-style confirmation: a sheet at the bottom with the question, a red action and Cancel, instead of the
    /// floating bubble iOS 26 draws for a confirmation dialog.
    func bottomConfirm(isPresented: Binding<Bool>, title: LocalizedStringKey, message: LocalizedStringKey,
                       action: LocalizedStringKey, icon: String = "trash", perform: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmSheet(title: title, message: message, action: action, icon: icon) {
                perform(); isPresented.wrappedValue = false
            } cancel: { isPresented.wrappedValue = false }
        }
    }
}

struct PostCard: View {
    @EnvironmentObject var store: ChatStore
    let post: Post
    @State private var blockTarget: String?
    @State private var report: URL?
    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "megaphone.fill").font(.title3).foregroundStyle(Theme.actionBlue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: post.mine ? post.name + " (" + localized("You") + ")" : post.name).font(.subheadline.weight(.semibold))
                    Text(verbatim: post.text)
                    HStack(spacing: 4) {
                        left
                        if post.hops > 1 { Text("\u{00B7} \(post.hops) hops") }
                    }.font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if !post.mine {
                Button { report = Support.reportURL(name: post.name, id: post.from, text: post.text) } label: { Label("Report", systemImage: "flag.fill") }
                Button(role: .destructive) { blockTarget = post.from } label: { Label("Block", systemImage: "hand.raised.fill") }
            }
        }
        .blockConfirmation(for: $blockTarget, store: store)
        .opensMail($report)
    }
    @ViewBuilder private var left: some View {
        let secs = post.exp.timeIntervalSinceNow
        if secs >= 3600 { Text("\(Int(secs / 3600)) h left") } else { Text("\(max(1, Int(secs / 60))) min left") }
    }
}

struct NewPostSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var hours = 6

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Text("Announcements").font(.title2.weight(.semibold)).foregroundStyle(.white).padding(.top, 20)
                    TextField("Write an announcement…", text: $text, axis: .vertical).lineLimit(3...6)
                        .foregroundStyle(Theme.ink).padding(14).glass(radius: Theme.rField)
                    Text("Visible for").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        ForEach([1, 6, 24], id: \.self) { h in ChipButton(selected: hours == h, action: { hours = h }) { Text("\(h) h") } }
                        Spacer()
                    }
                    Text("Public · not encrypted. Phones nearby keep it and show it to people who arrive later, until it expires.").font(.footnote).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
                    PrimaryButton(title: "Post announcement") { store.post(text, hours: hours); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }.padding(.horizontal, 20).readableWidth(560)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Choose an emoji and a colour for your picture. Changes apply at once and go out with the next announcement.
struct AvatarPickerSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var emoji: String?
    @State private var color = 0

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Text("Your picture").font(.title2.weight(.semibold)).foregroundStyle(.white).padding(.top, 20)
                    Avatar(name: store.nickname, size: 88, avatar: store.myAvatar).accessibilityHidden(true)
                    Text("Pick an emoji and a colour. People nearby see it next to your name.").font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
                    Card {
                        VStack(spacing: 14) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                                ForEach(Avatars.emojis, id: \.self) { e in
                                    Button { emoji = e; apply() } label: {
                                        Text(e).font(.title).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44)
                                            .background(e == emoji ? Theme.actionBlue.opacity(0.22) : Theme.ink.opacity(0.06), in: Circle())
                                    }.buttonStyle(.plain)
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(0..<Avatars.colors, id: \.self) { i in
                                    Button { color = i; apply() } label: {
                                        Circle().fill(LinearGradient(colors: [avatarColors[i].0, avatarColors[i].1], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 30, height: 30).overlay(Circle().stroke(Theme.ink, lineWidth: i == color ? 3 : 0))
                                    }.buttonStyle(.plain)
                                }
                            }
                            Button("Use my initial") { emoji = nil; color = 0; store.changeAvatar(nil) }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                        }.frame(maxWidth: .infinity)
                    }
                    Button("Close") { dismiss() }.foregroundStyle(.white).padding(.bottom, 20)
                }.padding(.horizontal, 20).readableWidth(560)
            }
        }
        .onAppear { if let c = Avatars.parse(store.myAvatar) { emoji = c.emoji; color = c.color } }
        .presentationDetents([.large])
    }

    private func apply() { store.changeAvatar(emoji.map { Avatars.encode($0, color) }) }
}

/// A photo in a chat: the picture (or a placeholder) with a percentage while it is being sent.
struct PhotoBubble: View {
    let image: UIImage?
    var progress: Double? = nil
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 240) }
            else { Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.white).frame(width: 140, height: 120) }
            if let progress {
                Text(verbatim: "\(Int(progress * 100))%").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.55), in: Capsule())
            }
        }
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The body of `bottomConfirm`: sized to its content, like WhatsApp's delete sheet.
struct ConfirmSheet: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    var icon = "trash"
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var height: CGFloat = 280
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(message).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.bottom, 6)
            Button(role: .destructive) { confirm() } label: {
                Label(action, systemImage: icon).font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
            }
            .foregroundStyle(Color(hex: 0xE5484D)).glass(radius: 16)
            Button { cancel() } label: {
                Text("Cancel").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
            }
            .foregroundStyle(Theme.link).glass(radius: 16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Permission sheets

/// What a permission sheet explains. iOS draws its own alerts and apps cannot style them, so before iOS asks (and when
/// something is off or was refused) the app shows this sheet in the same spirit as iOS's location prompt: icon, title,
/// one honest paragraph, a small picture of what it is for, and large buttons.
enum PermissionAsk: String, Identifiable {
    case bluetooth, bluetoothOff, bluetoothDenied, location, locationDenied, locationServicesOff, cameraDenied, microphoneDenied
    var id: String { rawValue }
    var isBluetooth: Bool { [.bluetooth, .bluetoothOff, .bluetoothDenied].contains(self) }
    var isLocation: Bool { [.location, .locationDenied, .locationServicesOff].contains(self) }
    var symbol: String {
        switch self {
        case .cameraDenied: "camera.fill"
        case .microphoneDenied: "mic.fill"
        default: isBluetooth ? "antenna.radiowaves.left.and.right" : "location.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .bluetooth: "Nearsend Chat uses Bluetooth"
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothDenied: "Bluetooth is not allowed"
        case .location: "Share your location?"
        case .locationDenied: "Location is off for Nearsend Chat"
        case .locationServicesOff: "Location Services is off"
        case .cameraDenied: "Camera is off for Nearsend Chat"
        case .microphoneDenied: "Microphone is off for Nearsend Chat"
        }
    }
    var message: LocalizedStringKey {
        switch self {
        case .bluetooth: "It finds phones nearby and sends them your messages, with no internet. Your iPhone asks next: tap Allow."
        case .bluetoothOff: "Nearsend Chat needs Bluetooth to find people nearby. Tap Turn on Bluetooth, then Settings, and switch Bluetooth on. If you see Allow New Connections, tap it."
        case .bluetoothDenied: "Nearsend Chat needs Bluetooth to find people nearby. Turn it on in Settings › Nearsend Chat › Bluetooth."
        case .location: "Only when you share it in a chat or attach it to an SOS. It goes over Bluetooth to the people you choose, never to us. Your iPhone asks next."
        case .locationDenied: "To share your position, allow location in Settings › Nearsend Chat › Location."
        case .locationServicesOff: "Attaching your position needs Location Services. Tap Turn on Location Services, then Settings, and switch it on."
        case .cameraDenied: "To take photos and scan QR codes, allow the camera in Settings › Nearsend Chat › Camera."
        case .microphoneDenied: "To record voice notes, allow the microphone in Settings › Nearsend Chat › Microphone."
        }
    }
    var chip: LocalizedStringKey {
        switch self {
        case .bluetooth, .bluetoothOff, .bluetoothDenied: "No internet needed"
        case .location, .locationDenied, .locationServicesOff: "Only when you share"
        case .cameraDenied, .microphoneDenied: "Only while you use it"
        }
    }
    var primary: LocalizedStringKey {
        switch self {
        case .bluetooth, .location: "Continue"
        case .bluetoothOff: "Turn on Bluetooth"
        case .bluetoothDenied, .locationDenied, .cameraDenied, .microphoneDenied: "Open Settings"
        case .locationServicesOff: "Turn on Location Services"
        }
    }
    var hasSecondary: Bool { true }
}

struct PermissionSheet: View {
    let ask: PermissionAsk
    /// Off at the end of onboarding: "Not now" would leave the person stuck on the last page.
    var allowsLater = true
    var onPrimary: () -> Void = {}
    /// Called when the sheet closes without the main button (Not now, or swiped away).
    var onLater: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var acted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: ask.symbol)
                    .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(LinearGradient(colors: [Color(hex: 0x3F8CFF), Theme.actionBlue], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Image(systemName: "hand.raised.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2))
                    .offset(x: 10, y: 8)
            }
            .padding(.top, 8).accessibilityHidden(true)
            Text(ask.title).font(.title2.weight(.bold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(ask.message).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            illustration.frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Label { Text(ask.chip) } icon: { Image(systemName: ask.isBluetooth ? "wifi.slash" : "hand.tap.fill") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionBlue)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(.white, in: Capsule()).padding(10)
                }
                .accessibilityHidden(true)
                .padding(.bottom, 6)
            VStack(spacing: 10) {
                Button { acted = true; dismiss(); onPrimary() } label: {
                    Text(ask.primary).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                }
                if ask.hasSecondary && allowsLater {
                    Button { dismiss() } label: {
                        Text("Not now").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.ink).background(Theme.ink.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(ask.hasSecondary && allowsLater ? 680 : 620), .large])
        .presentationCornerRadius(36)
        .onDisappear { if !acted { onLater() } }
    }

    @ViewBuilder private var illustration: some View {
        if ask.isBluetooth { RadarPicture() }
        else if ask.isLocation { MapPicture() }
        else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xE8F1FF), Color(hex: 0xD3E4FF)], startPoint: .top, endPoint: .bottom)
                Image(systemName: ask.symbol).font(.system(size: 64, weight: .regular)).foregroundStyle(Theme.actionBlue.opacity(0.75))
            }
        }
    }
}

/// You in the middle, friends around you on rings: what Bluetooth is for.
private struct RadarPicture: View {
    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2 + 10)
            ZStack {
                LinearGradient(colors: [Color(hex: 0xE8F1FF), Color(hex: 0xD3E4FF)], startPoint: .top, endPoint: .bottom)
                ForEach(1...3, id: \.self) { i in
                    Circle().stroke(Theme.actionBlue.opacity(0.18), lineWidth: 1.5)
                        .frame(width: CGFloat(i) * 70, height: CGFloat(i) * 70).position(c)
                }
                ForEach(Array([("🦊", -0.9, 0.5), ("🌻", 0.35, 0.75), ("⚽️", 2.4, 1.0)].enumerated()), id: \.offset) { _, f in
                    Text(f.0).font(.system(size: 22)).frame(width: 38, height: 38).background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .position(x: c.x + cos(f.1) * 105 * f.2 * 0.66, y: c.y + sin(f.1) * 105 * f.2 * 0.5)
                }
                Circle().fill(Theme.actionBlue).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: Theme.actionBlue.opacity(0.5), radius: 8).position(c)
            }
        }
    }
}

/// A small drawn map with your position: what location is for. Drawn, not loaded, so it works with no internet.
private struct MapPicture: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF3EEE2)))
            ctx.fill(Path(ellipseIn: CGRect(x: -40, y: size.height * 0.45, width: size.width * 0.55, height: size.height * 0.9)),
                     with: .color(Color(hex: 0xC9E6B4)))
            ctx.fill(Path(roundedRect: CGRect(x: size.width * 0.62, y: 18, width: size.width * 0.3, height: 52), cornerRadius: 10),
                     with: .color(Color(hex: 0xC9E6B4)))
            var roads = Path()
            roads.move(to: CGPoint(x: 0, y: size.height * 0.3)); roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.62))
            roads.move(to: CGPoint(x: size.width * 0.38, y: 0)); roads.addLine(to: CGPoint(x: size.width * 0.58, y: size.height))
            roads.move(to: CGPoint(x: size.width * 0.75, y: 0)); roads.addLine(to: CGPoint(x: size.width * 0.9, y: size.height))
            ctx.stroke(roads, with: .color(.white), lineWidth: 9)
            var highway = Path()
            highway.move(to: CGPoint(x: size.width * 0.15, y: size.height)); highway.addLine(to: CGPoint(x: size.width, y: size.height * 0.78))
            ctx.stroke(highway, with: .color(Color(hex: 0xB9B9C3)), lineWidth: 12)
        }
        .overlay {
            Circle().fill(Theme.actionBlue).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 4)
                .background(Circle().fill(Theme.actionBlue.opacity(0.15)).frame(width: 70, height: 70))
                .offset(x: 10, y: 6)
        }
    }
}

/// The camera for photos and QR scanning: go ahead when allowed, ask iOS the first time, or report that it was refused.
enum CameraAccess {
    static func check(ok: @escaping () -> Void, denied: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: ok()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async { granted ? ok() : denied() } }
        default: denied()
        }
    }
}
