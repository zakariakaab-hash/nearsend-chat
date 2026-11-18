import SwiftUI

struct IdentityView: View {
    @EnvironmentObject var store: ChatStore
    @State private var confirmWipe = false
    @State private var pickAvatar = false
    @State private var shareLog = false
    @State private var mail: URL?
    @AppStorage("language") private var language = "system"

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        PageTitle(text: "You").padding(.top, 8)
                            .onTapGesture(count: 3) { confirmWipe = true }   // panic: triple-tap
                        Card {
                            VStack(spacing: 12) {
                                Button { pickAvatar = true } label: { Avatar(name: store.nickname, size: 88, avatar: store.myAvatar) }
                                    .buttonStyle(.plain).accessibilityLabel("Your picture")
                                Text("Tap to change").font(.caption).foregroundStyle(Theme.link)
                                TextField("Nickname", text: $store.nickname)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .submitLabel(.done)
                                    .onSubmit { store.applyNickname() }
                                StatusPill(text: "No account · no phone number")
                            }.frame(maxWidth: .infinity)
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Your fingerprint", systemImage: "key.fill").font(.subheadline.weight(.semibold))
                                Text(verbatim: store.myFingerprint.isEmpty ? "—" : store.myFingerprint)
                                    .font(.system(.callout, design: .monospaced)).foregroundStyle(Theme.link)
                                Text("Compare this in person to verify a contact. It changes if you erase everything.")
                                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Card {
                            HStack {
                                Label("Language", systemImage: "globe").font(.subheadline.weight(.semibold))
                                Spacer()
                                Picker("Language", selection: $language) {
                                    Text("System default").tag("system")
                                    ForEach(AppLanguage.all) { Text(verbatim: $0.name).tag($0.code) }
                                }.pickerStyle(.menu).tint(Theme.link)
                            }
                        }
                        PrivacyCard()
                        VStack(spacing: 6) {
                            Button { shareLog = true } label: {
                                Label("Share debug log", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.link).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                            }
                            Text("Last 500 events: who connected, packet types, errors. No messages, photos or keys.")
                                .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 8)
                        }
                        VStack(spacing: 6) {
                            Button { mail = Support.contactURL } label: {
                                Label("Contact us", systemImage: "envelope.fill").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.link).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                            }
                            Text("To report someone, long-press their message or open their contact info and tap Report.")
                                .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 8)
                        }
                        Button(role: .destructive) { confirmWipe = true } label: {
                            Label("Erase everything", systemImage: "trash.fill").font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 14).glass(radius: Theme.rButton)
                        }
                        SkyPill {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Project status", systemImage: "hammer.fill").font(.subheadline.weight(.semibold))
                                Text("Early development. Not security audited. Not tested on many devices yet. Bitchat compatibility unverified. GPL-3.0.")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 20).readableWidth()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .opensMail($mail)
            .sheet(isPresented: $pickAvatar) { AvatarPickerSheet().environmentObject(store) }
            .sheet(isPresented: $shareLog) {
                let head = "Nearsend Chat debug log\n\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n\n"
                ShareSheet(items: [head + (NLog.dump().isEmpty ? "(no events yet)" : NLog.dump())])
            }
            .confirmationDialog("Erase all messages, keys and settings on this phone?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { store.wipeAll() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone. You will get a new identity.") }
        }
    }
}
