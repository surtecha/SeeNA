import SwiftUI

struct PhoneSetupView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ScreenScaffold(
            title: "Place the phone securely",
            subtitle: "Keep the iPhone upright at eye level with the front camera clear and two metres of safe space in front."
        ) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180)
                .foregroundColor(SEENATheme.teal)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            liveStatus

            Button("Lock phone position") {
                dependencies.sensorCoordinator.lockPhoneReference()
                dependencies.spokenPrompts.speak("Phone position locked. Stand close to the phone for calibration.")
            }
            .buttonStyle(SecondaryActionStyle())

            Button("Continue to calibration") { session.navigate(to: .calibration) }
                .buttonStyle(PrimaryActionStyle())
                .disabled(!canContinue)
        }
        .onAppear { dependencies.sensorCoordinator.start() }
        .onDisappear {
            if session.path.last != .calibration { dependencies.sensorCoordinator.stop() }
        }
        .navigationTitle("Phone setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var liveStatus: some View {
        if let sample = session.sensorState {
            StatusRow(title: "Face", detail: sample.faceCount == 1 ? "One face centred" : "Centre one face in view", state: sample.faceCount == 1 ? .ready : .warning)
            StatusRow(title: "Phone", detail: sample.phoneStable ? "Stable for testing" : "Keep the phone still", state: sample.phoneStable ? .ready : .warning)
            StatusRow(title: "Head position", detail: abs(sample.headYawDegrees) <= 10 && abs(sample.headPitchDegrees) <= 10 ? "Facing the phone" : "Face the phone directly", state: abs(sample.headYawDegrees) <= 10 && abs(sample.headPitchDegrees) <= 10 ? .ready : .warning)
            StatusRow(title: "Lighting", detail: sample.luminance >= 0.12 ? "Usable camera exposure" : "Turn on another light", state: sample.luminance >= 0.12 ? .ready : .warning)
        } else {
            ProgressView("Starting face and motion tracking…")
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private var canContinue: Bool {
        guard let sample = session.sensorState else { return false }
        return sample.faceCount == 1
            && sample.phoneStable
            && abs(sample.headYawDegrees) <= 10
            && abs(sample.headPitchDegrees) <= 10
            && sample.luminance >= 0.12
    }
}
