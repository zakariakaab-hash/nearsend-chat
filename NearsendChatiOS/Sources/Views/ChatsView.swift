import SwiftUI

/// The chat list. A real `List`, so rows get the system's full-row taps and WhatsApp-style swipes:
/// swipe right to pin (and mark read/unread), swipe left for Delete and More (mute, lock, favourite, clear).
struct ChatsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("tab") private var tab = 1
    @State private var path: [String] = UserDefaults.standard.bool(forKey: "openThread") ? [UserDefaults.standard.string(forKey: "threadID") ?? "a"] : []
    @State private var newGroup = false
    @State private var toDelete: Conversation?
    @State private var toClear: Conversation?
    @State private var more: Conversation?
    @State private var afterMore: (() -> Void)?
    @State private var addContact = false
    @State private var filter = Filter.all
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var bulkDelete = false

    enum Filter { case all, unread, favorites }

    private var sorted: [Conversation] {
        store.conversations
            .filter {
                switch filter {
                case .all: true
                case .unread: $0.unread > 0
                case .favorites: $0.isFavorite
                }
            }
            .sorted {
                if $0.id == publicChannelID { return true }
                if $1.id == publicChannelID { return false }
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if let a = $0.pinnedAt, let b = $1.pinnedAt { return a > b }
                return ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                SkyBackground()
                List {
                    header.plainRow()
                    if store.conversations.count <= 1 && filter == .all {
                        Card {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 30)).foregroundStyle(Theme.actionBlue)
                                Text("No private chats yet").font(.headline)
                                Text("Open Nearby and tap someone to say hi.").font(.footnote).foregroundStyle(Theme.inkSecondary)
                            }.frame(maxWidth: .infinity)
                        }.plainRow()
                    }
                    ForEach(sorted) { c in
                        Button {
                            if selecting { if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) } }
                            else { path.append(c.id) }
                        } label: {
                            HStack(spacing: 10) {
                                if selecting {
                                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(selected.contains(c.id) ? Theme.actionBlue : .white)
                                        .accessibilityLabel(selected.contains(c.id) ? "Selected" : "Not selected")
                                }
                                row(c)
                            }
                        }
                            .buttonStyle(.plain)
                            .plainRow()
                            .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(c) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(c) }
                            .contextMenu { menu(c) }
                    }
                    if sorted.isEmpty && filter != .all {
                        Text(filter == .unread ? "No unread chats" : "No favourites yet. Swipe left on a chat and tap More.")
                            .font(.subheadline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.top, 24).plainRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                if selecting { selectionBar }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let c = store.conversations.first(where: { $0.id == id }) { ThreadView(conversationID: c.id, peer: c.peer) }
            }
            .alert(deleteTitle, isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), presenting: toDelete) { c in
                Button(c.isGroup ? "Leave group" : "Delete chat", role: .destructive) {
                    if path.contains(c.id) { path.removeAll() }
                    store.deleteConversation(c.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("Only on this phone. The other person keeps their copy.") }
            .alert("Clear messages", isPresented: Binding(get: { toClear != nil }, set: { if !$0 { toClear = nil } }), presenting: toClear) { c in
                Button("Clear messages", role: .destructive) { store.clearChat(c.id) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("Only on this phone. The other person keeps their copy.") }
            // WhatsApp-style "More": a bottom sheet with the chat on top and one row per action.
            .sheet(isPresented: $addContact) {
                AddContactSheet { id in addContact = false; if !id.isEmpty { path = [id] } }.environmentObject(store)
            }
            .sheet(item: $more, onDismiss: { afterMore?(); afterMore = nil }) { c in
                ChatActionsSheet(conversation: c, title: title(c)) { action in
                    switch action {
                    case .pin: store.togglePin(c.id)
                    case .mute: store.toggleMute(c.id)
                    case .lock: store.toggleLock(c.id)
                    case .favourite: store.toggleFavorite(c.id)
                    case .clear: afterMore = { toClear = c }          // the confirmation opens once the sheet is gone
                    case .delete: afterMore = { toDelete = c }
                    }
                    more = nil
                }
            }
            .alert("Delete chats", isPresented: $bulkDelete) {
                Button("Delete \(selected.count)", role: .destructive) {
                    for id in selected where id != publicChannelID { store.deleteConversation(id) }
                    endSelecting()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Only on this phone. The other person keeps their copy.") }
            .sheet(isPresented: $newGroup) {
                NewGroupSheet { id in newGroup = false; path = [id] }.environmentObject(store)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if selecting {
                    Button { endSelecting() } label: {
                        Text("Done").font(.headline).foregroundStyle(Theme.link).padding(.horizontal, 16).frame(height: 44).glass(radius: 22)
                    }.buttonStyle(.plain)
                } else {
                    Menu {
                        Button { selecting = true } label: { Label("Select chats", systemImage: "checkmark.circle") }
                        Button { for c in store.conversations where c.unread > 0 { store.toggleUnread(c.id) } } label: {
                            Label("Read all", systemImage: "envelope.open")
                        }
                        Button { newGroup = true } label: { Label("New group", systemImage: "person.3") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.link)
                            .frame(width: 44, height: 44).glass(radius: 22)
                    }.accessibilityLabel("More options")
                }
                Spacer()
                // WhatsApp-style +: start a chat (people are picked on Nearby) or a group.
                Menu {
                    Button { tab = 0 } label: { Label("New chat with someone nearby", systemImage: "dot.radiowaves.left.and.right") }
                    Button { addContact = true } label: { Label("Add contact", systemImage: "qrcode.viewfinder") }
                    Button { newGroup = true } label: { Label("New group", systemImage: "person.3") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.link)
                        .frame(width: 44, height: 44).glass(radius: 22)
                }.accessibilityLabel("New chat or group")
            }
            PageTitle(text: selecting ? "\(selected.count) selected" : "Chats")
            // Scrolls sideways at large text sizes instead of breaking the words.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(selected: filter == .all, action: { filter = .all }) { Text("All").fixedSize() }
                    ChipButton(selected: filter == .unread, action: { filter = .unread }) { Text("Unread").fixedSize() }
                    ChipButton(selected: filter == .favorites, action: { filter = .favorites }) { Text("Favourites").fixedSize() }
                }
            }.scrollClipDisabled()
        }.padding(.top, 8)
    }

    // MARK: selecting

    private func endSelecting() { selecting = false; selected.removeAll() }

    /// Bottom bar while selecting: actions for every ticked chat.
    private var selectionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                barButton("Pin", "pin") { for id in selected where id != publicChannelID { store.togglePin(id) }; endSelecting() }
                barButton("Mute", "bell.slash") { for id in selected { store.toggleMute(id) }; endSelecting() }
                barButton("Read", "envelope.open") {
                    for id in selected { if store.conversations.first(where: { $0.id == id })?.unread ?? 0 > 0 { store.toggleUnread(id) } }
                    endSelecting()
                }
                barButton("Delete", "trash", destructive: true) { bulkDelete = true }
            }
            .disabled(selected.isEmpty)
            .padding(.vertical, 10).glass(radius: Theme.rCard).padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private func barButton(_ title: LocalizedStringKey, _ icon: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) { Image(systemName: icon).font(.system(size: 18)); Text(title).font(.caption2) }
                .foregroundStyle(destructive ? Color.red : Theme.link).frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    // MARK: actions

    // Swipe buttons follow the app's look: round, icon only, in the app's own colours (the name stays for VoiceOver).
    @ViewBuilder private func leadingActions(_ c: Conversation) -> some View {
        if c.id != publicChannelID {
            Button { store.togglePin(c.id) } label: {
                Label(c.isPinned ? "Unpin" : "Pin", systemImage: c.isPinned ? "pin.slash.fill" : "pin.fill").labelStyle(.iconOnly)
            }.tint(Theme.actionBlue)
        }
        Button { store.toggleUnread(c.id) } label: {
            Label(c.unread > 0 ? "Read" : "Unread", systemImage: c.unread > 0 ? "envelope.open.fill" : "envelope.badge.fill").labelStyle(.iconOnly)
        }.tint(Color(hex: 0x1F9D63))
    }

    @ViewBuilder private func trailingActions(_ c: Conversation) -> some View {
        if c.id == publicChannelID {
            Button { toClear = c } label: { Label("Clear messages", systemImage: "trash.fill").labelStyle(.iconOnly) }.tint(Color(hex: 0xE5484D))
        } else {
            Button { toDelete = c } label: {
                Label(c.isGroup ? "Leave group" : "Delete chat", systemImage: "trash.fill").labelStyle(.iconOnly)
            }.tint(Color(hex: 0xE5484D))
        }
        Button { more = c } label: { Label("More", systemImage: "ellipsis").labelStyle(.iconOnly) }.tint(Theme.brandBlue)
    }

    /// Long-press menu and the "More" sheet share these.
    @ViewBuilder private func menu(_ c: Conversation) -> some View {
        if c.id != publicChannelID {
            Button { store.togglePin(c.id) } label: { Label(c.isPinned ? "Unpin" : "Pin", systemImage: c.isPinned ? "pin.slash" : "pin") }
        }
        Button { store.toggleMute(c.id) } label: { Label(c.isMuted ? "Unmute" : "Mute", systemImage: c.isMuted ? "bell" : "bell.slash") }
        if c.id != publicChannelID {
            Button { store.toggleLock(c.id) } label: { Label(c.isLocked ? "Unlock chat" : "Lock chat", systemImage: c.isLocked ? "lock.open" : "lock") }
        }
        Button { store.toggleFavorite(c.id) } label: {
            Label(c.isFavorite ? "Remove from favourites" : "Add to favourites", systemImage: c.isFavorite ? "heart.slash" : "heart")
        }
        Button(role: .destructive) { toClear = c } label: { Label("Clear messages", systemImage: "eraser") }
        if c.id != publicChannelID {
            Button(role: .destructive) { toDelete = c } label: { Label(c.isGroup ? "Leave group" : "Delete chat", systemImage: "trash") }
        }
    }

    private var deleteTitle: LocalizedStringKey { toDelete?.isGroup == true ? "Leave group" : "Delete chat" }
    private func title(_ c: Conversation) -> String { c.id == publicChannelID ? localized("Nearby channel") : c.peer.name }

    // MARK: row

    private func row(_ c: Conversation) -> some View {
        let isPublic = c.id == publicChannelID
        // At accessibility text sizes the picture goes above the text and the time below the name, so names are not split into syllables.
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        let header = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        return Card(padding: 12) {
            layout {
                Avatar(name: isPublic ? "#" : c.peer.name, size: 52, online: !isPublic && !c.isGroup && c.peer.hops == 1, avatar: c.peer.shownAvatar).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    header {
                        HStack(spacing: 6) {
                            if isPublic { Text("Nearby channel").font(.headline) } else { Text(verbatim: c.peer.name).font(.headline).lineLimit(big ? 3 : 1) }
                            if c.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink).accessibilityLabel("Favourite") }
                        }
                        if !big { Spacer() }
                        if let d = c.last?.date { Text(d, style: .time).font(.caption).foregroundStyle(Theme.inkSecondary) }
                    }
                    HStack(spacing: 6) {
                        Group {
                            if c.isRequest { Label("Message request", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(Theme.link) }
                            else if c.isLocked { Label("Locked chat", systemImage: "lock.fill") }
                            else if c.last != nil { Text(verbatim: preview(c)) }
                            else if isPublic { Text("Public · anyone in range can read this") }
                            else { Text(verbatim: "") }
                        }.font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(big ? 2 : 1)
                        Spacer()
                        if c.isMuted { Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(Theme.inkSecondary).accessibilityLabel("Muted") }
                        if c.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Theme.inkSecondary).accessibilityLabel("Pinned") }
                        if c.unread > 0 {
                            Text("\(c.unread)").font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(c.isMuted ? Color.gray : Theme.actionBlue, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func preview(_ c: Conversation) -> String {
        guard let m = c.last else { return "" }
        if let media = m.mediaLabel { return media }
        let text = Reply.split(m.text)?.body ?? m.text
        if let s = m.sender { return "\(s): \(text)" }
        return text
    }
}

private extension View {
    /// A list row that looks like the old card stack: no separators, no system background, same side margins.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }
}

/// The chat actions behind a swipe's "More", laid out like WhatsApp: the chat, then grouped rows with icons.
private struct ChatActionsSheet: View {
    enum Action { case pin, mute, lock, favourite, clear, delete }
    let conversation: Conversation
    let title: String
    let act: (Action) -> Void
    private var c: Conversation { conversation }
    private var isPublic: Bool { c.id == publicChannelID }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: isPublic ? "#" : c.peer.name, size: 44, avatar: c.peer.shownAvatar).accessibilityHidden(true)
                Text(verbatim: title).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
            }.padding(.horizontal, 4)
            VStack(spacing: 0) {
                if !isPublic { row(c.isPinned ? "Unpin" : "Pin", c.isPinned ? "pin.slash" : "pin", .pin) ; divider }
                row(c.isMuted ? "Unmute" : "Mute", c.isMuted ? "bell" : "bell.slash", .mute)
                if !isPublic { divider; row(c.isLocked ? "Unlock chat" : "Lock chat", c.isLocked ? "lock.open" : "lock", .lock) }
                divider
                row(c.isFavorite ? "Remove from favourites" : "Add to favourites", c.isFavorite ? "heart.slash" : "heart", .favourite)
            }.glass(radius: 16)
            VStack(spacing: 0) {
                row("Clear messages", "eraser", .clear, destructive: true)
                if !isPublic { divider; row(c.isGroup ? "Leave group" : "Delete chat", c.isGroup ? "rectangle.portrait.and.arrow.right" : "trash", .delete, destructive: true) }
            }.glass(radius: 16)
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(isPublic ? 300 : 430)])
        .presentationDragIndicator(.visible)
    }
    private var divider: some View { Divider().padding(.leading, 52) }
    private func row(_ label: LocalizedStringKey, _ icon: String, _ a: Action, destructive: Bool = false) -> some View {
        Button { act(a) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Text(label).font(.body)
                Spacer()
            }
            .foregroundStyle(destructive ? Color(hex: 0xE5484D) : Theme.ink)
            .padding(.horizontal, 14).frame(height: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// + › Add contact: scan a friend's code (camera) or paste the code they sent.
struct AddContactSheet: View {
    @EnvironmentObject var store: ChatStore
    let opened: (String) -> Void
    @State private var pasted = ""
    @State private var scanning = false
    @State private var problem: LocalizedStringKey?
    @State private var showMine = false
    @State private var cameraAsk: PermissionAsk?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if CodeScanner.supported {
                        Button { CameraAccess.check(ok: { scanning = true }, denied: { cameraAsk = .cameraDenied }) } label: {
                            Label("Scan their code", systemImage: "qrcode.viewfinder")
                        }
                    }
                    Button { showMine = true } label: { Label("Show my code", systemImage: "qrcode") }
                } footer: { Text("Scan each other's codes, so you can both write. Messages reach them even far away, carried by phones in between.") }
                Section {
                    TextField("nearsend:c:…", text: $pasted, axis: .vertical).lineLimit(2...4)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.footnote, design: .monospaced))
                    Button("Add") { add(pasted, inPerson: false) }.disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("Or paste a code") } footer: {
                    if let problem { Text(problem).foregroundStyle(.red) } else { Text("A friend can send their code from Show my code › Share my code.") }
                }
            }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { opened("") } } }
            .fullScreenCover(isPresented: $scanning) {
                CodeScanner { code in scanning = false; if let code { add(code, inPerson: true) } }.ignoresSafeArea()
            }
            .sheet(item: $cameraAsk) { a in PermissionSheet(ask: a) { SystemSettings.open() } }
            .sheet(isPresented: $showMine) {
                MyCodeSheet(payload: store.myCodePayload, fingerprint: store.myFingerprint, contactCode: store.myContactCode)
            }
        }
    }
    private func add(_ code: String, inPerson: Bool) {
        switch store.addContact(code: code, inPerson: inPerson) {
        case .added(let id, _): opened(id)
        case .itsYou: problem = "That is your own code."
        case .invalid: problem = "That is not a Nearsend contact code."
        }
    }
}
