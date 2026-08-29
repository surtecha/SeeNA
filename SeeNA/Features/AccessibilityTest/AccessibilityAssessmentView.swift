import Combine
import SwiftUI

private enum AccessibilityAssessmentStage: Equatable {
    case readability
    case comfort
    case contrast
    case controls
    case readAloud
    case simplified
    case complete
}

@MainActor
private final class AccessibilityAssessmentViewModel: ObservableObject {
    @Published private(set) var stage: AccessibilityAssessmentStage = .readability
    @Published private(set) var sizeIndex = 0
    @Published private(set) var lastWordAccuracy: Double?
    @Published private(set) var transcript = ""
    @Published private(set) var isBusy = false
    @Published var message: String?

    let sizes: [Double] = [48, 40, 34, 28, 24, 20, 18, 16]
    let phrases = [
        "The bus arrives near the library at ten.",
        "A blue folder waits beside the window.",
        "The clinic opens after the morning train.",
        "Please bring the small green card today.",
        "Three quiet streets lead to the market.",
        "The next appointment begins before lunch.",
        "A warm jacket hangs near the front door.",
        "The local service closes at half past four."
    ]

    private var smallestReadable: Double?
    private var smallestComfortable: Double?

    var currentSize: Double { sizes[sizeIndex] }
    var currentPhrase: String { phrases[sizeIndex] }

    func testReadability(dependencies: AppDependencies) async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        do {
            await dependencies.spokenPrompts.speakAndWait("Read the sentence aloud when you are ready.")
            let recording = try await dependencies.audioRecorder.record(maximumDuration: 12)
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            guard recording.adequateLevel else {
                message = "The recording was too quiet. Please try again."
                isBusy = false
                return
            }
            let response = try await dependencies.backend.transcribe(
                audioURL: recording.fileURL,
                mode: .readabilityPhrase,
                phraseID: "readability-\(sizeIndex)"
            )
            guard response.valid else {
                message = response.failureReason ?? "The sentence could not be transcribed."
                isBusy = false
                return
            }
            transcript = response.transcript
            let accuracy = ReadabilityEngine.wordAccuracy(reference: currentPhrase, transcript: response.transcript)
            lastWordAccuracy = accuracy
            if accuracy >= 0.80 {
                smallestReadable = currentSize
                stage = .comfort
            } else {
                finishReadability()
            }
        } catch {
            message = "Voice transcription is unavailable. Check the connection and try again."
        }
        isBusy = false
    }

    func setComfortable(_ comfortable: Bool) {
        if comfortable {
            smallestComfortable = currentSize
            if sizeIndex < sizes.count - 1 {
                sizeIndex += 1
                lastWordAccuracy = nil
                transcript = ""
                stage = .readability
            } else {
                finishReadability()
            }
        } else {
            finishReadability()
        }
    }

    func choose(_ value: String, session: AppSession) {
        switch stage {
        case .contrast:
            session.accessibilityAnswers.prefersHighContrast = value == "two"
            stage = .controls
        case .controls:
            session.accessibilityAnswers.prefersLargeControls = value == "larger"
            stage = .readAloud
        case .readAloud:
            session.accessibilityAnswers.prefersReadAloud = value == "yes"
            stage = .simplified
        case .simplified:
            session.accessibilityAnswers.prefersSimplifiedContent = value == "two"
            finish(session: session)
        default:
            break
        }
    }

    func listenForChoice(dependencies: AppDependencies, session: AppSession) async {
        guard !isBusy, let choiceSetID else { return }
        isBusy = true
        message = nil
        do {
            let recording = try await dependencies.audioRecorder.record(maximumDuration: 8)
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            let response = try await dependencies.backend.transcribe(
                audioURL: recording.fileURL,
                mode: .constrainedChoice,
                choiceSetID: choiceSetID
            )
            if response.valid, let choice = response.choice {
                choose(choice, session: session)
            } else {
                message = "I could not understand one clear choice. Say one answer or use a button."
            }
        } catch {
            message = "Voice choice is unavailable. You can still use the large buttons."
        }
        isBusy = false
    }

    private var choiceSetID: String? {
        switch stage {
        case .contrast: return "contrast"
        case .controls: return "controls"
        case .readAloud: return "readAloud"
        case .simplified: return "simplified"
        default: return nil
        }
    }

    private func finishReadability() {
        stage = .contrast
    }

    private func finish(session: AppSession) {
        let readable = smallestReadable ?? sizes[max(0, sizeIndex - 1)]
        let comfortable = smallestComfortable ?? sizes[max(0, sizeIndex - 1)]
        session.accessibilityAnswers.minimumReadablePointSize = readable
        session.accessibilityAnswers.comfortablePointSize = max(readable, comfortable)
        let profile = AccessibilityProfileEngine.makeProfile(from: session.accessibilityAnswers)
        session.accessibilityProfile = profile
        session.activeSession.accessibilityProfile = profile
        stage = .complete
        session.navigate(to: .processing)
    }
}

struct AccessibilityAssessmentView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model = AccessibilityAssessmentViewModel()

    var body: some View {
        ScreenScaffold(title: title, subtitle: subtitle) {
            stageContent

            if let message = model.message {
                Text(message)
                    .font(.body.weight(.semibold))
                    .foregroundColor(SEENATheme.warning)
                    .padding(16)
                    .background(SEENATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .navigationTitle("Accessibility assessment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch model.stage {
        case .readability, .comfort: return "Readability staircase"
        case .contrast: return "Which contrast is easier?"
        case .controls: return "Which control is easier?"
        case .readAloud: return "Would spoken help be useful?"
        case .simplified: return "Which version is easier to follow?"
        case .complete: return "Profile complete"
        }
    }

    private var subtitle: String? {
        switch model.stage {
        case .readability: return "Read this unfamiliar sentence aloud. Word accuracy is calculated locally from the transcript."
        case .comfort: return "Was this size comfortable, without straining or leaning closer?"
        case .contrast: return "Say one or two, or use a button."
        case .controls: return "Say standard or larger, or use a button."
        case .readAloud: return "Listen to the sample, then say yes or no."
        case .simplified: return "Say one for the original or two for the structured version."
        case .complete: return nil
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .readability:
            Text(model.currentPhrase)
                .font(.system(size: model.currentSize))
                .foregroundColor(SEENATheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SEENATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("\(Int(model.currentSize)) pt")
                .font(.headline)
                .foregroundColor(SEENATheme.secondaryInk)
            Button(model.isBusy ? "Listening…" : "Read this aloud") {
                Task { await model.testReadability(dependencies: dependencies) }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(model.isBusy)

        case .comfort:
            if let accuracy = model.lastWordAccuracy {
                StatusRow(
                    title: "Word accuracy",
                    detail: String(format: "%.0f%% — transcript comparison completed locally", accuracy * 100),
                    state: accuracy >= 0.8 ? .ready : .warning
                )
            }
            choiceButtons(first: "Comfortable", second: "Not comfortable") {
                model.setComfortable($0 == "Comfortable")
            }

        case .contrast:
            HStack(spacing: 12) {
                comparisonCard("ONE", foreground: .gray, background: Color.gray.opacity(0.10))
                comparisonCard("TWO", foreground: .black, background: .white)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 3))
            }
            voiceChoiceButton()
            choiceButtons(first: "One — standard", second: "Two — stronger") {
                model.choose($0.hasPrefix("One") ? "one" : "two", session: session)
            }

        case .controls:
            Button("Standard action") { model.choose("standard", session: session) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
            Button("Larger action") { model.choose("larger", session: session) }
                .buttonStyle(PrimaryActionStyle())
            voiceChoiceButton()

        case .readAloud:
            Text("Medical travel support applications close on 14 September.")
                .font(.title3)
                .padding(20)
                .background(SEENATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Button("Play female voice sample") {
                dependencies.spokenPrompts.speak("Medical travel support applications close on the fourteenth of September.")
            }
            .buttonStyle(SecondaryActionStyle())
            voiceChoiceButton()
            choiceButtons(first: "Yes", second: "No") {
                model.choose($0 == "Yes" ? "yes" : "no", session: session)
            }

        case .simplified:
            Text("ONE — Applicants seeking consideration under the regional transportation reimbursement framework are required to provide documentation substantiating their residence and appointment.")
                .font(.body)
                .foregroundColor(.gray)
                .padding(16)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text("TWO — Medical Travel Support").font(.title2.bold())
                Text("You may be able to get help travelling to a medical appointment.")
                Text("You need: photo ID, proof of address and appointment confirmation.").fontWeight(.semibold)
            }
            .padding(18)
            .background(SEENATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            voiceChoiceButton()
            choiceButtons(first: "One — original", second: "Two — structured") {
                model.choose($0.hasPrefix("One") ? "one" : "two", session: session)
            }

        case .complete:
            ProgressView()
        }
    }

    private func comparisonCard(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func voiceChoiceButton() -> some View {
        Button(model.isBusy ? "Listening…" : "Answer by voice") {
            Task { await model.listenForChoice(dependencies: dependencies, session: session) }
        }
        .buttonStyle(SecondaryActionStyle())
        .disabled(model.isBusy)
    }

    private func choiceButtons(first: String, second: String, action: @escaping (String) -> Void) -> some View {
        VStack(spacing: 12) {
            Button(first) { action(first) }.buttonStyle(PrimaryActionStyle())
            Button(second) { action(second) }.buttonStyle(SecondaryActionStyle())
        }
    }
}
