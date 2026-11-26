import LocalAuthentication
import PhotosUI
import SwiftUI

struct ThreadView: View {
    @EnvironmentObject var store: ChatStore
    let conversationID: String
    let peer: Peer
    @State private var draft = ""
    @State private var showInfo = UserDefaults.standard.bool(forKey: "showInfo")   // `-showInfo YES` launch argument (screenshots)
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var bigPhoto: String?
    @State private var noPosition = false
    @State private var blockTarget: String?
    @State private var report: URL?
    @State private var replyTo: Message?
    @State private var forwarding: Message?
    @State private var deleting: Message?
    @State private var unlocked = false
    @State private var infoFor: Message?
    @Environment(\.scenePhase) private var scenePhase

    private var conversation: Conversation? { store.conversations.first { $0.id == conversationID } }
    private var pinned: Message? { conversation?.pinnedMessage.flatMap { pid in messages.first { $0.id == pid } } }
    private var isPublic: Bool { conversationID == publicChannelID }
    private var messages: [Message] { store.conversations.first { $0.id == conversationID }?.messages ?? [] }
    private var members: [Member]? { store.conversations.first { $0.id == conversationID }?.members }
    private var livePeer: Peer { store.peers.first { $0.id == conversationID } ?? peer }
    private var online: Bool { isPublic || store.peers.contains { $0.id == conversationID } }
    private var encrypted: Bool { store.simulated || !livePeer.fingerprint.isEmpty }

    var body: some View {
        ZStack {
            SkyBackground()
            if conversation?.isLocked == true && !unlocked {
                lockedView
            } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    if let pinned { pinnedBar(pinned, proxy: proxy) }
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            SkyPill {
                                Label(isPublic ? "Public · anyone in range can read this"
                                      : members != nil ? "Encrypted separately for each member"
                                      : (encrypted ? "End-to-end encrypted" : "Waiting for encryption keys"),
                                      systemImage: isPublic ? "megaphone.fill" : "lock.fill").font(.caption)
                            }.scaleEffect(0.92).padding(.vertical, 10)
                            ForEach(messages) { m in
                                bubble(m).id(m.id)
                            }
                        }.padding(.horizontal, 16).padding(.top, 8).readableWidth()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                composer
            }
            }
        }
        .onAppear { if conversation?.isLocked == true && !unlocked { authenticate() } }
        .onChange(of: unlocked) { _, _ in readIfVisible() }
        .onChange(of: scenePhase) { _, _ in readIfVisible() }
        .onAppear { store.activeConversation = conversationID; readIfVisible() }
        .onDisappear { if store.activeConversation == conversationID { store.activeConversation = nil } }
        .onChange(of: messages.count) { _, _ in readIfVisible() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)   // otherwise the bar is clear until you scroll and Back/info vanish into the blue sky
        .toolbar(.hidden, for: .tabBar)                     // full-height conversation, like Android
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    if isPublic { Text("Nearby channel").font(.headline).foregroundStyle(Theme.ink) }
                    else { Text(verbatim: livePeer.name).font(.headline).foregroundStyle(Theme.ink) }
                    subtitle.font(.caption2).foregroundStyle(online || members != nil ? Theme.secure : Theme.inkSecondary)
                }
            }
            if !isPublic {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text(LocalizedStringKey(members != nil ? "Group info" : "Contact info")))
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { store.sendPhoto(data, in: conversationID) } else { store.photoError = true }
                pickedPhoto = nil
            }
        }
        .blockConfirmation(for: $blockTarget, store: store)
        .confirmationDialog("Delete message?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { m in
            Button("Delete for me", role: .destructive) { store.deleteMessage(m.id, in: conversationID) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("Only on this phone. The other person keeps their copy.") }
        .sheet(item: $infoFor) { m in MessageInfoSheet(message: m, chatName: members != nil ? livePeer.name : nil) }
        .sheet(item: $forwarding) { m in
            ForwardSheet(text: Reply.split(m.text)?.body ?? m.text, from: conversationID).environmentObject(store)
        }
        .opensMail($report)
        .alert("Couldn't use this picture", isPresented: $store.photoError) { Button("Close", role: .cancel) {} }
        .alert("No position yet. Try again outdoors.", isPresented: $noPosition) { Button("Close", role: .cancel) {} }
        .fullScreenCover(isPresented: Binding(get: { bigPhoto != nil }, set: { if !$0 { bigPhoto = nil } })) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let id = bigPhoto, let img = store.loadPhoto(id) { Image(uiImage: img).resizable().scaledToFit() }
            }.onTapGesture { bigPhoto = nil }
        }
        .sheet(isPresented: $showInfo) {
            if let members {
                GroupInfoSheet(name: livePeer.name, members: members) {
                    showInfo = false; store.leaveGroup(conversationID); dismiss()
                }.environmentObject(store)
            } else {
                PeerInfoSheet(peer: livePeer) { showInfo = false; store.deleteConversation(conversationID); dismiss() }.environmentObject(store)
            }
        }
    }

    @ViewBuilder private var subtitle: some View {
        if isPublic { Text("Public channel") }
        else if let members { Text("\(members.count) members") }
        else if !online && store.canCarryTo(conversationID) { Text("Away · phones nearby carry your messages to them (up to 24 h)") }
        else if !online { Text("Out of range · will send when nearby") }
        else if livePeer.hops == 1 { Text("Direct link") }
        else { Text("\(livePeer.hops) hops") }
    }

    private var composer: some View {
        VStack(spacing: 6) {
        if let r = replyTo {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.actionBlue).frame(width: 3).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: replyName(r)).font(.caption.weight(.semibold)).foregroundStyle(Theme.actionBlue)
                    Text(verbatim: r.photo != nil ? "\u{1F4F7} " + localized("Photo") : (Reply.split(r.text)?.body ?? r.text))
                        .font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                Button { replyTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary) }
                    .accessibilityLabel("Cancel reply")
            }
            .padding(.horizontal, 14).padding(.vertical, 8).glass(radius: Theme.rField)
            .padding(.horizontal, 12).padding(.top, 8)
        }
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5).focused($focused).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glass(radius: Theme.rField)
            if !isPublic {
                Menu {
                    if members == nil { Button { showPhotoPicker = true } label: { Label("Photo", systemImage: "photo") } }
                    Button { store.sendLocation(in: conversationID) { ok in if !ok { noPosition = true } } } label: { Label("Location", systemImage: "mappin.circle") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.link)
                        .frame(width: 46, height: 46).glass(radius: 23)
                }.accessibilityLabel("Attach")
            }
            Button {
                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let out = replyTo.map { Reply.compose(quoting: $0, from: replyName($0), text: t) } ?? t
                store.send(out, in: conversationID); draft = ""; replyTo = nil
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: Theme.rButton, style: .continuous))
            }
            .accessibilityLabel("Send")
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .readableWidth()
        .background(.ultraThinMaterial)
    }

    private func bubble(_ m: Message) -> Bubble {
        let group = isPublic || members != nil
        let blockAction: (() -> Void)? = (!m.mine && m.senderID != nil && group) ? { blockTarget = m.senderID } : nil
        let reportAction: (() -> Void)? = m.mine ? nil : { reportMessage(m) }
        let forwardAction: (() -> Void)? = m.photo == nil ? { forwarding = m } : nil
        let isPinnedNow = conversation?.pinnedMessage == m.id
        return Bubble(message: m, showSender: group, progress: store.photoProgress[m.id],
                      loadPhoto: { store.loadPhoto($0) }, onOpenPhoto: { bigPhoto = $0 },
                      onRetry: { store.retry(m.id, in: conversationID) },
                      onBlock: blockAction, onReport: reportAction,
                      onReply: { replyTo = m; focused = true }, onForward: forwardAction,
                      onPin: { store.pinMessage(isPinnedNow ? nil : m.id, in: conversationID) }, isPinned: isPinnedNow,
                      onDelete: { deleting = m }, onInfo: m.mine ? { infoFor = m } : nil)
    }

    private func reportMessage(_ m: Message) {
        let direct = !isPublic && members == nil   // 1:1 chat: the sender is the other person
        report = Support.reportURL(name: m.sender ?? livePeer.name, id: m.senderID ?? (direct ? livePeer.id : nil),
                                   text: m.photo != nil ? "[photo]" : m.text, date: m.date)
    }

    /// Only an open, unlocked chat on screen counts as read (not a locked chat, not the phone in a pocket).
    private func readIfVisible() {
        guard scenePhase == .active, conversation?.isLocked != true || unlocked else { return }
        store.markRead(conversationID)
    }

    private func replyName(_ m: Message) -> String { m.mine ? store.nickname : (m.sender ?? livePeer.name) }

    private func pinnedBar(_ m: Message, proxy: ScrollViewProxy) -> some View {
        Button { withAnimation { proxy.scrollTo(m.id, anchor: .center) } } label: {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill").foregroundStyle(Theme.actionBlue)
                Text(verbatim: m.photo != nil ? "\u{1F4F7} " + localized("Photo") : (Reply.split(m.text)?.body ?? m.text))
                    .font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Button { store.pinMessage(nil, in: conversationID) } label: { Image(systemName: "xmark").foregroundStyle(Theme.inkSecondary) }
                    .accessibilityLabel("Unpin")
            }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity).background(.ultraThinMaterial)
        }.buttonStyle(.plain).accessibilityLabel("Pinned message")
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.white)
            Text("Locked chat").font(Theme.display(28)).foregroundStyle(.white).textCase(.uppercase)
            PrimaryButton(title: "Unlock") { authenticate() }.frame(maxWidth: 260)
        }
    }

    /// Face ID, Touch ID or the phone's passcode. Without any of these set up the chat simply opens.
    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked = true; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localized("Unlock this chat")) { ok, _ in
            Task { @MainActor in if ok { unlocked = true } }
        }
    }
}

/// Pick a chat to forward a message to. The text is sent as a new message from you.
struct ForwardSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let text: String
    let from: String
    var body: some View {
        NavigationStack {
            List(store.conversations.filter { $0.id != from }) { c in
                Button {
                    store.send(text, in: c.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: c.id == publicChannelID ? "#" : c.peer.name, size: 36, avatar: c.peer.shownAvatar).accessibilityHidden(true)
                        if c.id == publicChannelID { Text("Nearby channel") } else { Text(verbatim: c.peer.name) }
                    }
                }.foregroundStyle(Theme.ink)
            }
            .navigationTitle("Forward to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct Bubble: View {
    let message: Message
    var showSender = false
    var progress: Double? = nil
    var loadPhoto: (String) -> UIImage? = { _ in nil }
    var onOpenPhoto: (String) -> Void = { _ in }
    var onRetry: () -> Void = {}
    var onBlock: (() -> Void)? = nil       // set for other people's public-channel and group messages: long-press to block the sender
    var onReport: (() -> Void)? = nil      // set for every message from someone else: long-press to report it by email
    var onReply: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var isPinned = false
    var onDelete: (() -> Void)? = nil
    var onInfo: (() -> Void)? = nil        // our own messages: delivery details

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 60) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if showSender, !message.mine, let s = message.sender {
                    Text(verbatim: s).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).padding(.leading, 6)
                }
                if let pid = message.photo {
                    PhotoBubble(image: loadPhoto(pid), progress: progress).onTapGesture { onOpenPhoto(pid) }
                } else {
                    textContent
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(message.mine ? Color.white : Theme.ink)
                        .modifier(BubbleBackground(mine: message.mine))
                }
                HStack(spacing: 4) {
                    Text(message.date, style: .time)
                    if !message.mine && message.hops > 1 { Text("· \(message.hops) hops") }
                    if message.mine { ticks.accessibilityElement().accessibilityLabel(LocalizedStringKey(stateName)) }
                    if message.state == .failed { Text("Tap to retry") }
                }.font(.caption2).foregroundStyle(.white.opacity(0.85)).shadow(color: .black.opacity(0.25), radius: 2)
            }
            if !message.mine { Spacer(minLength: 60) }
        }
        .onTapGesture { if message.state == .failed { onRetry() } }
        .contextMenu {
            if let onReply { Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") } }
            if let onForward { Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") } }
            if message.photo == nil {
                Button { UIPasteboard.general.string = Reply.split(message.text)?.body ?? message.text } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
            if let onPin { Button { onPin() } label: { Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") } }
            if message.mine, let onInfo { Button { onInfo() } label: { Label("Info", systemImage: "info.circle") } }
            if let onDelete { Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") } }
            if !message.mine, let onReport { Button { onReport() } label: { Label("Report", systemImage: "flag.fill") } }
            if !message.mine, let onBlock { Button(role: .destructive) { onBlock() } label: { Label("Block", systemImage: "hand.raised.fill") } }
        }
    }
    /// Plain text, or a quoted line above the reply when the text starts with "↪ name: …".
    @ViewBuilder private var textContent: some View {
        if let r = Reply.split(message.text) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Rectangle().fill(message.mine ? Color.white.opacity(0.8) : Theme.actionBlue).frame(width: 3)
                    Text(verbatim: r.quote).font(.caption).lineLimit(2).opacity(0.85)
                }
                .padding(6).background((message.mine ? Color.white : Theme.actionBlue).opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(verbatim: r.body)
            }
        } else {
            Text(verbatim: message.text)
        }
    }

    private var icon: String {
        switch message.state {
        case .sending: "clock"
        case .sent: "checkmark"
        case .relayed: "arrow.triangle.branch"
        case .delivered, .read: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
    /// WhatsApp-style: one tick sent, two ticks delivered, two coloured ticks read.
    @ViewBuilder private var ticks: some View {
        if message.state == .delivered || message.state == .read {
            HStack(spacing: -5) { Image(systemName: "checkmark"); Image(systemName: "checkmark") }
                .fontWeight(.bold)
                .foregroundStyle(message.state == .read ? Color(hex: 0x7CF5C4) : .white.opacity(0.85))
        } else {
            Image(systemName: icon)
        }
    }
    private var stateName: String {
        switch message.state {
        case .sending: "Sending"
        case .sent: "Sent"
        case .relayed: "Relayed"
        case .delivered: "Delivered"
        case .read: "Read"
        case .failed: "Failed"
        }
    }
}

private struct BubbleBackground: ViewModifier {
    let mine: Bool
    func body(content: Content) -> some View {
        if mine {
            content.background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            content.glass(radius: 20)
        }
    }
}

/// Fingerprint comparison: two people read their digits to each other in person to rule out an impostor.
struct PeerInfoSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let peer: Peer
    var onDelete: (() -> Void)? = nil
    @State private var blockTarget: String?
    @State private var report: URL?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
            VStack(spacing: 16) {
                Avatar(name: peer.name, size: 80, avatar: peer.shownAvatar).padding(.top, 24).accessibilityHidden(true)
                Text(verbatim: peer.name).font(.title2.weight(.semibold)).foregroundStyle(.white)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Their fingerprint", systemImage: "key.fill").font(.subheadline.weight(.semibold))
                        Text(verbatim: peer.fingerprint.isEmpty ? "—" : peer.fingerprint)
                            .font(.system(.title3, design: .monospaced)).foregroundStyle(Theme.link)
                        Text("Ask them to read the digits on their You tab. If they match, nobody is impersonating them.")
                            .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(title: peer.verified ? "Remove verification" : "Mark as verified") {
                    store.toggleVerified(peer); dismiss()
                }
                let isBlocked = store.blocked.contains(peer.id)
                if isBlocked { StatusPill(text: "Blocked · their messages are ignored", color: .red) }
                Button { if isBlocked { store.toggleBlocked(peer.id) } else { blockTarget = peer.id } } label: {
                    Text(LocalizedStringKey(isBlocked ? "Unblock" : "Block")).font(.subheadline.weight(.semibold))
                        .foregroundStyle(isBlocked ? Theme.link : .red).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                }
                Button { report = Support.reportURL(name: peer.name, id: peer.id, text: nil) } label: {
                    Label("Report", systemImage: "flag.fill").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                }
                if onDelete != nil {
                    Button { confirmDelete = true } label: {
                        Label("Delete chat", systemImage: "trash").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                    }
                }
                Button("Close") { dismiss() }.foregroundStyle(.white).padding(.bottom, 16)
            }.padding(.horizontal, 20).readableWidth(560)
            }
        }
        .confirmationDialog("Delete chat", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete chat", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only on this phone. The other person keeps their copy.") }
        .blockConfirmation(for: $blockTarget, store: store)
        .opensMail($report)
        .presentationDetents([.medium, .large])
    }
}

/// "Info" on one of our messages, like WhatsApp's: when it was sent and whether and when it was delivered.
/// There are no read receipts yet: the mesh protocol only confirms delivery to the other phone.
struct MessageInfoSheet: View {
    let message: Message
    var chatName: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: message.photo != nil ? "\u{1F4F7} " + localized("Photo") : (Reply.split(message.text)?.body ?? message.text))
                        .lineLimit(6)
                }
                Section {
                    row("Sent", "checkmark", message.state == .sending ? nil : message.date, done: message.state != .sending && message.state != .failed)
                    if message.state == .relayed {
                        Label("Carried by a phone nearby", systemImage: "arrow.triangle.branch").foregroundStyle(Theme.ink)
                    }
                    row("Delivered", "checkmark.circle.fill", message.deliveredAt, done: message.state == .delivered || message.state == .read)
                    if chatName == nil { row("Read", "eye.fill", message.readAt, done: message.state == .read) }
                    if message.state == .failed {
                        Label("Not sent. Tap the message to try again.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                } footer: {
                    Text(chatName != nil ? "Delivered means every member's phone received it." : "Read appears when they open the chat, if both of you have Delivery receipts on.")
                }
            }
            .navigationTitle("Message info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ date: Date?, done: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(done ? Theme.secure : Theme.inkSecondary)
            Spacer()
            if let date, done { Text(date, format: .dateTime.day().month().hour().minute()).foregroundStyle(Theme.inkSecondary) }
            else { Text("Waiting").foregroundStyle(Theme.inkSecondary) }
        }
    }
}
