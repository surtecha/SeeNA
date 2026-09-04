import Foundation
import Combine
import UIKit

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
    case history
}

enum SessionPersistenceState: Equatable {
    case unknown
    case saved
    case volatile
}

enum ScreeningResponseMode: Equatable {
    case voicePreferred
    case operatorOnly
}

enum SafetyStopReason: String, CaseIterable, Identifiable {
    case suddenVisionChange
    case severeEyePain
    case seriousEyeInjury
    case contactLenses
    case under18
    case unsafeMovement
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suddenVisionChange: return "Sudden vision change or loss"
        case .severeEyePain: return "Severe eye pain"
        case .seriousEyeInjury: return "Serious injury, chemical, or object in the eye"
        case .contactLenses: return "Contact lenses are still in"
        case .under18: return "Participant is under 18"
        case .unsafeMovement: return "Cannot move safely for the task"
        case .other: return "Another safety exclusion applies"
        }
    }

    var urgentGuidance: String {
        switch self {
        case .suddenVisionChange:
            return "Stop. Sudden vision change or loss needs immediate medical help. Go to the nearest emergency department. Call 000 if it is an emergency. You can also call Healthdirect on 1800 022 222."
        case .severeEyePain, .seriousEyeInjury:
            return "Stop. Seek a doctor as soon as possible or go to the nearest emergency department. Call 000 only if it is an emergency. You can also call Healthdirect on 1800 022 222."
        case .contactLenses:
            return "Stop this screening. Remove contact lenses and arrange an appropriate eye examination before considering another screening."
        case .under18:
            return "Stop this screening. SeeNA is for adults aged 18 or older."
        case .unsafeMovement:
            return "Stop this screening. Do not move farther from the phone if you cannot do so safely."
        case .other:
            return "Stop this screening. Arrange appropriate professional care before trying again."
        }
    }
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
    @Published var persistenceState: SessionPersistenceState = .unknown
    @Published var responseMode: ScreeningResponseMode = .voicePreferred
    @Published var safetyStopReason: SafetyStopReason?
    private var sceneLifecycle = SceneLifecycleCoordinator()

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-SEENA_USE_MOCK_SENSORS"),
           arguments.contains(SimulatorVoiceAutomation.launchArgument) {
            didTapStart = true
            path = [.deviceCheck]
            return
        }
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
        announce(route)
    }

    func beginJourney() {
        guard !didTapStart, path.isEmpty else { return }
        didTapStart = true
        navigate(to: .eligibility)
    }

    func replaceFlow(with route: AppRoute) {
        path = [route]
        announce(route)
    }

    func goBack() {
        if !path.isEmpty { path.removeLast() }
        if let route = path.last { announce(route) }
    }

    private func announce(_ route: AppRoute) {
        // These destinations immediately own the spoken-guidance channel.
        // Posting an independent VoiceOver screen announcement at the same
        // time creates two competing voices, so let their route-aware prompt
        // provide the audible context instead. Passive destinations retain a
        // concise screen-change announcement.
        switch route {
        case .eligibility, .safetyStop, .permissions, .deviceCheck,
             .phoneSetup, .calibration, .rightEyeInstructions,
             .rightEyeTest, .rightGaborTest, .leftEyeInstructions,
             .leftEyeTest, .leftGaborTest, .results:
            return
        case .processing, .evidence, .history:
            break
        }

        let label: String
        switch route {
        case .processing: label = "Saving screening"
        case .evidence: label = "Answer audit"
        case .history: label = "Previous sessions"
        default: return
        }
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .screenChanged, argument: label)
        }
    }

    func startNewSession() {
        activeSession = ScreeningSession()
        sensorState = nil
        appError = nil
        didTapStart = false
        cachedExplanation = nil
        persistenceState = .unknown
        responseMode = .voicePreferred
        safetyStopReason = nil
        path = []
    }

    func abandonJourney() {
        activeSession = ScreeningSession()
        sensorState = nil
        cachedExplanation = nil
        capabilityTier = nil
        appError = nil
        persistenceState = .unknown
        responseMode = .voicePreferred
        safetyStopReason = nil
        didTapStart = false
    }

    /// Marks the first inactive/background transition in a suspension cycle.
    /// Returning `false` makes repeated `.inactive` -> `.background` delivery
    /// idempotent, so camera and audio teardown cannot race each other twice.
    @discardableResult
    func beginSceneSuspension() -> Bool {
        guard sceneLifecycle.beginSuspension() else { return false }
        sensorState = nil
        return true
    }

    /// Consumes the suspension exactly once and calculates the resources that
    /// the *current* route still needs. This avoids restoring a stale capture
    /// state if navigation changed while the app was inactive.
    func consumeSceneResumePlan() -> SceneResumePlan? {
        sceneLifecycle.consumeResumePlan(
            requiresLiveSensors: requiresLiveSensors,
            requiresScreeningBrightness: requiresScreeningBrightness
        )
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
