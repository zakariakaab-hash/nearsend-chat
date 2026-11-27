import AVFoundation
import LocalAuthentication
import MapKit
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
    @StateObject private var recorder = VoiceRecorder()
    /// Voice notes go to one contact, like photos (not to groups or the Nearby channel).
    private var canRecord: Bool { !isPublic && members == nil }
    @State private var showAttach = false
    @State private var afterAttach: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var bigPhoto: String?
    @State private var noPosition = false
    @State private var locationAsk: PermissionAsk?
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
                            if showVerifyBanner { verifyBanner }
                            ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in row(i, m) }
                        }.padding(.horizontal, 16).padding(.top, 8).readableWidth()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if conversation?.isRequest == true { requestBar } else { composer }
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
            // WhatsApp-style header: picture, then name and status; tapping it opens contact or group info.
            ToolbarItem(placement: .principal) {
                Button { if !isPublic { showInfo = true } } label: {
                    HStack(spacing: 10) {
                        Avatar(name: isPublic ? "#" : livePeer.name, size: 36, avatar: livePeer.shownAvatar)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            if isPublic { Text("Nearby channel").font(.headline).foregroundStyle(Theme.ink) }
                            else { Text(verbatim: livePeer.name).font(.headline).foregroundStyle(Theme.ink) }
                            subtitle.font(.caption2).foregroundStyle(online || members != nil ? Theme.secure : Theme.inkSecondary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPublic)
            }
            if !isPublic {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text(LocalizedStringKey(members != nil ? "Group info" : "Contact info")))
                }
            }
        }
        // Attach: a bottom sheet with what can go over Bluetooth, each with a line on how it travels.
        .sheet(isPresented: $showAttach, onDismiss: { afterAttach?(); afterAttach = nil }) {
            AttachSheet(name: isPublic ? localized("Nearby channel") : livePeer.name, oneToOne: members == nil,
                        hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera)) { choice in
                switch choice {
                case .photo: afterAttach = { showPhotoPicker = true }
                case .camera: afterAttach = { CameraAccess.check(ok: { showCamera = true }, denied: { locationAsk = .cameraDenied }) }
                case .location:
                    if store.hasLocationPermission { store.sendLocation(in: conversationID) { ok in if !ok { noPosition = true } } }
                    else { let a: PermissionAsk = store.locationStatus == .notDetermined ? .location : .locationDenied; afterAttach = { locationAsk = a } }
                }
                showAttach = false
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img, let data = img.jpegData(compressionQuality: 0.9) { store.sendPhoto(data, in: conversationID) }
            }.ignoresSafeArea()
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { store.sendPhoto(data, in: conversationID) } else { store.photoError = true }
                pickedPhoto = nil
            }
        }
        .blockConfirmation(for: $blockTarget, store: store)
        .bottomConfirm(isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                       title: "Delete message?", message: "Only on this phone. The other person keeps their copy.",
                       action: "Delete for me") { if let m = deleting { store.deleteMessage(m.id, in: conversationID) } }
        .sheet(item: $infoFor) { m in MessageInfoSheet(message: m, chatName: members != nil ? livePeer.name : nil) }
        .sheet(item: $forwarding) { m in
            ForwardSheet(text: Reply.split(m.text)?.body ?? m.text, from: conversationID).environmentObject(store)
        }
        .opensMail($report)
        .alert("Couldn't use this picture", isPresented: $store.photoError) { Button("Close", role: .cancel) {} }
        .alert("No position yet. Try again outdoors.", isPresented: $noPosition) { Button("Close", role: .cancel) {} }
        .sheet(item: $locationAsk) { a in
            PermissionSheet(ask: a) { if a == .location { store.requestLocation() } else { SystemSettings.open() } }
        }
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
                    Text(verbatim: r.mediaLabel ?? (Reply.split(r.text)?.body ?? r.text))
                        .font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                Button { replyTo = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("Cancel reply")
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
                Button { showAttach = true } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.link)
                        .frame(width: 46, height: 46).glass(radius: 23)
                }.accessibilityLabel("Attach")
            }
            if canRecord && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VoiceRecordButton(recorder: recorder) { data in store.sendVoice(data, in: conversationID) }
            } else {
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
        }
        .overlay { if recorder.isRecording { RecordingBar(recorder: recorder).padding(.trailing, 64) } }
        .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .readableWidth()
        .background(.ultraThinMaterial)
    }

    /// One message, with a day separator above it when it starts a new day.
    @ViewBuilder private func row(_ i: Int, _ m: Message) -> some View {
        if i == 0 || !Calendar.current.isDate(messages[i - 1].date, inSameDayAs: m.date) { DaySeparator(date: m.date) }
        bubble(m, isLastMine: m.mine && m.id == lastMineID).id(m.id)
    }

    private var lastMineID: String? { messages.last(where: { $0.mine })?.id }

    /// A stranger wrote first ("Messages from strangers: Ask me"): accept to reply, or block. No read receipt until accepted.
    private var requestBar: some View {
        VStack(spacing: 10) {
            Text("Message request").font(.headline).foregroundStyle(Theme.ink)
            Text("\(livePeer.name) isn't in your chats yet. They don't know you've seen this.")
                .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    // A group from a stranger is left (its messages are ignored); a person is blocked.
                    if !conversationID.hasPrefix("g:") { store.toggleBlocked(conversationID) }
                    store.deleteConversation(conversationID)
                    dismiss()
                } label: {
                    Text(conversationID.hasPrefix("g:") ? "Leave" : "Block").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(.red).background(Color.red.opacity(0.12), in: Capsule())
                }
                Button { store.acceptRequest(conversationID) } label: {
                    Text("Accept").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity).glass(radius: 24).padding(.horizontal, 12).padding(.bottom, 8)
    }

    /// Private chats with someone not yet verified: a gentle nudge to compare fingerprints, hidden once they are verified.
    @State private var verifyDismissed = false
    private var showVerifyBanner: Bool {
        !isPublic && members == nil && encrypted && !livePeer.verified && !verifyDismissed && !(conversation?.isLocked == true && !unlocked)
    }
    private var verifyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield").font(.title3).foregroundStyle(Theme.link).accessibilityHidden(true)
            Text("Not verified. Compare fingerprints in person to be sure this is really them.")
                .font(.footnote).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            Button("Verify") { showInfo = true }.font(.footnote.weight(.semibold)).foregroundStyle(Theme.link)
            Button { verifyDismissed = true } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
                .foregroundStyle(Theme.inkSecondary).accessibilityLabel(Text("Close"))
        }
        .padding(12).glass(radius: 16).padding(.bottom, 6)
    }

    private func bubble(_ m: Message, isLastMine: Bool = false) -> Bubble {
        let group = isPublic || members != nil
        let blockAction: (() -> Void)? = (!m.mine && m.senderID != nil && group) ? { blockTarget = m.senderID } : nil
        // Private chats report from contact info (i); the long-press Report stays where senders may be strangers.
        let reportAction: (() -> Void)? = (m.mine || !group) ? nil : { reportMessage(m) }
        let forwardAction: (() -> Void)? = m.photo == nil ? { forwarding = m } : nil
        let isPinnedNow = conversation?.pinnedMessage == m.id
        // Group chats read like Messages: the name on the first bubble of a run from one person, their picture beside the last.
        var first = true, last = true
        if group, !m.mine, let i = messages.firstIndex(where: { $0.id == m.id }) {
            first = i == 0 || messages[i - 1].mine || messages[i - 1].senderID != m.senderID
            last = i == messages.count - 1 || messages[i + 1].mine || messages[i + 1].senderID != m.senderID
        }
        let sid = m.senderID ?? m.sender ?? ""
        let pic = store.peers.first { $0.id == sid }?.shownAvatar ?? Avatars.fallback(for: sid)
        return Bubble(message: m, showSender: group && first, avatarColumn: group, showAvatar: last, senderAvatar: pic,
                      showStatusText: isLastMine, photoBytes: m.mine ? m.photo.flatMap { store.photoSize($0) } : nil,
                      progress: store.photoProgress[m.id],
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
                                   text: m.photo != nil ? (m.isVoice ? "[voice message]" : "[photo]") : m.text, date: m.date)
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
                Text(verbatim: m.mediaLabel ?? (Reply.split(m.text)?.body ?? m.text))
                    .font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Button { store.pinMessage(nil, in: conversationID) } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.inkSecondary).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
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
    var avatarColumn = false               // groups and the Nearby channel: a column for the sender's picture
    var showAvatar = false                 // the picture itself, on the last bubble of a run
    var senderAvatar: String? = nil
    var showStatusText = false             // our latest message: say in words where it is, not only ticks
    var photoBytes: Int? = nil             // our photos: how small it was made for Bluetooth
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
        HStack(alignment: .bottom, spacing: 8) {
            if message.mine { Spacer(minLength: 60) }
            if avatarColumn && !message.mine {
                Group {
                    if showAvatar { Avatar(name: message.sender ?? "?", size: 28, avatar: senderAvatar) }
                    else { Color.clear }
                }
                .frame(width: 28, height: 28).padding(.bottom, 18).accessibilityHidden(true)
            }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if showSender, !message.mine, let s = message.sender {
                    Text(verbatim: s).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).padding(.leading, 6)
                }
                if let pid = message.photo, message.isVoice {
                    VoiceBubble(id: pid, mine: message.mine, progress: progress)
                } else if let pid = message.photo {
                    PhotoBubble(image: loadPhoto(pid), progress: progress).onTapGesture { onOpenPhoto(pid) }
                } else if let loc = SharedLocation.parse(message.text) {
                    LocationBubble(lat: loc.lat, lon: loc.lon, mine: message.mine)
                } else {
                    textContent
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(message.mine ? Color.white : Theme.ink)
                        .modifier(BubbleBackground(mine: message.mine))
                }
                HStack(spacing: 4) {
                    if let photoBytes { Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(photoBytes), countStyle: .file) + " ·") }
                    Text(message.date, style: .time)
                    if !message.mine && message.hops > 1 { Text("· \(message.hops) hops") }
                    if message.mine { ticks.accessibilityElement().accessibilityLabel(LocalizedStringKey(stateName)) }
                    if message.state == .failed { Text("Tap to retry") }
                    else if showStatusText { Text(LocalizedStringKey(statusText)) }
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
    /// Nearsend's own status mark: a ring that closes as the message gets closer (sent, carried, delivered, read).
    @ViewBuilder private var ticks: some View {
        if message.state == .failed { Image(systemName: icon) }
        else { StatusRing(state: message.state) }
    }
    private var statusText: String {
        switch message.state {
        case .sending: "Waiting for a phone nearby"
        case .sent: "Sent"
        case .relayed: "Carried by a phone nearby"
        case .delivered: "Delivered"
        case .read: "Read"
        case .failed: ""
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
        .bottomConfirm(isPresented: $confirmDelete, title: "Delete chat",
                       message: "Only on this phone. The other person keeps their copy.", action: "Delete chat") { onDelete?() }
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
                    Text(verbatim: message.mediaLabel ?? (Reply.split(message.text)?.body ?? message.text))
                        .lineLimit(6)
                }
                Section {
                    row("Sent", .sent, message.state == .sending ? nil : message.date, done: message.state != .sending && message.state != .failed)
                    if message.state == .relayed {
                        Label { Text("Carried by a phone nearby") } icon: { StatusRing(state: .relayed, tint: Theme.ink, size: 17) }
                            .foregroundStyle(Theme.ink)
                    }
                    row("Delivered", .delivered, message.deliveredAt, done: message.state == .delivered || message.state == .read)
                    if chatName == nil { row("Read", .read, message.readAt, done: message.state == .read) }
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

    private func row(_ title: LocalizedStringKey, _ state: DeliveryState, _ date: Date?, done: Bool) -> some View {
        HStack {
            Label { Text(title) } icon: {
                StatusRing(state: state, tint: done ? Theme.secure : Theme.inkSecondary,
                           readFill: done ? Theme.secure : Theme.inkSecondary.opacity(0.5), readDot: .white, size: 17)
            }.foregroundStyle(done ? Theme.secure : Theme.inkSecondary)
            Spacer()
            if let date, done { Text(date, format: .dateTime.day().month().hour().minute()).foregroundStyle(Theme.inkSecondary) }
            else if !done { Text("Waiting").foregroundStyle(Theme.inkSecondary) }
        }
    }
}

/// A shared position: a small map (skipped in Battery saver) and a button that opens Apple Maps at that spot.
private struct LocationBubble: View {
    let lat: Double, lon: Double, mine: Bool
    @ObservedObject private var power = PowerMode.shared
    @Environment(\.openURL) private var openURL
    private var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var body: some View {
        Button { open() } label: {
            VStack(alignment: .leading, spacing: 0) {
                if !power.saver {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
                        interactionModes: []) {
                        Marker("", coordinate: coordinate).tint(Theme.actionBlue)
                    }
                    .frame(width: 240, height: 130)
                    .allowsHitTesting(false)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Location").font(.subheadline.weight(.semibold))
                        Text("Open in Maps").font(.caption).opacity(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.6)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(width: 240, alignment: .leading)
            }
            .foregroundStyle(mine ? Color.white : Theme.ink)
            .modifier(BubbleBackground(mine: mine))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Location"))
        .accessibilityHint(Text("Open in Maps"))
    }
    private func open() {
        let s = String(format: "https://maps.apple.com/?ll=%.5f,%.5f&q=%.5f,%.5f", locale: Locale(identifier: "en_US_POSIX"), lat, lon, lat, lon)
        if let url = URL(string: s) { openURL(url) }
    }
}

/// "Today", "Yesterday" or the date, between messages from different days.
private struct DaySeparator: View {
    let date: Date
    var body: some View {
        Group {
            if Calendar.current.isDateInToday(date) { Text("Today") }
            else if Calendar.current.isDateInYesterday(date) { Text("Yesterday") }
            else { Text(date, format: .dateTime.weekday(.wide).day().month(.wide)) }
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.skyPill, in: Capsule())
        .padding(.vertical, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The system camera, for "Camera" in the + menu. Calls back with the photo, or nil when cancelled.
private struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

extension Message {
    /// What lists, replies and notifications show for a photo or voice note.
    var mediaLabel: String? {
        guard photo != nil else { return nil }
        return isVoice ? "\u{1F3A4} " + localized("Voice message") : "\u{1F4F7} " + localized("Photo")
    }
}

// MARK: voice notes

/// Records a short voice note as small AAC (mono, 16 kHz, 12 kbit/s): about 1.5 KB a second, so 12 seconds fit Bluetooth like a photo.
@MainActor final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var denied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var onFinish: ((Data) -> Void)?
    private var held = false          // the finger is still on the button (permission can arrive after it let go)
    private var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("voice-note.m4a") }

    func start(onFinish: @escaping (Data) -> Void) {
        guard !isRecording, !held else { return }
        held = true
        AVAudioApplication.requestRecordPermission { ok in
            Task { @MainActor in
                guard ok else { self.held = false; self.denied = true; return }
                guard self.held else { return }          // a quick tap: let go before recording could start
                self.begin(onFinish)
            }
        }
    }
    private func begin(_ onFinish: @escaping (Data) -> Void) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 12_000]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { NLog.i("voice", "recorder could not be created"); return }
        r.delegate = self
        guard r.record(forDuration: VoiceNote.maxSeconds) else { NLog.i("voice", "recording did not start"); return }
        NLog.i("voice", "recording")
        recorder = r; self.onFinish = onFinish; elapsed = 0; isRecording = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
    }
    /// Stops; sends unless `cancel` or shorter than a second.
    func stop(cancel: Bool = false) {
        held = false
        guard let r = recorder else { return }
        let long = r.currentTime >= 1
        if cancel || !long { onFinish = nil }
        r.stop()          // the delegate hands over the file
    }
    nonisolated func audioRecorderDidFinishRecording(_ r: AVAudioRecorder, successfully ok: Bool) {
        Task { @MainActor in
            self.timer?.invalidate(); self.timer = nil; self.isRecording = false; self.recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            let data = ok ? VoiceRecorder.shrink(self.url) : nil
            NLog.i("voice", "finished ok=\(ok) bytes=\(data?.count ?? -1) send=\(self.onFinish != nil)")
            if let done = self.onFinish, let data { done(data) }
            self.onFinish = nil
            try? FileManager.default.removeItem(at: self.url)
        }
    }
}

extension VoiceRecorder {
    /// Re-encodes a recording as AAC, mono, 16 kHz, 12 kbit/s (about 1.5 KB a second, the smallest this encoder makes),
    /// whatever format the microphone gave.
    /// nil when it cannot be read or is still too big for Bluetooth.
    nonisolated static func shrink(_ src: URL) -> Data? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("voice-small.m4a")
        try? FileManager.default.removeItem(at: out)
        defer { try? FileManager.default.removeItem(at: out) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000.0,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 12_000]
        guard let input = try? AVAudioFile(forReading: src) else { return nil }
        do {
            let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let conv = AVAudioConverter(from: input.processingFormat, to: output.processingFormat) else { return nil }
            let inBuf = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096)!
            let ratio = output.processingFormat.sampleRate / input.processingFormat.sampleRate
            var done = false
            while !done {
                let outBuf = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(4096 * ratio) + 64)!
                var err: NSError?
                let status = conv.convert(to: outBuf, error: &err) { _, st in
                    do { try input.read(into: inBuf) } catch { st.pointee = .endOfStream; return nil }
                    if inBuf.frameLength == 0 { st.pointee = .endOfStream; return nil }
                    st.pointee = .haveData; return inBuf
                }
                if outBuf.frameLength > 0 { try output.write(from: outBuf) }
                if status == .endOfStream || status == .error { done = true }
            }
        } catch { return nil }
        guard let raw = try? Data(contentsOf: out) else { return nil }
        let data = VoiceNote.stripPadding(raw)
        guard VoiceNote.looksLikeAudio(data), data.count <= 60_000 else { return nil }
        return data
    }
}

/// Hold to record, let go to send, slide left to cancel.
struct VoiceRecordButton: View {
    @ObservedObject var recorder: VoiceRecorder
    let send: (Data) -> Void
    @State private var cancelling = false
    var body: some View {
        Image(systemName: "mic.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(recorder.isRecording ? Color(hex: 0xE5484D) : Theme.actionBlue,
                        in: RoundedRectangle(cornerRadius: Theme.rButton, style: .continuous))
            .scaleEffect(recorder.isRecording ? 1.15 : 1)
            .animation(.easeOut(duration: 0.15), value: recorder.isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !recorder.isRecording && !cancelling { recorder.start(onFinish: send) }
                        cancelling = v.translation.width < -90
                        if cancelling { recorder.stop(cancel: true) }
                    }
                    .onEnded { _ in
                        if !cancelling { recorder.stop() }
                        cancelling = false
                    }
            )
            .accessibilityLabel(Text(recorder.isRecording ? "Stop and send voice message" : "Record voice message"))
            .accessibilityAddTraits(.isButton)
            // VoiceOver cannot hold: activating starts recording, activating again sends it.
            .accessibilityAction { if recorder.isRecording { recorder.stop() } else { recorder.start(onFinish: send) } }
            .sheet(isPresented: $recorder.denied) { PermissionSheet(ask: .microphoneDenied) { SystemSettings.open() } }
    }
}

/// Shown over the text field while recording: time left and how to cancel.
struct RecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: 0xE5484D)).frame(width: 10, height: 10)
            Text(verbatim: String(format: "0:%02d / 0:%02d", Int(recorder.elapsed), Int(VoiceNote.maxSeconds)))
                .font(.body.monospacedDigit()).foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Label("Slide to cancel", systemImage: "chevron.left").font(.footnote).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 46)
        .glass(radius: Theme.rField)
    }
}

/// Plays one voice note at a time.
@MainActor final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayer()
    @Published private(set) var playing: String?
    @Published private(set) var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ id: String, data: Data?) {
        if playing == id { stop(); return }
        stop()
        guard let data, let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.delegate = self; p.play(); player = p; playing = id; progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }
    func stop() {
        player?.stop(); player = nil; timer?.invalidate(); timer = nil; playing = nil; progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
    /// Loudness of a voice note in `bars` slices, 0...1, for the bars in its bubble.
    nonisolated static func levels(_ data: Data?, bars: Int) -> [Double] {
        let flat = [Double](repeating: 0.15, count: bars)
        guard let data else { return flat }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil, let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return flat }
        let n = Int(buf.frameLength), per = max(1, n / bars)
        var out = (0..<bars).map { b -> Double in
            var sum: Float = 0
            let start = b * per, end = min(n, start + per)
            guard start < end else { return 0 }
            for i in start..<end { sum += ch[i] * ch[i] }
            return Double((sum / Float(end - start)).squareRoot())
        }
        // Scaled to the loudest part, but never below a speaking level, so a near-silent note shows low bars.
        let peak = max(out.max() ?? 0, 0.05)
        out = out.map { max(0.08, min(1, $0 / peak)) }
        return out
    }

    func duration(_ data: Data?) -> TimeInterval {
        guard let data, let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue) else { return 0 }
        return p.duration
    }
}

/// A voice note in the chat: play/pause, a progress line and its length.
struct VoiceBubble: View {
    let id: String
    let mine: Bool
    var progress: Double? = nil
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var player = VoicePlayer.shared
    @State private var length: TimeInterval = 0
    @State private var levels = [Double](repeating: 0.15, count: 28)
    private var isPlaying: Bool { player.playing == id }
    var body: some View {
        HStack(spacing: 10) {
            Button { player.toggle(id, data: store.mediaData(id)) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background((mine ? Color.white : Theme.actionBlue).opacity(0.2), in: Circle())
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isPlaying ? "Pause" : "Play voice message"))
            VStack(alignment: .leading, spacing: 4) {
                // WhatsApp-style sound bars: louder parts are taller; the played part is filled in.
                let played = isPlaying ? player.progress : (progress ?? 0)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(levels.indices, id: \.self) { i in
                        Capsule()
                            .fill((mine ? Color.white : Theme.actionBlue).opacity(Double(i) / Double(levels.count) < played ? 1 : 0.4))
                            .frame(width: 2.5, height: 4 + 20 * levels[i])
                    }
                }.frame(height: 24)
                Text(verbatim: String(format: "0:%02d", Int(length.rounded())))
                    .font(.caption.monospacedDigit()).opacity(0.85)
            }
            .frame(width: 130)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .foregroundStyle(mine ? Color.white : Theme.ink)
        .modifier(BubbleBackground(mine: mine))
        .onAppear {
            let data = store.mediaData(id)
            length = player.duration(data)
            if levels.allSatisfy({ $0 == 0.15 }) { levels = VoicePlayer.levels(data, bars: levels.count) }
        }
    }
}

/// The + menu: "Send to <name>" and one row per kind of attachment, saying how it fits Bluetooth.
private struct AttachSheet: View {
    enum Choice { case photo, camera, location }
    let name: String
    let oneToOne: Bool
    let hasCamera: Bool
    let pick: (Choice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send to \(name)").font(.headline).foregroundStyle(Theme.ink).padding(.horizontal, 4)
            VStack(spacing: 0) {
                if oneToOne {
                    row("Photo", "Made small, about 20 KB, so it fits Bluetooth", "photo", .photo)
                    if hasCamera { Divider().padding(.leading, 70); row("Camera", "Take a photo and send it", "camera", .camera) }
                    Divider().padding(.leading, 70)
                }
                row("Location", "Your position as a map pin", "mappin.and.ellipse", .location)
            }.glass(radius: 16)
            if oneToOne {
                Label("For a voice message, hold the microphone button in the chat.", systemImage: "mic")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(oneToOne ? (hasCamera ? 360 : 290) : 170)])
        .presentationDragIndicator(.visible)
    }
    private func row(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ icon: String, _ c: Choice) -> some View {
        Button { pick(c) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.link)
                    .frame(width: 42, height: 42).background(Theme.actionBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Theme.ink)
                    Text(sub).font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The message status mark (design option D, "ring fill"): sending is a faint ring, sent a quarter, carried by a phone
/// nearby a half, delivered the whole ring with a dot, read a filled mint disc. Told apart by shape, not only by colour.
struct StatusRing: View {
    let state: DeliveryState
    var tint: Color = .white
    var readFill: Color = Color(hex: 0x7CF5C4)
    var readDot: Color = Color(hex: 0x0C447C)
    var size: CGFloat = 13
    private var arc: CGFloat {
        switch state { case .sending, .failed: 0; case .sent: 0.25; case .relayed: 0.5; case .delivered, .read: 1 }
    }
    var body: some View {
        let w = max(1.4, size * 0.12)
        ZStack {
            if state == .read {
                Circle().fill(readFill)
                Circle().fill(readDot).frame(width: size * 0.32, height: size * 0.32)
            } else {
                Circle().stroke(tint.opacity(0.35), lineWidth: w)
                if arc > 0 {
                    Circle().trim(from: 0, to: arc).stroke(tint, style: StrokeStyle(lineWidth: w, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if state == .delivered { Circle().fill(tint).frame(width: size * 0.32, height: size * 0.32) }
            }
        }
        .padding(w / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
