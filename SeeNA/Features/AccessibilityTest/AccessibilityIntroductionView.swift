import SwiftUI

struct AccessibilityIntroductionView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ScreenScaffold(
            title: "Make digital information easier to use",
            subtitle: "This is a separate near-readability assessment. It is not calculated from eye power and remains available even when numeric screening is unavailable."
        ) {
            StatusRow(title: "Read unfamiliar text", detail: "SEENA measures transcript word accuracy at several text sizes.", state: .ready)
            StatusRow(title: "Compare layouts", detail: "Choose contrast, control size, spoken assistance and simpler structure.", state: .ready)
            StatusRow(title: "Apply your profile", detail: "SEENA changes its own sample service interface immediately.", state: .ready)

            Button("Set up the near assessment") { session.navigate(to: .accessibilitySetup) }
                .buttonStyle(PrimaryActionStyle())

            if session.activeSession.rightEyeResult != nil || session.activeSession.leftEyeResult != nil {
                Button("Skip accessibility assessment") { session.navigate(to: .processing) }
                    .buttonStyle(SecondaryActionStyle())
            }
        }
        .onAppear {
            dependencies.spokenPrompts.speak("Next is a separate reading and accessibility assessment at about forty centimetres.")
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccessibilitySetupView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var manualDistanceConfirmed = false

    var body: some View {
        ScreenScaffold(
            title: "Move to a comfortable near distance",
            subtitle: "Hold or view the phone at approximately 40 cm in good light. Keep your usual near-reading correction if you normally use one."
        ) {
            Text(distanceText)
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .foregroundColor(distanceReady ? SEENATheme.teal : SEENATheme.ink)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Current distance \(distanceText)")

            if session.sensorState == nil {
                Toggle("I am positioned about 40 cm away", isOn: $manualDistanceConfirmed)
                    .font(.headline)
                    .padding(18)
                    .background(SEENATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Begin readability assessment") { session.navigate(to: .accessibilityTest) }
                .buttonStyle(PrimaryActionStyle())
                .disabled(!distanceReady && !manualDistanceConfirmed)
        }
        .onAppear {
            dependencies.sensorCoordinator.start()
            dependencies.spokenPrompts.speak("Move to about forty centimetres from the phone, then begin the readability assessment.")
        }
        .navigationTitle("Near setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var distance: Double? {
        session.sensorState?.correctedDistanceMetres ?? session.sensorState?.fusedDistanceMetres
    }
    private var distanceReady: Bool { distance.map { (0.35...0.50).contains($0) } ?? false }
    private var distanceText: String { distance.map { String(format: "%.2f m", $0) } ?? "40 cm" }
}
