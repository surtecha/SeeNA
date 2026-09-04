import Observation
import SwiftUI

@MainActor
@Observable
private final class EyeReadyViewModel {
    enum Phase { case speaking, listening, waiting }
    private(set) var phase: Phase = .speaking
    private var hasStarted = false

    func begin(eye: Eye, session: AppSession, dependencies: AppDependencies) async {
        guard !hasStarted else { return }
        hasStarted = true
        defer { hasStarted = false }
        await listenForReady(eye: eye, session: session, dependencies: dependencies)
    }

    func continueNow(eye: Eye, session: AppSession) {
        session.navigate(to: eye == .right ? .rightEyeTest : .leftEyeTest)
    }

    private func listenForReady(eye: Eye, session: AppSession, dependencies: AppDependencies) async {
        let instructionRoute: AppRoute = eye == .right ? .rightEyeInstructions : .leftEyeInstructions
#if DEBUG
        if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
            phase = .waiting
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  session.path.last == instructionRoute else { return }
            continueNow(eye: eye, session: session)
            return
        }
#endif
        var nextPrompt = "Cover your \(eye.eyeToCover) eye without pressing. Say yes when ready."

        while !Task.isCancelled, session.path.last == instructionRoute {
            phase = .speaking
            _ = await dependencies.spokenPrompts.speakForTransition(nextPrompt)

            guard !Task.isCancelled, session.path.last == instructionRoute else { return }
            guard session.responseMode == .voicePreferred, dependencies.network.isConnected else {
                phase = .waiting
                return
            }

            do {
                phase = .listening
                let recording = try await dependencies.audioRecorder.record(maximumDuration: 8)
                defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }

                if recording.adequateLevel {
                    let response = try await dependencies.backend.transcribe(
                        audioURL: recording.fileURL,
                        mode: .constrainedChoice,
                        choiceSetID: "readAloud"
                    )
                    guard !Task.isCancelled, session.path.last == instructionRoute else { return }
                    if response.valid, response.choice == "yes" {
                        HapticFeedback.success()
                        continueNow(eye: eye, session: session)
                        return
                    }
                }

                phase = .waiting
                nextPrompt = "I didn’t catch that. Take your time, then say yes when ready."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, session.path.last == instructionRoute else { return }
                phase = .waiting
                nextPrompt = "I couldn’t hear you. Take your time, then say yes again."
            }
        }
    }

    func cancel(dependencies: AppDependencies) {
        hasStarted = false
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
    }
}

struct EyeInstructionsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = EyeReadyViewModel()
    let eye: Eye

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: eye == .right ? "eye.circle.fill" : "eye.circle")
                .font(.system(size: 92, weight: .light))
                .accessibilityHidden(true)
            Text("\(eye.displayName) eye")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Cover your \(eye.eyeToCover) eye")
                .font(.title3.weight(.semibold))
            VoiceStatusPill(isListening: model.phase == .listening)
            Text("Say “yes” when ready")
                .font(.body)
                .foregroundStyle(SEENATheme.secondaryInk)
            Spacer()
            Button("I’m ready") { model.continueNow(eye: eye, session: session) }
                .buttonStyle(PrimaryActionStyle())
        }
        .padding(24)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { await model.begin(eye: eye, session: session, dependencies: dependencies) }
        .onDisappear { model.cancel(dependencies: dependencies) }
    }
}
