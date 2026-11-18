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

    private var isPublic: Bool { conversationID == publicChannelID }
    private var messages: [Message] { store.conversations.first { $0.id == conversationID }?.messages ?? [] }
    private var members: [Member]? { store.conversations.first { $0.id == conversationID }?.members }
    private var livePeer: Peer { store.peers.first { $0.id == conversationID } ?? peer }
    private var online: Bool { isPublic || store.peers.contains { $0.id == conversationID } }
    private var encrypted: Bool { store.simulated || !livePeer.fingerprint.isEmpty }

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            SkyPill {
                                Label(isPublic ? "Public · anyone in range can read this"
                                      : members != nil ? "Encrypted separately for each member"
                                      : (encrypted ? "End-to-end encrypted" : "Waiting for encryption keys"),
                                      systemImage: isPublic ? "megaphone.fill" : "lock.fill").font(.caption)
                            }.scaleEffect(0.92).padding(.vertical, 10)
                            ForEach(messages) { m in
                                Bubble(message: m, showSender: isPublic || members != nil, progress: store.photoProgress[m.id],
                                       loadPhoto: { store.loadPhoto($0) }, onOpenPhoto: { bigPhoto = $0 },
                                       onRetry: { store.retry(m.id, in: conversationID) },
                                       onBlock: (!m.mine && m.senderID != nil && (isPublic || members != nil)) ? { blockTarget = m.senderID } : nil,
                                       onReport: m.mine ? nil : {
                                           let direct = !isPublic && members == nil   // 1:1 chat: the sender is the other person
                                           report = Support.reportURL(name: m.sender ?? livePeer.name, id: m.senderID ?? (direct ? livePeer.id : nil),
                                                                      text: m.photo != nil ? "[photo]" : m.text, date: m.date)
                                       }).id(m.id)
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
        .onAppear { store.activeConversation = conversationID; store.markRead(conversationID) }
        .onDisappear { if store.activeConversation == conversationID { store.activeConversation = nil } }
        .onChange(of: messages.count) { _, _ in store.markRead(conversationID) }
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
            } else { PeerInfoSheet(peer: livePeer).environmentObject(store) }
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
                store.send(t, in: conversationID); draft = ""
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: Theme.rButton, style: .continuous))
            }
            .accessibilityLabel("Send")
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .readableWidth()
        .background(.ultraThinMaterial)
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
                    Text(verbatim: message.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(message.mine ? Color.white : Theme.ink)
                        .modifier(BubbleBackground(mine: message.mine))
                }
                HStack(spacing: 4) {
                    Text(message.date, style: .time)
                    if !message.mine && message.hops > 1 { Text("· \(message.hops) hops") }
                    if message.mine { Image(systemName: icon).accessibilityLabel(LocalizedStringKey(stateName)) }
                    if message.state == .failed { Text("Tap to retry") }
                }.font(.caption2).foregroundStyle(.white.opacity(0.85)).shadow(color: .black.opacity(0.25), radius: 2)
            }
            if !message.mine { Spacer(minLength: 60) }
        }
        .onTapGesture { if message.state == .failed { onRetry() } }
        .contextMenu {
            if let onReport { Button { onReport() } label: { Label("Report", systemImage: "flag.fill") } }
            if let onBlock { Button(role: .destructive) { onBlock() } label: { Label("Block", systemImage: "hand.raised.fill") } }
        }
    }
    private var icon: String {
        switch message.state {
        case .sending: "clock"
        case .sent: "checkmark"
        case .relayed: "arrow.triangle.branch"
        case .delivered: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
    private var stateName: String {
        switch message.state {
        case .sending: "Sending"
        case .sent: "Sent"
        case .relayed: "Relayed"
        case .delivered: "Delivered"
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
    @State private var blockTarget: String?
    @State private var report: URL?

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 16) {
                Avatar(name: peer.name, size: 80, avatar: peer.avatar).padding(.top, 24).accessibilityHidden(true)
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
                Button("Close") { dismiss() }.foregroundStyle(.white)
                Spacer()
            }.padding(.horizontal, 20).readableWidth(560)
        }
        .blockConfirmation(for: $blockTarget, store: store)
        .opensMail($report)
        .presentationDetents([.medium, .large])
    }
}
