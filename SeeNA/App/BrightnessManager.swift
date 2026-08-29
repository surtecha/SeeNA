import Foundation
import UIKit

@MainActor
final class BrightnessManager {
    private let defaultsKey = "seena.originalBrightness"
    private let isEnabled: Bool
    private var originalBrightness: CGFloat?

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func applyScreeningBrightness(_ value: CGFloat = 0.80) {
        guard isEnabled else { return }
        if originalBrightness == nil {
            originalBrightness = UIScreen.main.brightness
            UserDefaults.standard.set(Double(UIScreen.main.brightness), forKey: defaultsKey)
        }
        UIScreen.main.brightness = max(0.05, min(1, value))
    }

    func restore() {
        guard isEnabled else { return }
        let stored = originalBrightness.map(Double.init) ?? UserDefaults.standard.object(forKey: defaultsKey) as? Double
        if let stored { UIScreen.main.brightness = CGFloat(stored) }
        originalBrightness = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func restoreIfNeeded() {
        guard isEnabled,
              let stored = UserDefaults.standard.object(forKey: defaultsKey) as? Double else { return }
        UIScreen.main.brightness = CGFloat(stored)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
