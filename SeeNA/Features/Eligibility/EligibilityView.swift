import Observation
import SwiftUI

@MainActor
@Observable
private final class VoiceSafetyViewModel {
    enum Phase: Equatable {
        case speaking
        case listening
        case checking
        case retry
        case finished
    }

    private(set) var phase: Phase = .speaking
    private var hasBegun = false

    var status: String {
        switch phase {
        case .speaking: return "Listen"
        case .listening: return "Say yes or no"
        case .checking: return "Checking"
        case .retry: return "I didn’t catch that"
        case .finished: return "Ready"
        }
    }

    func begin(session: AppSession, dependencies: AppDependencies) async {
        guard !hasBegun else { return }
        hasBegun = true
        await ask(session: session, dependencies: dependencies)
    }

    func ask(session: AppSession, dependencies: AppDependencies) async {
        phase = .speaking
        await dependencies.spokenPrompts.speakAndWait(
            "Remove glasses. Say no if you wear contacts, have sudden pain or vision change, are under eighteen, or cannot walk safely. Otherwise, say yes."
        )

        do {
            phase = .listening
            let recording = try await dependencies.audioRecorder.record(maximumDuration: 7)
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            guard recording.adequateLevel else {
                await retry(session: session, dependencies: dependencies)
                return
            }
            phase = .checking
            let response = try await dependencies.backend.transcribe(
                audioURL: recording.fileURL,
                mode: .constrainedChoice,
                choiceSetID: "readAloud"
            )
            guard response.valid, let choice = response.choice else {
                await retry(session: session, dependencies: dependencies)
                return
            }
            answer(choice == "yes", session: session, dependencies: dependencies)
        } catch {
            phase = .retry
            dependencies.spokenPrompts.speak("I couldn’t hear an answer. You can say it again, or use the two large buttons.")
        }
    }

    func answer(_ canContinue: Bool, session: AppSession, dependencies: AppDependencies) {
        guard phase != .finished else { return }
        phase = .finished
        HapticFeedback.impact()
        if canContinue {
            session.navigate(to: .deviceCheck)
        } else {
            dependencies.spokenPrompts.speak("That’s okay. This screening should not continue.")
            session.navigate(to: .safetyStop)
        }
    }

    private func retry(session: AppSession, dependencies: AppDependencies) async {
        phase = .retry
        await dependencies.spokenPrompts.speakAndWait("I didn’t catch that. Say yes to continue, or no to stop.")
        hasBegun = false
        await begin(session: session, dependencies: dependencies)
    }
}

struct EligibilityView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = VoiceSafetyViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.system(size: 62, weight: .light))
            Text("One safety check")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Listen, then say yes or no.")
                .font(.body.weight(.medium))
                .foregroundStyle(SEENATheme.secondaryInk)
            VoiceStatusPill(isListening: model.phase == .listening)
            Text(model.status)
                .font(.headline)
                .contentTransition(.opacity)
            Spacer()

            if model.phase == .retry {
                Button("Ask me again") {
                    Task { await model.ask(session: session, dependencies: dependencies) }
                }
                .buttonStyle(PrimaryActionStyle())
            }

            HStack(spacing: 12) {
                Button("No, stop") { model.answer(false, session: session, dependencies: dependencies) }
                    .buttonStyle(SecondaryActionStyle())
                Button("Yes, continue") { model.answer(true, session: session, dependencies: dependencies) }
                    .buttonStyle(PrimaryActionStyle())
            }
        }
        .padding(24)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { await model.begin(session: session, dependencies: dependencies) }
    }
}

struct SafetyStopView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "heart.text.square")
                .font(.system(size: 60, weight: .light))
            Text("Please stop here")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("SeeNA is not suitable today. If you have sudden vision change, severe pain, or an eye injury, seek professional care promptly.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SEENATheme.secondaryInk)
            Spacer()
            Text("No screening result was created")
                .font(.caption.weight(.semibold))
        }
        .padding(24)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task {
            await dependencies.spokenPrompts.speakAndWait(
                "Please stop here. SeeNA is not suitable today. For sudden vision change, severe pain, or an eye injury, seek professional care promptly."
            )
        }
    }
}
