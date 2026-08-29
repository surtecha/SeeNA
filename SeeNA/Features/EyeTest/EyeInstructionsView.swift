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
        await listenForReady(eye: eye, session: session, dependencies: dependencies)
    }

    func continueNow(eye: Eye, session: AppSession) {
        session.navigate(to: eye == .right ? .rightEyeTest : .leftEyeTest)
    }

    private func listenForReady(eye: Eye, session: AppSession, dependencies: AppDependencies) async {
        phase = .speaking
        await dependencies.spokenPrompts.speakAndWait(
            "Cover your \(eye.eyeToCover) eye without pressing. Say yes when ready."
        )
        do {
            phase = .listening
            let recording = try await dependencies.audioRecorder.record(maximumDuration: 8)
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            let response = try await dependencies.backend.transcribe(
                audioURL: recording.fileURL,
                mode: .constrainedChoice,
                choiceSetID: "readAloud"
            )
            if response.valid, response.choice == "yes" {
                HapticFeedback.success()
                continueNow(eye: eye, session: session)
            } else {
                phase = .waiting
                await dependencies.spokenPrompts.speakAndWait("Take your time. Say yes when you are ready.")
                hasStarted = false
                await begin(eye: eye, session: session, dependencies: dependencies)
            }
        } catch {
            phase = .waiting
            dependencies.spokenPrompts.speak("I couldn’t hear you. Say yes again, or use the ready button.")
        }
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
    }
}
