import UIKit
import UserNotifications

/// iOS relaunches the app in the background, with no screen, when Bluetooth activity happens after the system had
/// terminated it (state restoration). The mesh must therefore start here and not only when the first screen appears.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "onboarded") {      // Bluetooth permission has been asked for
            MainActor.assumeIsolated { ChatStore.shared.startIfNeeded() }
        }
        return true
    }

    /// Message notifications are only posted while the app is in the background; SOS alarms are posted always and must show.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tapping an SOS alarm opens the SOS tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let tab = response.notification.request.content.userInfo["tab"] as? Int { UserDefaults.standard.set(tab, forKey: "tab") }
    }
}
