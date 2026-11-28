import LocalAuthentication
import SwiftUI

@main
struct NearsendChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = ChatStore.shared
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("appLock") private var appLock = false
    /// App lock: closed at launch and every time the app goes to the background.
    @State private var locked = UserDefaults.standard.bool(forKey: "appLock")
    /// A transfer file opened from AirDrop or Files (also on a fresh install, before onboarding).
    @State private var openedTransfer: OpenedFile?

    init() {
        let a = UITabBarAppearance()
        a.configureWithTransparentBackground()
        a.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    @ObservedObject private var power = PowerMode.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LanguageRoot {
                if onboarded { RootView() } else { OnboardingView { onboarded = true } }
            }
            .environmentObject(store)
            .tint(Theme.link)
            .preferredColorScheme(power.saver ? .dark : nil)   // battery saver: light text on the black background
            .onAppear { if onboarded { store.startIfNeeded() } }
            .onChange(of: onboarded) { _, v in if v { store.startIfNeeded() } }
            .overlay { if locked && appLock { AppLockView { locked = false } } }
            .onChange(of: scenePhase, initial: true) { _, p in
                power.applyBrightness(active: p == .active)
                if p == .background && appLock { locked = true }
            }
            .onOpenURL { url in if url.pathExtension.lowercased() == "nearsend" { openedTransfer = OpenedFile(url: url) } }
            .sheet(item: $openedTransfer) { f in TransferSheet(openedFile: f.url).environmentObject(store) }
            .onChange(of: power.saver) { _, _ in power.applyBrightness(active: scenePhase == .active) }
        }
    }
}

struct OpenedFile: Identifiable { let url: URL; var id: URL { url } }

struct RootView: View {
    @EnvironmentObject var store: ChatStore
    /// The tab bar takes images, not views: draw the avatar once per change of picture or name.
    private var youIcon: UIImage? {
        guard store.myAvatar != nil else { return nil }
        let r = ImageRenderer(content: Avatar(name: store.nickname, size: 28, avatar: store.myAvatar))
        r.scale = 3
        return r.uiImage?.withRenderingMode(.alwaysOriginal)   // keep its colours: the tab bar tints template images
    }
    @AppStorage("tab") private var tab = 0
    /// Filled dark icons for the other tabs; the open tab shows its icon as an outline, in the accent colour.
    private func tabLabel(_ title: LocalizedStringKey, _ icon: String, _ index: Int) -> some View {
        Label { Text(title) } icon: {
            if tab == index, let outline = Self.outline(icon) { Image(uiImage: outline) }
            else { Image(systemName: icon).environment(\.symbolVariants, .fill) }
        }
    }
    /// iOS 26 fills the selected tab's SF Symbol on its own. Drawing the outline into a plain template bitmap
    /// keeps it an outline (still tinted with the accent colour by the tab bar).
    private static func outline(_ name: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.black, renderingMode: .alwaysOriginal) else { return nil }
        let f = UIGraphicsImageRendererFormat(); f.scale = 3
        return UIGraphicsImageRenderer(size: symbol.size, format: f).image { _ in symbol.draw(at: .zero) }
            .withRenderingMode(.alwaysTemplate)
    }
    var body: some View {
        TabView(selection: $tab) {
            NearbyView().tabItem { tabLabel("Nearby", "dot.radiowaves.left.and.right", 0) }.tag(0)
            ChatsView().tabItem { tabLabel("Chats", "bubble.left.and.bubble.right", 1) }
                .badge(store.unreadTotal).tag(1)
            SosView().tabItem { tabLabel("SOS", "exclamationmark.triangle", 3) }
                .badge(store.activeAlerts).tag(3)
            IdentityView().tabItem {
                // Your own picture as the tab icon (falls back to the person symbol until one exists).
                if let img = youIcon { Label { Text("You") } icon: { Image(uiImage: img).renderingMode(.original) } }
                else { tabLabel("You", "person.crop.circle", 2) }
            }.tag(2)
        }
    }
}

struct AppLanguage: Identifiable {
    let code: String, name: String
    var id: String { code }
    /// Each language is listed in its own language so people can find it whatever the app is currently showing.
    static let all: [AppLanguage] = [
        .init(code: "en", name: "English"), .init(code: "sv", name: "Svenska"), .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"), .init(code: "de", name: "Deutsch"), .init(code: "pt", name: "Português"),
        .init(code: "it", name: "Italiano"), .init(code: "ar", name: "العربية"), .init(code: "tr", name: "Türkçe"),
        .init(code: "ru", name: "Русский"), .init(code: "zh-Hans", name: "简体中文"), .init(code: "ja", name: "日本語"),
    ]
}

/// Follows the phone's language by default; the "language" setting overrides it (and flips layout for right-to-left languages).
struct LanguageRoot<Content: View>: View {
    @AppStorage("language") private var language = "system"
    @Environment(\.layoutDirection) private var systemDirection
    @ViewBuilder var content: Content

    var body: some View {
        let explicit = language != "system"
        content
            .environment(\.locale, explicit ? Locale(identifier: language) : Locale.autoupdatingCurrent)
            .environment(\.layoutDirection, explicit
                ? (Locale.Language(identifier: language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                : systemDirection)
    }
}

/// Covers the whole app until Face ID, Touch ID or the passcode says it's you. Asks once on its own when shown.
struct AppLockView: View {
    let unlocked: () -> Void
    @State private var asking = false
    @State private var fromBackground = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 96, height: 96).background(Theme.actionBlue, in: Circle())
                Text("Nearsend Chat is locked").font(.title2.weight(.bold)).foregroundStyle(.white)
                Button { ask() } label: {
                    Label("Unlock", systemImage: "faceid").font(.headline).padding(.horizontal, 28).frame(minHeight: 50)
                        .foregroundStyle(Theme.actionBlue).background(.white, in: Capsule())
                }
            }
        }
        // Ask on its own only when shown in front, or when coming back from the background; after a cancel the
        // person taps Unlock (Face ID's own sheet makes the app inactive, which must not start another prompt).
        .onAppear { if scenePhase == .active { ask() } else { fromBackground = true } }
        .onChange(of: scenePhase) { _, p in
            if p == .background { fromBackground = true }
            if p == .active && fromBackground { fromBackground = false; ask() }
        }
    }

    private func ask() {
        guard !asking else { return }
        let ctx = LAContext()
        var err: NSError?
        // No passcode on the phone any more: the lock cannot be checked, so it does not keep the person out.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked(); return }
        asking = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localized("Unlock Nearsend Chat")) { ok, _ in
            Task { @MainActor in asking = false; if ok { unlocked() } }
        }
    }
}
