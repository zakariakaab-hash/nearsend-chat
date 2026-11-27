import LocalAuthentication
import SwiftUI
import VisionKit

struct IdentityView: View {
    @EnvironmentObject var store: ChatStore
    @State private var confirmWipe = false
    @State private var pickAvatar = false

    @State private var showScanner = false
    @AppStorage("language") private var language = "system"
    @State private var showMyCode = false
    @State private var scanResult: String?      // the verified person's name, or "" when the code matched nobody

    private func rowGroup<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0, content: c).glass().buttonStyle(.plain)
    }
    private var rowDivider: some View { Divider().padding(.leading, 62) }

    /// Profile and code in one card: "My code" opens the QR, fingerprint and share link; "Scan" adds or verifies a friend.
    private var profileCard: some View {
        Card {
            VStack(spacing: 12) {
                Button { pickAvatar = true } label: { Avatar(name: store.nickname, size: 88, avatar: store.myAvatar) }
                    .buttonStyle(.plain).accessibilityLabel("Your picture")
                Text("Tap to change").font(.caption).foregroundStyle(Theme.link)
                TextField("Nickname", text: $store.nickname)
                    .multilineTextAlignment(.center)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .submitLabel(.done)
                    .onSubmit { store.applyNickname() }
                StatusPill(text: "No account · no phone number")
                Group {
                    HStack(spacing: 10) {
                        Button { showMyCode = true } label: {
                            Label("My code", systemImage: "qrcode").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                        }
                        if CodeScanner.available {
                            Button { showScanner = true } label: {
                                Label("Scan", systemImage: "qrcode.viewfinder").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(Theme.link).background(Theme.actionBlue.opacity(0.12), in: Capsule())
                            }
                        }
                    }.padding(.top, 4)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        PageTitle(text: "You").padding(.top, 8)
                            .onTapGesture(count: 3) { confirmWipe = true }   // panic: triple-tap
                        profileCard
                        // Like WhatsApp: the settings are rows right here, each opening its own page.
                        rowGroup {
                            NavigationLink { AccountSettingsView() } label: { SettingsRow(icon: "key", title: "Account") }
                            rowDivider
                            NavigationLink { PrivacySettingsView() } label: { SettingsRow(icon: "lock", title: "Privacy") }
                            rowDivider
                            NavigationLink { NotificationSettingsView() } label: { SettingsRow(icon: "bell", title: "Notifications") }
                            rowDivider
                            NavigationLink { ConnectionView() } label: {
                                SettingsRow(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth",
                                            value: LocalizedStringKey(store.bluetoothLabel))
                            }
                            rowDivider
                            HStack(spacing: 14) {
                                SettingsIcon(icon: "globe")
                                Text("Language").foregroundStyle(Theme.ink).layoutPriority(1)
                                Spacer(minLength: 4)
                                Picker("Language", selection: $language) {
                                    Text("System default").tag("system")
                                    ForEach(AppLanguage.all) { Text(verbatim: $0.name).tag($0.code) }
                                }.pickerStyle(.menu).labelsHidden().tint(Theme.inkSecondary).lineLimit(1).fixedSize()
                            }.padding(.horizontal, 16).frame(minHeight: 56)
                        }
                        rowGroup {
                            NavigationLink { ShareAppView() } label: { SettingsRow(icon: "heart", title: "Invite a friend") }
                            rowDivider
                            NavigationLink { HelpSettingsView() } label: { SettingsRow(icon: "questionmark.circle", title: "Help") }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 24).readableWidth()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $pickAvatar) { AvatarPickerSheet().environmentObject(store) }
            .sheet(isPresented: $showMyCode) { MyCodeSheet(payload: store.myCodePayload, fingerprint: store.myFingerprint, contactCode: store.myContactCode) }
            .fullScreenCover(isPresented: $showScanner) {
                CodeScanner { code in
                    showScanner = false
                    if let code { scanResult = store.verifyScanned(code) ?? "" }
                }.ignoresSafeArea()
            }
            .alert(scanResult.map { $0.isEmpty ? localized("No match") : $0 } ?? "", isPresented: Binding(get: { scanResult != nil }, set: { if !$0 { scanResult = nil } })) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(scanResult?.isEmpty == true
                    ? "This code doesn't belong to anyone nearby or in your chats. Be near them and try again."
                    : "Fingerprint matches. Marked as verified."))
            }
            .bottomConfirm(isPresented: $confirmWipe, title: "Erase all messages, keys and settings on this phone?",
                           message: "This cannot be undone. You will get a new identity.", action: "Erase everything") { store.wipeAll() }
        }
    }
}

// MARK: - Settings

/// A row like WhatsApp's settings: plain outline icon, title, optional value, chevron.
struct SettingsRow: View {
    let icon: String
    let title: LocalizedStringKey
    var value: LocalizedStringKey? = nil
    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(icon: icon)
            Text(title).foregroundStyle(Theme.ink)
            Spacer()
            if let value { Text(value).foregroundStyle(Theme.inkSecondary) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary.opacity(0.7))
        }
        .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
    }
}

struct SettingsIcon: View {
    let icon: String
    var body: some View {
        Image(systemName: icon).font(.system(size: 19, weight: .regular)).foregroundStyle(Theme.ink)
            .frame(width: 32, height: 32)
    }
}

/// One settings page: a native grouped list on the sky.
struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            SkyBackground()
            List { content }.scrollContentBackground(.hidden).tint(Theme.actionBlue).labelStyle(PlainIconLabelStyle())
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Settings icons are plain and dark, like WhatsApp's; the list would tint them blue otherwise.
struct PlainIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) { configuration.icon.foregroundStyle(Theme.ink).frame(width: 28); configuration.title }
    }
}

/// Section titles and notes sit on the blue sky: white, so they stay readable.
func settingHead(_ t: LocalizedStringKey) -> some View { Text(t).font(.footnote.weight(.semibold)).foregroundStyle(.white) }
func settingFoot(_ t: LocalizedStringKey) -> some View { Text(t).foregroundStyle(.white.opacity(0.9)) }

func settingToggle(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, icon: String, _ on: Binding<Bool>) -> some View {
    Toggle(isOn: on) {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        } icon: { Image(systemName: icon) }
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject var store: ChatStore
    @AppStorage("appLock") private var appLock = false
    @State private var lockError = false

    var body: some View {
        SettingsPage(title: "Privacy") {
            Section {
                Picker(selection: $store.strangers) {
                    Text("Ask me").tag(ChatStore.StrangerPolicy.ask)
                    Text("Allow").tag(ChatStore.StrangerPolicy.allow)
                    Text("Block").tag(ChatStore.StrangerPolicy.block)
                } label: { Label("Messages from strangers", systemImage: "person.crop.circle.badge.questionmark") }
                settingToggle("Hide me from strangers", "People nearby see \u{201C}\(ChatStore.hiddenName)\u{201D} instead of your name and picture. People you already chat with still see your name.",
                              icon: "eye.slash", $store.hideFromStrangers)
            } header: { settingHead("Strangers") } footer: { settingFoot(LocalizedStringKey(strangerFooter)) }
            Section {
                Toggle(isOn: Binding(get: { appLock }, set: { setAppLock($0) })) { Label("App lock", systemImage: "faceid") }
                settingToggle("Delivery receipts", "Let senders see when their message reached you.", icon: "checkmark.circle", $store.receipts)
                Picker(selection: $store.autoDeleteDays) {
                    Text("Never").tag(0); Text("1 day").tag(1); Text("\(7) days").tag(7); Text("\(30) days").tag(30)
                } label: { Label("Delete messages after", systemImage: "timer") }
            }
        }
        .alert("Set a passcode first", isPresented: $lockError) { Button("OK", role: .cancel) {} } message: {
            Text("App lock uses Face ID, Touch ID or your iPhone passcode. Turn on a passcode in Settings › Face ID & Passcode.")
        }
    }

    private var strangerFooter: String {
        switch store.strangers {
        case .ask: return "Strangers are people you have no chat with yet. Their first message waits as a request: you choose to accept or block. They don't see that you read it."
        case .allow: return "Strangers are people you have no chat with yet. Their messages arrive like any other."
        case .block: return "Strangers are people you have no chat with yet. Their messages are dropped. People you add by code or start a chat with can always write."
        }
    }

    /// Turning App lock on asks for Face ID first, so nobody locks themselves out with a sensor that does not work.
    private func setAppLock(_ on: Bool) {
        guard on else { appLock = false; return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { lockError = true; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localized("Turn on App lock")) { ok, _ in
            Task { @MainActor in if ok { appLock = true } }
        }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        SettingsPage(title: "Notifications") {
            Section {
                settingToggle("Hide text in notifications", "Notifications show who wrote, not what.", icon: "bell.slash", $store.hidePreviews)
                settingToggle("Notify me when a friend is nearby", "When someone you chat with comes back in range after 30 minutes away. At most every 2 hours per person. Works while the app is open or running in the background.",
                              icon: "person.2.wave.2", $store.friendNearbyAlerts)
                settingToggle("Announcements", "Show announcements from people nearby and notify me. Off: they are hidden, but your phone still passes them on.",
                              icon: "megaphone", $store.showAnnouncements)
            }
        }
    }
}

/// Like WhatsApp's Account page: the things that concern the identity itself.
struct AccountSettingsView: View {
    @EnvironmentObject var store: ChatStore
    @State private var transfer = false
    @State private var confirmWipe = false

    var body: some View {
        SettingsPage(title: "Account") {
            Section {
                Button { transfer = true } label: { Label("Move to another phone", systemImage: "iphone.and.arrow.forward") }
                    .foregroundStyle(Theme.ink)
            } footer: {
                settingFoot("Moves your identity, chats and contacts to a new iPhone with a password-protected file.")
            }
            Section {
                Button(role: .destructive) { confirmWipe = true } label: { Label("Erase everything", systemImage: "trash") }
            } footer: {
                settingFoot("Deletes all messages, keys and settings on this phone. You get a new identity. This cannot be undone.")
            }
        }
        .sheet(isPresented: $transfer) { TransferSheet().environmentObject(store) }
        .bottomConfirm(isPresented: $confirmWipe, title: "Erase all messages, keys and settings on this phone?",
                       message: "This cannot be undone. You will get a new identity.", action: "Erase everything") { store.wipeAll() }
    }
}

/// Like WhatsApp's Help page: help center, feedback, terms and privacy, licences, app version.
struct HelpSettingsView: View {
    @AppStorage("onboarded") private var onboarded = true
    @Environment(\.openURL) private var openURL
    @State private var shareLog = false
    @State private var mail: URL?

    static let helpCenter = URL(string: "https://chat.nearsend.app/support/")!
    static let privacyPolicy = URL(string: "https://chat.nearsend.app/privacy/")!
    /// The app has no terms of its own: Apple's standard licence agreement applies to App Store apps.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "") (\(i?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        SettingsPage(title: "Help") {
            Section {
                Button { openURL(Self.helpCenter) } label: { Label("Help center", systemImage: "questionmark.circle") }
                    .foregroundStyle(Theme.ink)
                Button { mail = Support.feedbackURL } label: { Label("Send feedback", systemImage: "bubble.left.and.text.bubble.right") }
                    .foregroundStyle(Theme.ink)
                NavigationLink { TermsView() } label: { Label("Terms and Privacy Policy", systemImage: "doc.text") }
                NavigationLink { LicencesView() } label: { Label("Licences", systemImage: "doc.plaintext") }
                HStack {
                    Label("App version", systemImage: "info.circle")
                    Spacer()
                    Text(verbatim: Self.version).foregroundStyle(Theme.inkSecondary)
                }
            }
            Section {
                Button { onboarded = false } label: { Label("Show the intro", systemImage: "play.circle") }.foregroundStyle(Theme.ink)
                Button { shareLog = true } label: { Label("Share debug log", systemImage: "ladybug") }.foregroundStyle(Theme.ink)
            } footer: {
                settingFoot("The debug log has the last 500 events: who connected, packet types, errors. No messages, photos or keys. To report someone, long-press their message or open their contact info and tap Report.")
            }
        }
        .opensMail($mail)
        .sheet(isPresented: $shareLog) {
            let head = "Nearsend Chat debug log\n\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n\n"
            ShareSheet(items: [head + (NLog.dump().isEmpty ? "(no events yet)" : NLog.dump())])
        }
    }
}

struct TermsView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        SettingsPage(title: "Terms and Privacy Policy") {
            Section {
                Button { openURL(HelpSettingsView.privacyPolicy) } label: { Label("Privacy policy", systemImage: "hand.raised") }
                    .foregroundStyle(Theme.ink)
                Button { openURL(HelpSettingsView.terms) } label: { Label("Terms of use", systemImage: "doc.text") }
                    .foregroundStyle(Theme.ink)
            } footer: {
                settingFoot("Nearsend Chat has no accounts and collects no data. The terms of use are Apple's standard licence agreement for App Store apps.")
            }
        }
    }
}

/// The licences of the app and of what it includes.
struct LicencesView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        SettingsPage(title: "Licences") {
            Section {
                licence("Nearsend Chat", "GNU General Public License v3.0. A fork of Bitchat. The source code is public.",
                        url: "https://github.com/zakariakaab-hash/nearsend-chat")
                licence("Anton font", "Vernon Adams. SIL Open Font License 1.1.", url: "https://openfontlicense.org")
            } footer: {
                settingFoot("Everything else is Apple's own system frameworks (SwiftUI, Core Bluetooth, CryptoKit).")
            }
        }
    }

    private func licence(_ name: String, _ text: LocalizedStringKey, url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name).font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

/// What the Bluetooth link is doing, in plain words: on or off, who is reachable, and why it may be slower; plus the
/// switches that change how it works.
struct ConnectionView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var power = PowerMode.shared
    @State private var batteryLow = false

    private var direct: Int { max(0, store.peers.count - store.relayedCount) }

    var body: some View {
        SettingsPage(title: "Bluetooth") {
            Section {
                row("Bluetooth", "antenna.radiowaves.left.and.right", Text(LocalizedStringKey(store.bluetoothLabel)))
                row("In range", "dot.radiowaves.left.and.right", Text(verbatim: "\(direct)"))
                row("Through other phones", "point.3.connected.trianglepath.dotted", Text(verbatim: "\(store.relayedCount)"))
            } header: {
                Text("Bluetooth connects you to Nearsend phones nearby, with no Wi-Fi, no cell signal and no internet.")
                    .font(.subheadline).foregroundStyle(.white).textCase(nil).padding(.bottom, 6)
            }
            if !store.simulated && ["off", "unauthorized"].contains(store.bluetoothState) {
                Section {
                    if store.bluetoothState == "off" {
                        Label("Bluetooth is off. Turn it on in Control Center to find people nearby.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    } else {
                        Button { SystemSettings.open() } label: { Label("Open Settings", systemImage: "gear") }
                    }
                }
            }
            Section {
                settingToggle("Battery saver", "Black screen, no animations, dimmer screen, and Bluetooth looks for phones less often while you are connected.",
                              icon: "battery.25", $power.saver)
                settingToggle("Pass on messages for others", "Helps messages travel further and reach people who are away. Uses some battery.",
                              icon: "arrow.triangle.branch", $store.relayOthers)
                settingToggle("Demo mode", "Shows sample people and chats, so you can try the app without another phone. Bluetooth is off while it is on; your own chats come back when you turn it off.",
                              icon: "play.rectangle", Binding(get: { store.simulated }, set: { store.setDemo($0) }))
            }
            Section {
                if let saving = savingText {
                    Label { Text(LocalizedStringKey(saving)) } icon: { Image(systemName: "battery.25") }
                        .font(.footnote).foregroundStyle(Color(hex: 0xB45309))
                }
                Label("In the background iPhone slows Bluetooth down, and nothing works after you swipe the app away. Leave it open in the background.",
                      systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
        .onAppear { batteryLow = PowerMode.batteryLow }
    }

    /// Why Bluetooth looks for phones less often right now, if it does.
    private var savingText: String? {
        if power.saver { return "Battery saver is on: Nearsend looks for phones less often while you are connected. Messages may arrive a little later." }
        if power.systemLowPower { return "Low Power Mode is on: Nearsend looks for phones less often while you are connected. Messages may arrive a little later." }
        if batteryLow { return "Low battery: Nearsend looks for phones less often while you are connected. Messages may arrive a little later." }
        return nil
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ value: Text) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); value.foregroundStyle(Theme.inkSecondary) }
    }
}

/// Recommend the app to the person next to you: a QR their camera opens as the App Store page.
struct ShareAppView: View {
    @State private var howItWorks = false
    @Environment(\.openURL) private var openURL
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6839386595")!

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Recommend Nearsend Chat to the person next to you.")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.top, 8)
                    Card {
                        VStack(spacing: 12) {
                            if let img = MyCodeSheet.qr(Self.appStoreURL.absoluteString) {
                                Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 200, height: 200).padding(14)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .accessibilityLabel(Text("QR code of the App Store page"))
                            }
                            Text("Scan with the camera").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }.frame(maxWidth: .infinity)
                    }
                    ShareLink(item: Self.appStoreURL) {
                        Label("Share link", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                    }
                    Button { openURL(Self.appStoreURL) } label: {
                        Label("Nearsend Chat on the App Store", systemImage: "arrow.up.forward.app").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.link).background(.white.opacity(0.85), in: Capsule())
                    }
                }.padding(.horizontal, 20).padding(.bottom, 24).readableWidth()
            }
        }
        .navigationTitle("Invite a friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { howItWorks = true } label: { Image(systemName: "info.circle") }.accessibilityLabel(Text("How does it work?"))
            }
        }
        .sheet(isPresented: $howItWorks) {
            VStack(alignment: .leading, spacing: 18) {
                Text("How does it work?").font(.title2.weight(.bold)).padding(.top, 24)
                step("qrcode", "Show the code to the person next to you: their camera opens Nearsend Chat on the App Store.")
                step("arrow.down.circle", "They need internet once, to download it. After that it works with no signal.")
                step("person.2", "Then add each other: tap My code on the You tab and scan.")
                Spacer()
                Button { howItWorks = false } label: {
                    Text("Got it").font(.headline).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(.white).background(Theme.actionBlue, in: Capsule())
                }
            }
            .padding(24)
            .presentationDetents([.medium])
        }
    }

    private func step(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.link).frame(width: 30)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Make a password-protected transfer file on the old phone, or restore one on the new phone.
struct TransferSheet: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var includePhotos = true
    @State private var working = false
    @State private var file: URL?
    @State private var pickFile = false
    @State private var picked: URL?
    @State private var confirmRestore = false
    @State private var error: String?
    @State private var restored = false

    private var passwordOK: Bool { password.count >= 10 && (mode == 1 || password == repeatPassword) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) {
                    Text("This is the old phone").tag(0)
                    Text("This is the new phone").tag(1)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if mode == 0 {
                    Section {
                        SecureField("Password (at least 10 characters)", text: $password).textContentType(.newPassword)
                        SecureField("Repeat the password", text: $repeatPassword).textContentType(.newPassword)
                        Toggle("Include photos and voice notes", isOn: $includePhotos)
                    } header: { Text("1 · Make a transfer file") } footer: {
                        Text("The file holds your identity, chats and contacts, locked with this password. Without it nobody can open the file, not even us. Nothing is uploaded: you choose where the file goes.")
                    }
                    Section {
                        Button { make() } label: {
                            HStack { Text("Make the file"); Spacer(); if working { ProgressView() } }
                        }.disabled(!passwordOK || working)
                        if let file {
                            ShareLink(item: file) { Label("Send the file to the new phone", systemImage: "square.and.arrow.up") }
                        }
                    } footer: {
                        Text("Send it with AirDrop or save it to Files. When the new phone works, erase this one: the same identity on two phones confuses delivery.")
                    }
                } else {
                    Section {
                        Button { pickFile = true } label: {
                            Label(picked?.lastPathComponent ?? localized("Choose the transfer file"), systemImage: "doc")
                        }
                        SecureField("Password", text: $password).textContentType(.password)
                    } header: { Text("Restore from a file") } footer: {
                        Text("This replaces the identity, chats and settings on this phone with the ones in the file.")
                    }
                    Section {
                        Button(role: .destructive) { confirmRestore = true } label: {
                            HStack { Text("Restore"); Spacer(); if working { ProgressView() } }
                        }.disabled(picked == nil || password.isEmpty || working)
                    }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
                if restored { Section { Label("Done. This phone now has your identity and chats.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.secure) } }
            }
            .navigationTitle("Move to another phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: mode) { _, _ in password = ""; repeatPassword = ""; error = nil; file = nil }
            .fileImporter(isPresented: $pickFile, allowedContentTypes: [.item]) { r in
                if case .success(let url) = r { picked = url; error = nil }
            }
            .bottomConfirm(isPresented: $confirmRestore, title: "Replace everything on this phone?",
                           message: "The identity, chats and settings here are replaced by the ones in the file.", action: "Restore") { restore() }
        }
    }

    /// PBKDF2 with 600,000 rounds takes a moment: run it off the main thread's critical path, then share the file.
    private func make() {
        working = true; error = nil
        let pw = password, photos = includePhotos
        Task {
            do { file = try store.makeTransferFile(password: pw, includePhotos: photos) }
            catch { self.error = error.localizedDescription }
            working = false
        }
    }

    private func restore() {
        guard let picked else { return }
        working = true; error = nil
        let pw = password
        Task {
            do { try store.restoreTransfer(from: picked, password: pw); restored = true }
            catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

/// A QR code of our fingerprint, for a friend to scan with "Scan a code".
struct MyCodeSheet: View {
    let payload: String
    let fingerprint: String
    var contactCode: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text("Your code").font(.title3.weight(.semibold))
            if let img = Self.qr(payload) {
                Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel(Text("QR code of your fingerprint"))
            }
            VStack(spacing: 6) {
                Label("Your fingerprint", systemImage: "key.fill").font(.subheadline.weight(.semibold))
                Text(verbatim: fingerprint).font(.system(.callout, design: .monospaced)).foregroundStyle(Theme.link)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Compare this in person to verify a contact. It changes if you erase everything.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text(contactCode == nil ? "Let a friend scan this to verify you. Do it in person."
                 : "A friend scans this with Add contact to chat with you, even from far away. Scan theirs too, so you can both write.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let contactCode {
                ShareLink(item: contactCode) { Label("Share my code", systemImage: "square.and.arrow.up") }
                    .font(.subheadline.weight(.semibold))
            }
            Button("Done") { dismiss() }.font(.headline)
        }
        .padding(24)
        .presentationDetents([.large])
    }
    static func qr(_ s: String) -> UIImage? {
        let f = CIFilter(name: "CIQRCodeGenerator")
        f?.setValue(Data(s.utf8), forKey: "inputMessage")
        f?.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f?.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The camera QR reader for "Scan a code" (VisionKit). Calls back with the first code read, or nil when closed.
struct CodeScanner: UIViewControllerRepresentable {
    let done: (String?) -> Void
    static var available: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    func makeUIViewController(context: Context) -> UINavigationController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in done(nil) })
        try? scanner.startScanning()
        return UINavigationController(rootViewController: scanner)
    }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let done: (String?) -> Void
        private var finished = false
        init(done: @escaping (String?) -> Void) { self.done = done }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for case let .barcode(b) in items { if let v = b.payloadStringValue { finished = true; s.stopScanning(); done(v); return } }
        }
    }
}
