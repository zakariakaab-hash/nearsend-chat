import SwiftUI

/// Name a group and tick who is in it: people in range and saved contacts.
struct NewGroupSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void
    @State private var name = ""
    @State private var picked = Set<String>()

    private var people: [Peer] {
        let inRange = store.peers
        let saved = store.conversations.filter { !$0.isGroup && $0.id != publicChannelID }.map(\.peer)
            .filter { c in !inRange.contains { $0.id == c.id } }
        return inRange + saved
    }
    private var ok: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !picked.isEmpty }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("New group").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Button("Cancel") { dismiss() }.foregroundStyle(.white)
                    }.padding(.top, 20)
                    TextField("Group name", text: $name)
                        .foregroundStyle(Theme.ink).padding(.horizontal, 16).padding(.vertical, 14).glass(radius: Theme.rField)
                        .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
                    Text("Choose members").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Card(padding: 8) { VStack(alignment: .leading, spacing: 0) {
                        if people.isEmpty {
                            Text("Add contacts first: scan a QR code or wait until someone is in range.")
                                .font(.subheadline).foregroundStyle(Theme.inkSecondary).padding(8)
                        }
                        VStack(spacing: 0) {
                            ForEach(people) { p in
                                let on = picked.contains(p.id)
                                Button {
                                    if on { picked.remove(p.id) } else { picked.insert(p.id) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Avatar(name: p.name, size: 40, online: store.peers.contains { $0.id == p.id } && p.hops == 1, avatar: p.avatar)
                                        Text(verbatim: p.name).font(.headline).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                                            .foregroundStyle(on ? Theme.actionBlue : Theme.inkSecondary)
                                    }.padding(8).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    } }
                    PrimaryButton(title: "Create group") {
                        guard ok else { return }
                        onCreated(store.createGroup(name: name, people: people.filter { picked.contains($0.id) }))
                    }
                    .disabled(!ok).opacity(ok ? 1 : 0.4)
                }.padding(.horizontal, 20).readableWidth(560)
            }
        }
        .presentationDetents([.large])
    }
}

/// Members and leaving. Leaving only affects this phone.
struct GroupInfoSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let name: String
    let members: [Member]
    let onLeave: () -> Void
    @State private var confirm = false

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Avatar(name: name, size: 80).padding(.top, 24).accessibilityHidden(true)
                    Text(verbatim: name).font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text("\(members.count) members").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(members, id: \.id) { m in
                                let me = store.isMe(m.id)
                                HStack(spacing: 12) {
                                    Avatar(name: me ? store.nickname : m.name, size: 36,
                                           online: !me && store.peers.contains { $0.id == m.id && $0.hops == 1 })
                                    if me { Text(verbatim: store.nickname + " (") + Text("You") + Text(verbatim: ")") }
                                    else { Text(verbatim: store.peers.first { $0.id == m.id }?.name ?? m.name) }
                                    Spacer()
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { confirm = true } label: {
                        Text("Leave group").fontWeight(.semibold).foregroundStyle(Color(hex: 0xD93025))
                            .frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                    }
                    Button("Close") { dismiss() }.foregroundStyle(.white)
                }.padding(.horizontal, 20).readableWidth(560)
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Leave group", isPresented: $confirm) {
            Button("Leave group", role: .destructive, action: onLeave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This phone forgets the group and ignores its new messages. The others are not told.")
        }
    }
}
