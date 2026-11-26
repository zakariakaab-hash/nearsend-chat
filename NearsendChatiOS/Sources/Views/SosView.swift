import CoreLocation
import SwiftUI

let sosRed = Color(hex: 0xD7263D)
private let sosRedDeep = Color(hex: 0xA3182B)

/// Text built in code (SMS body, compass points) in the app's chosen language, like `Text` does via the environment.
func localized(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "language") ?? "system"
    let bundle = lang == "system" ? Bundle.main
        : Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Hold-to-send SOS, our own position, and alarms heard from others.
struct SosView: View {
    @State private var servicesOff = false   // Location Services switched off for the whole phone
    @State private var locationAlert = false  // permission was refused before: explain and offer Settings

    @EnvironmentObject var store: ChatStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        sosContent
            // CLLocationManager.locationServicesEnabled() must not run on the main thread.
            .task(id: store.locationStatus) { servicesOff = await Task.detached { !CLLocationManager.locationServicesEnabled() }.value }
            // Turning "Attach my location" on asks for permission right away, so the position is ready before an emergency.
            .onChange(of: store.shareLocation) { _, on in if on { ensureLocation() } }
            .alert("Location is off for Nearsend Chat", isPresented: $locationAlert) {
                Button("Open Settings") { SystemSettings.open() }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("To attach your position to an SOS, allow location for Nearsend Chat in Settings. Until then the alarm is sent without it.")
            }
    }

    /// Location for the SOS: ask iOS the first time; if it was refused, explain and offer Settings. Phone-wide Location
    /// Services off and Screen Time blocks are explained under the switch.
    private func ensureLocation() {
        guard !store.hasLocationPermission, !servicesOff, store.locationStatus != .restricted else { return }
        if store.locationStatus == .notDetermined { store.requestLocation() } else { locationAlert = true }
    }

    private var sosContent: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 16) {
                    PageTitle(text: "SOS").padding(.top, 8)
                    SkyPill { Text("The alarm reaches phones nearby that have Nearsend Chat, also through other phones. It does not call emergency services.").font(.subheadline) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Someone's alarm is on: show it first, above our own button, so it is never below the fold.
                    if store.activeAlerts > 0 { alarms }
                    SosButton(active: store.mySos != nil) {
                        store.startSos()   // never wait: the alarm goes out now, the position joins the repeats once allowed
                        if store.shareLocation { ensureLocation() }
                    }.padding(.vertical, 8)
                    if store.mySos != nil {
                        Text("SOS is on · sent again every 15 s").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(sosRed, in: Capsule())
                        PrimaryButton(title: "I'm safe · stop alarm") { store.stopSos() }
                    }
                    TextField("Add a note (optional)", text: $store.sosNote)
                        .foregroundStyle(Theme.ink).padding(.horizontal, 16).padding(.vertical, 14).glass(radius: Theme.rField)
                    locationCard
                    if store.activeAlerts == 0 { alarms }
                    beyond
                }.padding(.horizontal, 20).padding(.bottom, 24).readableWidth()
            }
        }
        .onAppear { store.useLocation(true) }
        .onDisappear { store.useLocation(false) }
    }

    private var locationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $store.shareLocation) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(sosRed)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Attach my location").font(.headline)
                            Text("People who get the alarm see how far away you are and in which direction.")
                                .font(.footnote).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }.tint(sosRed)
                if store.shareLocation {
                    if !store.hasLocationPermission && (servicesOff || store.locationStatus == .restricted) {
                        // Location Services off for the whole phone (or blocked by Screen Time): the app's own row in
                        // Settings is greyed out, so say where to switch it on.
                        Text(servicesOff ? "Location Services is off on this iPhone. Turn it on in Settings › Privacy & Security › Location Services."
                                         : "Location is blocked by Screen Time. Allow it in Settings › Screen Time › Content & Privacy Restrictions › Location Services.")
                            .font(.footnote).foregroundStyle(sosRed)
                    } else if !store.hasLocationPermission {
                        HStack {
                            Text("Location permission needed.").font(.footnote).foregroundStyle(sosRed)
                            Spacer()
                            Button("Allow") {
                                if store.locationStatus == .notDetermined { store.requestLocation() } else { SystemSettings.open() }
                            }.font(.footnote.weight(.semibold))
                        }
                    } else if let l = store.myLocation {
                        Label("Location allowed · position found ±\(Int(l.horizontalAccuracy.rounded())) m", systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(Theme.secure)
                    } else {
                        Label("Location allowed · looking for your position…", systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(Theme.secure)
                    }
                }
                Text("Public · not encrypted. Every phone nearby can read it.").font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    @ViewBuilder private var alarms: some View {
        if store.alerts.isEmpty {
            Card {
                Label("All quiet nearby.", systemImage: "checkmark.shield").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Alarms nearby").textCase(.uppercase).font(Theme.display(24)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            ForEach(store.alerts) { a in AlertCard(alert: a, me: store.myLocation) }
        }
    }

    private var beyond: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Beyond Nearsend").font(.headline)
                Text("Calls and texts need cell signal. Texts are not encrypted.").font(.footnote).foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 10) {
                    SosAction(title: "Call \(EmergencyNumber.local)", icon: "phone.fill") {
                        if let u = URL(string: "tel:" + EmergencyNumber.local) { openURL(u) }
                    }
                    SosAction(title: "Text my position", icon: "message.fill") { if let u = smsURL { openURL(u) } }
                }
            }
        }
    }

    private var smsURL: URL? {
        var body = localized("SOS: I need help.")
        if let l = store.myLocation {
            let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), l.coordinate.latitude)
            let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), l.coordinate.longitude)
            body += "\n" + localized("My position:") + " https://www.openstreetmap.org/?mlat=\(lat)&mlon=\(lon)#map=17/\(lat)/\(lon)"
        }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return body.addingPercentEncoding(withAllowedCharacters: safe).flatMap { URL(string: "sms:&body=" + $0) }   // iOS form: no recipient
    }
}

/// Press and hold for 2 seconds; a ring fills while holding. Letting go early cancels.
private struct SosButton: View {
    let active: Bool
    let onTrigger: () -> Void
    @State private var progress: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 10)
            Circle().trim(from: 0, to: active ? 1 : progress).stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().fill(LinearGradient(colors: [sosRed, sosRedDeep], startPoint: .top, endPoint: .bottom)).padding(14)
                .scaleEffect(active && pulse ? 1.04 : 1)
            VStack(spacing: 2) {
                Text(verbatim: "SOS").font(Theme.display(56)).foregroundStyle(.white)
                if !active { Text("hold").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.white.opacity(0.85)) }
            }
        }
        .frame(width: 210, height: 210)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 2, perform: {
            guard !active else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onTrigger()
            progress = 0
        }, onPressingChanged: { pressing in
            guard !active else { return }
            if pressing { withAnimation(.linear(duration: 2)) { progress = 1 } }
            else { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
        })
        .onChange(of: active) { _, on in
            progress = 0
            if on { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } } else { pulse = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "SOS"))
        .accessibilityHint(Text("Hold for 2 seconds to send an SOS alarm"))
        .accessibilityAction { if !active { onTrigger() } }
    }
}

private struct AlertCard: View {
    let alert: SosAlert
    let me: CLLocation?
    @Environment(\.openURL) private var openURL

    /// Apple Maps at the alarm's position, when it came with one.
    private var mapURL: URL? {
        guard let lat = alert.lat, let lon = alert.lon else { return nil }
        return URL(string: String(format: "maps://?ll=%.5f,%.5f&q=SOS", locale: Locale(identifier: "en_US_POSIX"), lat, lon))
    }

    var body: some View {
        // The whole card opens the map (not only the small icon), when the alarm has a position.
        Button { if let mapURL { openURL(mapURL) } } label: { card }
            .buttonStyle(.plain)
            .disabled(mapURL == nil)
            .accessibilityHint(mapURL == nil ? Text("") : Text("Open map"))
    }

    private var card: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2)
                    .foregroundStyle(alert.active ? sosRed : Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    (Text(verbatim: alert.name + " ").bold() + Text("needs help")).font(.headline)
                    if let n = alert.note, !n.isEmpty { Text(verbatim: n).font(.subheadline) }
                    HStack(spacing: 4) {
                        if let d = distance { Text(verbatim: d) }
                        if alert.hops > 1 { Text("· \(alert.hops) hops") }
                        Text(verbatim: "·")
                        if alert.active { Text(alert.date, style: .time) } else { Text("Ended") }
                    }.font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if mapURL != nil {
                    Image(systemName: "map.fill").font(.title3).foregroundStyle(Theme.link).accessibilityHidden(true)
                }
            }
        }
        .opacity(alert.active ? 1 : 0.7)
    }

    /// "350 m · NE" from our position to theirs.
    private var distance: String? {
        guard let me, let lat = alert.lat, let lon = alert.lon else { return nil }
        let there = CLLocation(latitude: lat, longitude: lon)
        let d = me.distance(from: there)
        let dist = d < 1000 ? "\(Int(d.rounded())) m" : String(format: "%.1f km", d / 1000)
        let p1 = me.coordinate.latitude * .pi / 180, p2 = lat * .pi / 180, dl = (lon - me.coordinate.longitude) * .pi / 180
        let bearing = (atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let points = localized("N,NE,E,SE,S,SW,W,NW").split(separator: ",").map(String.init)
        guard points.count == 8 else { return dist }
        return dist + " · " + points[Int((bearing + 22.5) / 45) % 8]
    }
}

private struct SosAction: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                .frame(maxWidth: .infinity).padding(.vertical, 12).glass(radius: Theme.rButton)
        }
    }
}

/// The emergency number for the phone's region (Settings > General > Language & Region), ambulance first where
/// police and ambulance differ. 112 everywhere else: it is the GSM emergency number and most networks route it.
enum EmergencyNumber {
    static var local: String { number(for: Locale.current.region?.identifier) }
    static func number(for region: String?) -> String {
        guard let r = region?.uppercased() else { return "112" }
        if let n = table[r] { return n }
        return "112"
    }
    private static let table: [String: String] = {
        var t: [String: String] = [:]
        for r in ["US", "CA", "MX", "PR", "PA", "CR", "SV", "DO", "UY", "PH", "SA", "JO"] { t[r] = "911" }
        for r in ["GB", "HK", "MO", "MY", "BD", "AE", "QA", "BH", "SG", "GH"] { t[r] = "999" }
        for r in ["JP", "KR", "TW"] { t[r] = "119" }
        t["AU"] = "000"; t["NZ"] = "111"; t["CN"] = "120"; t["BR"] = "192"; t["AR"] = "911"
        t["TH"] = "1669"; t["VN"] = "115"; t["EG"] = "123"; t["MA"] = "15"; t["CO"] = "123"
        t["CL"] = "131"; t["IR"] = "115"; t["PK"] = "1122"
        return t
    }()
}
