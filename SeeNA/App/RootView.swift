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
        .tint(SEENATheme.ink)
        .preferredColorScheme(.light)
        .alert(
            "SeeNA could not continue",
            isPresented: Binding(
                get: { session.appError != nil },
                set: { if !$0 { session.appError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { session.appError = nil } },
            message: { Text(session.appError?.localizedDescription ?? "Please try again.") }
        )
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            session.sensorState = sample
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .eligibility: EligibilityView()
        case .safetyStop: SafetyStopView()
        case .permissions:
            PermissionsView(
                model: PermissionsViewModel(
                    audioRecorder: dependencies.audioRecorder,
                    prompts: dependencies.spokenPrompts
                )
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
        case .rightGaborTest: GaborTestView(eye: .right)
        case .leftEyeInstructions: EyeInstructionsView(eye: .left)
        case .leftEyeTest: EyeTestView(eye: .left)
        case .leftGaborTest: GaborTestView(eye: .left)
        case .processing: ProcessingView()
        case .results: ResultsView()
        case .evidence: EvidenceView()
        }
    }
}

#Preview("Welcome") {
    RootView()
        .environmentObject(AppSession())
        .environmentObject(AppDependencies.preview())
}
