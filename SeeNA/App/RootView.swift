import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    var body: some View {
        NavigationStack(path: $session.path) {
            WelcomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tint(SEENATheme.ink)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, session.accessibilityProfile?.swiftUIDynamicTypeSize ?? systemDynamicTypeSize)
        .alert(
            "SeeNA could not continue",
            isPresented: Binding(
                get: { session.appError != nil },
                set: { if !$0 { session.appError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { session.appError = nil } },
            message: { Text(session.appError?.localizedDescription ?? "Please try again.") }
        )
        .onChange(of: session.accessibilityProfile) { _, profile in
            session.activeSession.accessibilityProfile = profile
        }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            session.sensorState = sample
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .howItWorks: HowItWorksView()
        case .eligibility: EligibilityView()
        case .safetyStop: SafetyStopView()
        case .permissions:
            PermissionsView(
                model: PermissionsViewModel(audioRecorder: dependencies.audioRecorder)
            )
        case .deviceCheck: DeviceCheckView()
        case .phoneSetup:
            PhoneSetupView(
                model: PhoneSetupViewModel(
                    sensors: dependencies.sensorCoordinator,
                    prompts: dependencies.spokenPrompts
                )
            )
        case .calibration:
            BaselineCalibrationView(
                model: CalibrationViewModel(
                    sensors: dependencies.sensorCoordinator,
                    prompts: dependencies.spokenPrompts,
                    brightness: dependencies.brightness
                )
            )
        case .rightEyeInstructions: EyeInstructionsView(eye: .right)
        case .rightEyeTest: EyeTestView(eye: .right)
        case .leftEyeInstructions: EyeInstructionsView(eye: .left)
        case .leftEyeTest: EyeTestView(eye: .left)
        case .accessibilityIntroduction: AccessibilityIntroductionView()
        case .accessibilitySetup: AccessibilitySetupView()
        case .accessibilityTest: AccessibilityAssessmentView()
        case .processing: ProcessingView()
        case .results: ResultsView()
        case .evidence: EvidenceView()
        case .accessibleDemo: AccessibleDemoView()
        case .history: HistoryView()
        case .deletionConfirmation: DeletionView()
        }
    }
}

private extension AccessibilityProfile {
    var swiftUIDynamicTypeSize: DynamicTypeSize {
        switch recommendedDynamicType {
        case .large: return .large
        case .extraLarge: return .xLarge
        case .extraExtraLarge: return .xxLarge
        case .extraExtraExtraLarge: return .xxxLarge
        case .accessibility1: return .accessibility1
        case .accessibility2: return .accessibility2
        case .accessibility3: return .accessibility3
        }
    }
}

#Preview("Welcome") {
    RootView()
        .environmentObject(AppSession())
        .environmentObject(AppDependencies.preview())
}
