import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        NavigationStack(path: $session.path) {
            WelcomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tint(SEENATheme.teal)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, session.accessibilityProfile?.swiftUIDynamicTypeSize ?? .large)
        .alert(
            "SEENA could not continue",
            isPresented: Binding(
                get: { session.appError != nil },
                set: { if !$0 { session.appError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { session.appError = nil } },
            message: { Text(session.appError?.localizedDescription ?? "Please try again.") }
        )
        .onChange(of: session.accessibilityProfile) { profile in
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
        case .permissions: PermissionsView()
        case .deviceCheck: DeviceCheckView()
        case .phoneSetup: PhoneSetupView()
        case .calibration: BaselineCalibrationView()
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
