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

    private init() {
        // `queue: .main` delivers on the main thread, where SwiftUI wants its state changes.
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
