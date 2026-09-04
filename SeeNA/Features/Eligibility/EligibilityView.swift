import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
private final class SafetyEligibilityViewModel {
    enum Phase: Equatable { case question, selectReason, finished }

    enum VoiceState: Equatable {
        case preparing
        case speaking
        case listening
        case checking
        case touchFallback

        var statusText: String {
            switch self {
            case .preparing: return "Preparing voice"
            case .speaking: return "Listen for the question"
            case .listening: return "Listening for yes or no"
            case .checking: return "Checking your answer"
            case .touchFallback: return "Tap yes or no below"
            }
        }

        var isListening: Bool { self == .listening }

        var systemImage: String {
            switch self {
            case .preparing: return "ellipsis"
            case .speaking: return "speaker.wave.2.fill"
            case .listening: return "waveform"
            case .checking: return "checkmark.circle"
            case .touchFallback: return "hand.tap"
            }
        }
    }

    private(set) var phase: Phase = .question
    private(set) var voiceState: VoiceState = .preparing
    @ObservationIgnored private var conversationID: UUID?
    @ObservationIgnored private var auxiliaryTask: Task<Void, Never>?

    private let safetyQuestion = "Safety check. Say yes for sudden vision loss, severe eye pain or injury, contact lenses in, being under eighteen, or being unable to move safely. Otherwise, say no."
    private let retryQuestion = "Please say yes if any item applies, or no if none apply."

    func begin(session: AppSession, dependencies: AppDependencies) async {
        guard phase == .question, conversationID == nil else { return }
        let conversationID = UUID()
        self.conversationID = conversationID
        defer {
            if self.conversationID == conversationID {
                self.conversationID = nil
            }
        }

        voiceState = .preparing
        if AVAudioApplication.shared.recordPermission == .undetermined {
            voiceState = .speaking
            _ = await dependencies.spokenPrompts.speakForTransition(
                "To answer hands-free, SeeNA needs microphone access. Tap Allow."
            )
            guard isCurrent(conversationID, session: session) else { return }
        }
        let microphoneAllowed = await dependencies.audioRecorder.requestPermission()
        guard isCurrent(conversationID, session: session) else { return }

        var prompt = safetyQuestion
        var failedAttempts = 0

        while isCurrent(conversationID, session: session) {
            voiceState = .speaking
            let speechOutcome = await dependencies.spokenPrompts.speakAndWait(prompt)
            guard isCurrent(conversationID, session: session) else { return }
            guard SpeechProgressionPolicy.shouldAdvance(after: speechOutcome) else {
                voiceState = .touchFallback
                return
            }

            guard microphoneAllowed,
                  session.responseMode == .voicePreferred,
                  dependencies.network.isConnected else {
                await announceTouchFallback(conversationID, session: session, dependencies: dependencies)
                return
            }

            do {
                voiceState = .listening
                let recording = try await dependencies.audioRecorder.record(maximumDuration: 8)
                defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
                guard isCurrent(conversationID, session: session) else { return }

                if recording.adequateLevel {
                    voiceState = .checking
                    let response = try await dependencies.backend.transcribe(
                        audioURL: recording.fileURL,
                        mode: .constrainedChoice,
                        phraseID: "safety-eligibility",
                        choiceSetID: "eligibility"
                    )
                    guard isCurrent(conversationID, session: session) else { return }

                    if response.valid, response.choice == "no" {
                        answer(hasExclusion: false, session: session, dependencies: dependencies)
                        return
                    }
                    if response.valid, response.choice == "yes" {
                        answer(hasExclusion: true, session: session, dependencies: dependencies)
                        return
                    }
                }

                failedAttempts += 1
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(conversationID, session: session) else { return }
                failedAttempts += 1
            }

            guard failedAttempts < 2, dependencies.network.isConnected else {
                await announceTouchFallback(conversationID, session: session, dependencies: dependencies)
                return
            }
            prompt = retryQuestion
        }
    }

    func answer(hasExclusion: Bool, session: AppSession, dependencies: AppDependencies) {
        guard phase == .question else { return }
        conversationID = nil
        auxiliaryTask?.cancel()
        auxiliaryTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        HapticFeedback.impact()
        if hasExclusion {
            phase = .selectReason
            auxiliaryTask = Task { [weak self] in
                guard let self else { return }
                _ = await dependencies.spokenPrompts.speakAndWait(
                    "Choose the reason that applies so I can show the right safety guidance."
                )
                guard !Task.isCancelled,
                      self.phase == .selectReason,
                      session.path.last == .eligibility else { return }
            }
        } else {
            phase = .finished
            session.navigate(to: .permissions)
        }
    }

    func stop(for reason: SafetyStopReason, session: AppSession, dependencies: AppDependencies) {
        guard phase == .selectReason else { return }
        phase = .finished
        session.safetyStopReason = reason
        auxiliaryTask?.cancel()
        auxiliaryTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        session.navigate(to: .safetyStop)
    }

    func backToQuestion(session: AppSession, dependencies: AppDependencies) {
        guard phase == .selectReason else { return }
        auxiliaryTask?.cancel()
        auxiliaryTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        phase = .question
        voiceState = .preparing
        auxiliaryTask = Task { [weak self] in
            await self?.begin(session: session, dependencies: dependencies)
        }
    }

    func cancel(dependencies: AppDependencies) {
        conversationID = nil
        auxiliaryTask?.cancel()
        auxiliaryTask = nil
        voiceState = .preparing
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
    }

    private func isCurrent(_ id: UUID, session: AppSession) -> Bool {
        !Task.isCancelled
            && conversationID == id
            && phase == .question
            && session.path.last == .eligibility
    }

    private func announceTouchFallback(
        _ id: UUID,
        session: AppSession,
        dependencies: AppDependencies
    ) async {
        guard isCurrent(id, session: session) else { return }
        voiceState = .speaking
        _ = await dependencies.spokenPrompts.speakAndWait(
            "Voice answers are unavailable right now. Please tap yes or no below."
        )
        guard isCurrent(id, session: session) else { return }
        voiceState = .touchFallback
    }
}

struct EligibilityView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = SafetyEligibilityViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 58, weight: .light))
                    .frame(maxWidth: .infinity)
                Text(model.phase == .selectReason ? "Which reason applies?" : "Safety check first")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                if model.phase == .selectReason {
                    reasonChoices
                } else {
                    Text("Do not continue if any item below applies today.")
                        .font(.title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(SafetyStopReason.allCases.filter { $0 != .other }) { reason in
                            Label(reason.title, systemImage: "exclamationmark.circle")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 16))

                    EligibilityVoiceStatus(state: model.voiceState)

                    Text("Remove glasses for the task. Say yes or no, or use the large buttons.")
                        .font(.body)
                        .foregroundStyle(SEENATheme.secondaryInk)

                    VStack(spacing: 12) {
                        Button("No, none apply") {
                            model.answer(hasExclusion: false, session: session, dependencies: dependencies)
                        }
                        .buttonStyle(PrimaryActionStyle())
                        Button("Yes, one applies") {
                            model.answer(hasExclusion: true, session: session, dependencies: dependencies)
                        }
                        .buttonStyle(SecondaryActionStyle())
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { await model.begin(session: session, dependencies: dependencies) }
        .onDisappear { model.cancel(dependencies: dependencies) }
    }

    private var reasonChoices: some View {
        VStack(spacing: 12) {
            ForEach(SafetyStopReason.allCases) { reason in
                Button(reason.title) {
                    model.stop(for: reason, session: session, dependencies: dependencies)
                }
                .buttonStyle(SecondaryActionStyle())
                .frame(minHeight: 44)
            }
            Button("Back") {
                model.backToQuestion(session: session, dependencies: dependencies)
            }
                .frame(minHeight: 44)
        }
    }
}

private struct EligibilityVoiceStatus: View {
    let state: SafetyEligibilityViewModel.VoiceState

    var body: some View {
        Label(
            state.statusText,
            systemImage: state.systemImage
        )
        .font(.headline.weight(.semibold))
        .foregroundStyle(SEENATheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(SEENATheme.strongCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.statusText)
    }
}

struct SafetyStopView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    private var guidance: String {
        (session.safetyStopReason ?? .other).urgentGuidance
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 60, weight: .light))
                Text("Please stop here")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(guidance)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No screening result was created. This is not medical advice.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                Button("Return to start") {
                    dependencies.resetForNewScreening()
                    session.startNewSession()
                }
                .buttonStyle(PrimaryActionStyle())
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { _ = await dependencies.spokenPrompts.speakAndWait(guidance) }
        .onDisappear { dependencies.spokenPrompts.stop() }
    }
}
