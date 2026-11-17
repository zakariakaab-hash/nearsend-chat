import SwiftUI

/// Follows the iPhone's Low Power Mode, so the app can stop decorative animations and slow its background work.
final class PowerMode: ObservableObject {
    static let shared = PowerMode()
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private init() {
        // `queue: .main` delivers on the main thread, where SwiftUI wants its state changes.
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
