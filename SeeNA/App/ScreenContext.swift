import UIKit

@MainActor
enum ScreenContext {
    static var active: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.screen
            ?? scenes.first?.screen
    }
}
