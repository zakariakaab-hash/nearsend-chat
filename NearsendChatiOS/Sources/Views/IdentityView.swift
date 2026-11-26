import SwiftUI
import VisionKit

struct IdentityView: View {
    @EnvironmentObject var store: ChatStore
    @State private var confirmWipe = false
    @State private var pickAvatar = false
    @State private var shareLog = false
    @State private var mail: URL?
    @AppStorage("language") private var language = "system"
    @ObservedObject private var power = PowerMode.shared

    @State private var showScanner = false
    @State private var showMyCode = false
    @State private var scanResult: String?      // the verified person's name, or "" when the code matched nobody

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
                                    .font(.system(.title2, design: .rounded, weight: .semibold))
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
                                HStack(spacing: 10) {
                                    if CodeScanner.available {
                                        Button { showScanner = true } label: { Label("Scan a code", systemImage: "qrcode.viewfinder") }
                                            .buttonStyle(.borderedProminent).tint(Theme.actionBlue)
                                    }
                                    Button { showMyCode = true } label: { Label("Show my code", systemImage: "qrcode") }
                                        .buttonStyle(.bordered).tint(Theme.link)
                                }.font(.subheadline.weight(.semibold))
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
                        Card {
                            Toggle(isOn: $power.saver) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Battery saver", systemImage: "battery.25")
                                    Text("Pure black background and no animations. Saves battery on OLED screens. Bluetooth still uses power.")
                                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                                    Text("Also dims the screen while the app is open.")
                                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                                }
                            }.tint(Theme.actionBlue)
                        }
                        Card {
                            Toggle(isOn: Binding(get: { store.simulated }, set: { store.setDemo($0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Demo mode")
                                    Text("Shows sample people and chats, so you can try the app without another phone. Bluetooth is off while it is on; your own chats come back when you turn it off.")
                                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                                }
                            }.tint(Theme.actionBlue)
                        }
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
                                Text("Not security audited yet. Open source (GPL-3.0).")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 20).readableWidth()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .opensMail($mail)
            .sheet(isPresented: $pickAvatar) { AvatarPickerSheet().environmentObject(store) }
            .sheet(isPresented: $showMyCode) { MyCodeSheet(payload: store.myCodePayload, fingerprint: store.myFingerprint) }
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

/// A QR code of our fingerprint, for a friend to scan with "Scan a code".
private struct MyCodeSheet: View {
    let payload: String
    let fingerprint: String
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
            Text(verbatim: fingerprint).font(.system(.callout, design: .monospaced)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Let a friend scan this to verify you. Do it in person.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
