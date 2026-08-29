import SwiftUI

struct BaselineCalibrationView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var didCapture = false

    var body: some View {
        ScreenScaffold(
            title: "Set the 40 cm baseline",
            subtitle: "Stand close, look at the centre, and move slowly until the circle turns green. Keep your head facing the phone."
        ) {
            ZStack {
                Circle()
                    .stroke(didCapture ? SEENATheme.teal : readinessColor, lineWidth: 16)
                    .frame(width: 210, height: 210)
                VStack(spacing: 8) {
                    Text(distanceText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(didCapture ? "Baseline saved" : readinessText)
                        .font(.headline)
                }
                .foregroundColor(SEENATheme.ink)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            StatusRow(
                title: "Phone",
                detail: sample?.phoneStable == true ? "Stationary" : "Keep the phone completely still",
                state: sample?.phoneStable == true ? .ready : .warning
            )
            StatusRow(
                title: "Face and head",
                detail: headReady ? "One face, looking forward" : "Centre your face and look forward",
                state: headReady ? .ready : .warning
            )

            Button(didCapture ? "Baseline captured" : "Capture baseline") {
                capture()
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(!isReady || didCapture)

            if didCapture {
                Button("Continue to right eye") { session.navigate(to: .rightEyeInstructions) }
                    .buttonStyle(SecondaryActionStyle())
            }
        }
        .onAppear {
            dependencies.brightness.applyScreeningBrightness()
            dependencies.sensorCoordinator.start()
            dependencies.spokenPrompts.speak("Stand close to the phone and look at the centre. Move slowly until the circle turns green.")
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sample: DistanceSample? { session.sensorState }

    private var measuredDistance: Double? {
        sample?.correctedDistanceMetres ?? sample?.fusedDistanceMetres ?? sample?.rawARDistanceMetres
    }

    private var distanceText: String {
        measuredDistance.map { String(format: "%.2f m", $0) } ?? "Finding you…"
    }

    private var headReady: Bool {
        guard let sample else { return false }
        return sample.faceCount == 1 && abs(sample.headYawDegrees) <= 10 && abs(sample.headPitchDegrees) <= 10
    }

    private var isReady: Bool {
        guard let sample, let measuredDistance else { return false }
        return (0.37...0.43).contains(measuredDistance)
            && sample.phoneStable
            && headReady
            && sample.luminance >= 0.12
    }

    private var readinessColor: Color { isReady ? SEENATheme.teal : SEENATheme.warning }
    private var readinessText: String { isReady ? "Hold still" : "Move to 40 cm" }

    private func capture() {
        guard isReady, dependencies.sensorCoordinator.captureBaseline() else {
            session.appError = .invalidState
            return
        }
        session.activeSession.baselineDistanceMetres = measuredDistance
        didCapture = true
        dependencies.spokenPrompts.speak("Baseline saved. Cover your left eye next.")
    }
}
