import SwiftUI

/// Battery use: the iPhone's Low Power Mode and the app's own Battery saver (You tab).
/// `lowPower` stops decorative animations; `saver` also switches to a pure black, flat look that costs least on OLED screens.
final class PowerMode: ObservableObject {
    static let shared = PowerMode()
    @Published private(set) var systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var saver = UserDefaults.standard.bool(forKey: "saver") {
        didSet { UserDefaults.standard.set(saver, forKey: "saver") }
    }
    var lowPower: Bool { systemLowPower || saver }

    /// Battery at 20 % or less and not charging: Bluetooth saves battery on its own, like with Battery saver.
    @MainActor static var batteryLow: Bool {
        let d = UIDevice.current
        if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
        return d.batteryLevel >= 0 && d.batteryLevel <= 0.2 && d.batteryState == .unplugged
    }
    @MainActor static var batteryPercent: Int { Int((UIDevice.current.batteryLevel * 100).rounded()) }

    /// Battery saver also dims the screen while the app is in front. The person's own brightness is put back
    /// when the app goes to the background or the saver is turned off.
    private var savedBrightness: CGFloat?
    static let dimLevel: CGFloat = 0.3
    func applyBrightness(active: Bool) {
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen else { return }
        if saver && active {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            if screen.brightness > Self.dimLevel { screen.brightness = Self.dimLevel }
        } else if let b = savedBrightness {
            savedBrightness = nil
            screen.brightness = b
        }
    }

    private init() {
        // `queue: .main` delivers on the main thread, where SwiftUI wants its state changes.
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
