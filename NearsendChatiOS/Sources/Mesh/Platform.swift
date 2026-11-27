import AudioToolbox
import CoreBluetooth
import CoreLocation
import Foundation
import Security
import UIKit
import UserNotifications

/// Stores the device's private key in the Keychain. Wiping it gives the phone a brand-new identity.
enum KeyStore {
    private static let service = "app.nearsend.chat"
    private static let account = "identity-sk"

    static func loadOrCreate() -> MeshCrypto {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data, let c = try? MeshCrypto(privateKeyData: data) { return c }
        let c = MeshCrypto()
        wipe()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: c.privateKeyData,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(add as CFDictionary, nil)
        return c
    }

    static func wipe() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

    /// For "Move to another phone": the private key goes into the password-encrypted transfer file.
    static func exportKey() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// Restoring a transfer file: this phone takes over the identity it carries.
    static func replace(with key: Data) throws {
        _ = try MeshCrypto(privateKeyData: key)   // refuse anything that is not a valid key
        wipe()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: key,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Local notifications for messages that arrive while the app is not on screen, plus small haptics.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = UNNotificationSound(named: UNNotificationSoundName("nearsend_hop.caf"))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Someone nearby sent SOS: shown even with the app open (see AppDelegate), vibrates, and opens the SOS tab when tapped.
    static func alarm(title: String, body: String) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = UNNotificationSound(named: UNNotificationSoundName("nearsend_sos.caf"))
        c.userInfo = ["tab": 3]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sos-" + title, content: c, trigger: nil))
    }

    /// A new message with the app open: a tap and Nearsend's "hop" sound (quiet when the ring/silent switch is on silent).
    static func messageHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if UIApplication.shared.applicationState == .active, let id = hopSound { AudioServicesPlaySystemSound(id) }
    }
    /// Nearsend's own sounds (Resources): "hop" for messages, a faster, longer version for SOS alarms.
    private static let hopSound: SystemSoundID? = {
        guard let url = Bundle.main.url(forResource: "nearsend_hop", withExtension: "caf") else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr ? id : nil
    }()
    static func peerHaptic() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

/// Location for SOS only. Updates arrive on the main thread.
final class LocationFeed: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocation) -> Void)?
    var onStatus: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    func request() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) { if let l = locations.last { onUpdate?(l) } }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { onStatus?(m.authorizationStatus) }
}

/// Shows iOS's own "Turn on Bluetooth" alert on request. Its Settings button is the only way into Settings › Bluetooth:
/// apps cannot open that page or switch Bluetooth on. The main transport never shows it on its own (it confused people);
/// only the "Turn on Bluetooth" button does, by creating a short-lived manager that asks for it.
enum BluetoothPowerAlert {
    private static var manager: CBCentralManager?
    static func show() {
        manager = CBCentralManager(delegate: nil, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { manager = nil }
    }
}

/// iOS's own "Turn On Location Services" alert, shown on request: asking for a position while Location Services is off
/// makes iOS show it, and its Settings button leads to Settings › Privacy & Security › Location Services.
enum LocationServicesAlert {
    private static var manager: CLLocationManager?
    static func show() {
        let m = CLLocationManager()
        manager = m
        m.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { m.stopUpdatingLocation(); manager = nil }
    }
}

enum SystemSettings {
    static func open() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
