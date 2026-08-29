import Observation
import SwiftUI

@MainActor
@Observable
private final class SafetyEligibilityViewModel {
    enum Phase: Equatable { case question, selectReason, finished }

    private(set) var phase: Phase = .question
    private var hasBegun = false

    func begin(dependencies: AppDependencies) async {
        guard !hasBegun else { return }
        hasBegun = true
        _ = await dependencies.spokenPrompts.speakAndWait(
            "Safety check. Read the exclusions on screen. Tap No, none apply to continue, or Yes, one applies to stop."
        )
    }

    func answer(hasExclusion: Bool, session: AppSession, dependencies: AppDependencies) {
        guard phase == .question else { return }
        dependencies.spokenPrompts.stop()
        HapticFeedback.impact()
        if hasExclusion {
            phase = .selectReason
            dependencies.spokenPrompts.speak("Choose the reason that applies so I can show the right safety guidance.")
        } else {
            phase = .finished
            session.navigate(to: .permissions)
        }
    }

    func stop(for reason: SafetyStopReason, session: AppSession, dependencies: AppDependencies) {
        guard phase == .selectReason else { return }
        phase = .finished
        session.safetyStopReason = reason
        dependencies.spokenPrompts.stop()
        session.navigate(to: .safetyStop)
    }

    func backToQuestion() { phase = .question }

    func cancel(dependencies: AppDependencies) {
        hasBegun = false
        dependencies.spokenPrompts.stop()
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

                    Text("Remove glasses for the task. This check happens before SeeNA asks for camera or microphone access.")
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
        .task { await model.begin(dependencies: dependencies) }
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
            Button("Back", action: model.backToQuestion)
                .frame(minHeight: 44)
        }
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
