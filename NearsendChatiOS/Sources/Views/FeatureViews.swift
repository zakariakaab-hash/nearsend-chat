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
        confirmationDialog("Block this person?", isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: target.wrappedValue) { id in
            Button("Block", role: .destructive) { store.toggleBlocked(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Their messages and announcements are hidden and ignored. You can unblock them in their contact info.")
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

/// Switches on the You tab: pass on messages for others, delivery receipts, notification text, auto-delete.
struct PrivacyCard: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Privacy", systemImage: "lock.fill").font(.subheadline.weight(.semibold))
                row("Pass on messages for others", "Helps messages travel further and reach people who are away. Uses some battery.", $store.relayOthers)
                row("Delivery receipts", "Let senders see when their message reached you.", $store.receipts)
                row("Hide text in notifications", "Notifications show who wrote, not what.", $store.hidePreviews)
                row("Announcements", "Show announcements from people nearby and notify me. Off: they are hidden, but your phone still passes them on.", $store.showAnnouncements)
                Text("Delete messages after").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach([0, 1, 7, 30], id: \.self) { d in
                        ChipButton(selected: store.autoDeleteDays == d, action: { store.autoDeleteDays = d }) { dayLabel(d) }
                    }
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: LocalizedStringKey, _ body: LocalizedStringKey, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(body).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }.tint(Theme.actionBlue)
    }

    @ViewBuilder private func dayLabel(_ d: Int) -> some View {
        if d == 0 { Text("Never") } else if d == 1 { Text("1 day") } else { Text("\(d) days") }
    }
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
