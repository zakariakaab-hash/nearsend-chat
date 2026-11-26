import LocalAuthentication
import SwiftUI
import VisionKit

struct IdentityView: View {
    @EnvironmentObject var store: ChatStore
    @State private var confirmWipe = false
    @State private var pickAvatar = false

    @State private var showScanner = false
    @State private var showMyCode = false
    @State private var scanResult: String?      // the verified person's name, or "" when the code matched nobody

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
                        NavigationLink { SettingsView() } label: {
                            Card(padding: 14) {
                                HStack(spacing: 12) {
                                    Image(systemName: "gearshape.fill").foregroundStyle(.white)
                                        .frame(width: 34, height: 34).background(Theme.actionBlue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Settings").font(.headline).foregroundStyle(Theme.ink)
                                        Text("Privacy, strangers, app lock, battery, move to another phone")
                                            .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        SkyPill {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Project status", systemImage: "hammer.fill").font(.subheadline.weight(.semibold))
                                Text("Not security audited yet. Open source (GPL-3.0).")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                            }.frame(maxWidth: .infinity, alignment: .leading)
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

/// Every setting in one native grouped list: Connections, Privacy, Messages from strangers, App, Help.
struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var power = PowerMode.shared
    @AppStorage("language") private var language = "system"
    @AppStorage("appLock") private var appLock = false
    @AppStorage("onboarded") private var onboarded = true
    @State private var bluetoothHelp = false
    @State private var shareLog = false
    @State private var mail: URL?
    @State private var confirmWipe = false
    @State private var lockError = false
    @State private var transfer = false

    var body: some View {
        ZStack {
            SkyBackground()
            List {
                Section {
                    Button { bluetoothHelp = true } label: {
                        HStack {
                            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            Text(LocalizedStringKey(bluetoothText)).foregroundStyle(Theme.inkSecondary)
                        }
                    }.foregroundStyle(Theme.ink)
                    toggle("Battery saver", "Black screen, no animations, dimmer screen, and Bluetooth looks for phones less often while you are connected.",
                           icon: "battery.25", $power.saver)
                    toggle("Pass on messages for others", "Helps messages travel further and reach people who are away. Uses some battery.",
                           icon: "arrow.triangle.branch", $store.relayOthers)
                    toggle("Demo mode", "Shows sample people and chats, so you can try the app without another phone. Bluetooth is off while it is on; your own chats come back when you turn it off.",
                           icon: "play.rectangle", Binding(get: { store.simulated }, set: { store.setDemo($0) }))
                } header: { head("Connections") }
                Section {
                    Picker(selection: $store.strangers) {
                        Text("Ask me").tag(ChatStore.StrangerPolicy.ask)
                        Text("Allow").tag(ChatStore.StrangerPolicy.allow)
                        Text("Block").tag(ChatStore.StrangerPolicy.block)
                    } label: { Label("Messages from strangers", systemImage: "person.crop.circle.badge.questionmark") }
                    toggle("Hide me from strangers", "People nearby see \u{201C}\(ChatStore.hiddenName)\u{201D} instead of your name and picture. People you already chat with still see your name.",
                           icon: "eye.slash", $store.hideFromStrangers)
                } header: { head("Strangers") } footer: { foot(LocalizedStringKey(strangerFooter)) }
                Section {
                    Toggle(isOn: Binding(get: { appLock }, set: { setAppLock($0) })) {
                        Label("App lock", systemImage: "faceid")
                    }
                    toggle("Delivery receipts", "Let senders see when their message reached you.", icon: "checkmark.circle", $store.receipts)
                    toggle("Hide text in notifications", "Notifications show who wrote, not what.", icon: "bell.slash", $store.hidePreviews)
                    toggle("Notify me when a friend is nearby", "When someone you chat with comes back in range after 30 minutes away. At most every 2 hours per person. Works while the app is open or running in the background.",
                           icon: "person.2.wave.2", $store.friendNearbyAlerts)
                    toggle("Announcements", "Show announcements from people nearby and notify me. Off: they are hidden, but your phone still passes them on.",
                           icon: "megaphone", $store.showAnnouncements)
                    Picker(selection: $store.autoDeleteDays) {
                        Text("Never").tag(0); Text("1 day").tag(1); Text("\(7) days").tag(7); Text("\(30) days").tag(30)
                    } label: { Label("Delete messages after", systemImage: "timer") }
                } header: { head("Privacy") }
                Section {
                    Picker(selection: $language) {
                        Text("System default").tag("system")
                        ForEach(AppLanguage.all) { Text(verbatim: $0.name).tag($0.code) }
                    } label: { Label("Language", systemImage: "globe") }
                    Button { transfer = true } label: { Label("Move to another phone", systemImage: "iphone.and.arrow.forward") }
                        .foregroundStyle(Theme.ink)
                    ShareLink(item: URL(string: "https://chat.nearsend.app")!) { Label("Share Nearsend Chat", systemImage: "square.and.arrow.up") }
                        .foregroundStyle(Theme.ink)
                } header: { head("App") }
                Section {
                    Button { onboarded = false } label: { Label("Show the intro", systemImage: "play.circle") }.foregroundStyle(Theme.ink)
                    Button { mail = Support.contactURL } label: { Label("Contact us", systemImage: "envelope") }.foregroundStyle(Theme.ink)
                    Button { shareLog = true } label: { Label("Share debug log", systemImage: "doc.text") }.foregroundStyle(Theme.ink)
                } header: { head("Help") } footer: {
                    foot("The debug log has the last 500 events: who connected, packet types, errors. No messages, photos or keys. To report someone, long-press their message or open their contact info and tap Report.")
                }
                Section {
                    Button(role: .destructive) { confirmWipe = true } label: { Label("Erase everything", systemImage: "trash") }
                } footer: {
                    Text(verbatim: "Nearsend Chat \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").foregroundStyle(.white.opacity(0.9))
                }
            }
            .scrollContentBackground(.hidden)
            .tint(Theme.actionBlue)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .opensMail($mail)
        .sheet(isPresented: $bluetoothHelp) { BluetoothGuideSheet().environmentObject(store) }
        .sheet(isPresented: $transfer) { TransferSheet().environmentObject(store) }
        .sheet(isPresented: $shareLog) {
            let head = "Nearsend Chat debug log\n\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n\n"
            ShareSheet(items: [head + (NLog.dump().isEmpty ? "(no events yet)" : NLog.dump())])
        }
        .alert("Set a passcode first", isPresented: $lockError) { Button("OK", role: .cancel) {} } message: {
            Text("App lock uses Face ID, Touch ID or your iPhone passcode. Turn on a passcode in Settings › Face ID & Passcode.")
        }
        .bottomConfirm(isPresented: $confirmWipe, title: "Erase all messages, keys and settings on this phone?",
                       message: "This cannot be undone. You will get a new identity.", action: "Erase everything") { store.wipeAll() }
    }

    private var bluetoothText: String {
        if store.simulated { return "Demo data" }
        switch store.bluetoothState {
        case "ready": return "On"
        case "off": return "Off"
        case "unauthorized": return "Not allowed"
        case "unsupported": return "Unsupported"
        default: return "Starting…"
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

    /// Section titles and notes sit on the blue sky: white, so they stay readable.
    private func head(_ t: LocalizedStringKey) -> some View { Text(t).font(.footnote.weight(.semibold)).foregroundStyle(.white) }
    private func foot(_ t: LocalizedStringKey) -> some View { Text(t).foregroundStyle(.white.opacity(0.9)) }

    private func toggle(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, icon: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            } icon: { Image(systemName: icon) }
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
