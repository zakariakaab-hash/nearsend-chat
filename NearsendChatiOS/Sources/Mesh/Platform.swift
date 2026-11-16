import AudioToolbox
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
}

/// Local notifications for messages that arrive while the app is not on screen, plus small haptics.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Someone nearby sent SOS: shown even with the app open (see AppDelegate), vibrates, and opens the SOS tab when tapped.
    static func alarm(title: String, body: String) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.userInfo = ["tab": 3]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sos-" + title, content: c, trigger: nil))
    }

    static func messageHaptic() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
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

enum SystemSettings {
    static func open() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
