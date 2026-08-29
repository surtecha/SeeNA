import Foundation
import Combine

enum AppRoute: Hashable {
    case howItWorks
    case eligibility
    case safetyStop
    case permissions
    case deviceCheck
    case phoneSetup
    case calibration
    case rightEyeInstructions
    case rightEyeTest
    case leftEyeInstructions
    case leftEyeTest
    case accessibilityIntroduction
    case accessibilitySetup
    case accessibilityTest
    case processing
    case results
    case evidence
    case accessibleDemo
    case history
    case deletionConfirmation
}

enum AppError: LocalizedError, Equatable {
    case permissionDenied(String)
    case sensorUnavailable(String)
    case backendUnavailable
    case persistenceFailed
    case invalidState

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let permission): return "SEENA does not have access to \(permission)."
        case .sensorUnavailable(let sensor): return "\(sensor) is not available on this device."
        case .backendUnavailable: return "The voice service is temporarily unavailable."
        case .persistenceFailed: return "This session could not be saved."
        case .invalidState: return "SEENA could not safely continue this assessment."
        }
    }
}

struct EligibilityAnswers: Equatable {
    var wearingDistanceGlasses = false
    var wearingContactLenses = false
    var suddenVisionChange = false
    var severePainOrRecentInjury = false
    var canMoveSafely = true
    var isAdult = true

    var outcome: EligibilityOutcome {
        if suddenVisionChange || severePainOrRecentInjury { return .safetyStop }
        if wearingContactLenses || !canMoveSafely || !isAdult { return .accessibilityOnly }
        return .fullScreening
    }
}

enum EligibilityOutcome: Equatable {
    case fullScreening
    case accessibilityOnly
    case safetyStop
}

@MainActor
final class AppSession: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var activeSession = ScreeningSession()
    @Published var sensorState: DistanceSample?
    @Published var accessibilityProfile: AccessibilityProfile?
    @Published var accessibilityAnswers = AccessibilityAssessmentAnswers()
    @Published var cachedExplanation: ExplanationResponse?
    @Published var cachedAdaptedContent: AdaptedContentResponse?
    @Published var capabilityTier: DeviceCapabilityTier?
    @Published var eligibilityAnswers = EligibilityAnswers()
    @Published var appError: AppError?
    @Published var isAccessibilityOnly = false
    @Published var isRestoringHistory = false

    func navigate(to route: AppRoute) {
        path.append(route)
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
        isAccessibilityOnly = false
        accessibilityAnswers = AccessibilityAssessmentAnswers()
        accessibilityProfile = nil
        cachedExplanation = nil
        cachedAdaptedContent = nil
        path = []
    }

    func applyEligibility() {
        switch eligibilityAnswers.outcome {
        case .safetyStop:
            navigate(to: .safetyStop)
        case .accessibilityOnly:
            isAccessibilityOnly = true
            navigate(to: .permissions)
        case .fullScreening:
            navigate(to: .permissions)
        }
    }
}
