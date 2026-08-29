import Foundation
import Combine

enum AppRoute: Hashable {
    case eligibility
    case safetyStop
    case permissions
    case deviceCheck
    case phoneSetup
    case calibration
    case rightEyeInstructions
    case rightEyeTest
    case rightGaborTest
    case leftEyeInstructions
    case leftEyeTest
    case leftGaborTest
    case processing
    case results
    case evidence
}

enum AppError: LocalizedError, Equatable {
    case permissionDenied(String)
    case sensorUnavailable(String)
    case backendUnavailable
    case persistenceFailed
    case invalidState

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let permission): return "SeeNA does not have access to \(permission)."
        case .sensorUnavailable(let sensor): return "\(sensor) is not available on this device."
        case .backendUnavailable: return "The voice service is temporarily unavailable."
        case .persistenceFailed: return "This session could not be saved."
        case .invalidState: return "SeeNA could not safely continue this assessment."
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var activeSession = ScreeningSession()
    @Published var sensorState: DistanceSample?
    @Published var cachedExplanation: ExplanationResponse?
    @Published var capabilityTier: DeviceCapabilityTier?
    @Published var appError: AppError?
    @Published private(set) var didTapStart = false

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let keyIndex = arguments.firstIndex(of: "-SEENA_DEBUG_ROUTE"),
           arguments.indices.contains(keyIndex + 1),
           let route = Self.debugRoute(named: arguments[keyIndex + 1]) {
            didTapStart = true
            path = [route]
        }
#endif
    }

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func beginJourney() {
        guard !didTapStart, path.isEmpty else { return }
        didTapStart = true
        navigate(to: .permissions)
    }

    func replaceFlow(with route: AppRoute) {
        path = [route]
    }

    func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    func startNewSession() {
        activeSession = ScreeningSession()
        sensorState = nil
        appError = nil
        didTapStart = false
        cachedExplanation = nil
        path = []
    }

    var requiresLiveSensors: Bool {
        guard let route = path.last else { return false }
        switch route {
        case .phoneSetup, .calibration, .rightEyeTest, .rightGaborTest, .leftEyeTest, .leftGaborTest:
            return true
        default:
            return false
        }
    }

    var requiresScreeningBrightness: Bool {
        guard let route = path.last else { return false }
        switch route {
        case .calibration, .rightEyeTest, .rightGaborTest, .leftEyeTest, .leftGaborTest:
            return true
        default:
            return false
        }
    }

#if DEBUG
    private static func debugRoute(named value: String) -> AppRoute? {
        switch value.lowercased() {
        case "permissions": return .permissions
        case "phone-setup": return .phoneSetup
        case "calibration": return .calibration
        case "processing": return .processing
        default: return nil
        }
    }
#endif
}
