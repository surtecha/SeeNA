import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ProcessingViewModel {
    enum Phase: Equatable {
        case idle
        case saving
        case saveFailed
        case explaining
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var recoveryDeletionAllowed = false
    private var hasStarted = false
    private let store: SessionStore
    private let backend: BackendClient
    private let sensors: SensorCoordinator
    private let brightness: BrightnessManager

    init(store: SessionStore, backend: BackendClient, sensors: SensorCoordinator, brightness: BrightnessManager) {
        self.store = store
        self.backend = backend
        self.sensors = sensors
        self.brightness = brightness
    }

    func begin(session: AppSession) async {
        guard !hasStarted else { return }
        hasStarted = true
        sensors.stop()
        await saveAndFinish(session: session)
    }

    func retrySave(session: AppSession) async {
        guard phase == .saveFailed else { return }
        await saveAndFinish(session: session)
    }

    func continueWithoutSaving(session: AppSession) async {
        guard phase == .saveFailed else { return }
        session.persistenceState = .volatile
        await finish(session: session)
    }

    func deleteUnreadableHistoryAndRetry(session: AppSession) async {
        guard phase == .saveFailed, recoveryDeletionAllowed else { return }
        do {
            try await store.deleteAll()
            hasStarted = false
            await begin(session: session)
        } catch {
            phase = .saveFailed
            session.appError = .persistenceFailed
        }
    }

    private func saveAndFinish(session: AppSession) async {
        phase = .saving
        do {
            try await store.save(session.activeSession)
            session.persistenceState = .saved
            recoveryDeletionAllowed = false
        } catch {
            recoveryDeletionAllowed = SessionStore.allowsDestructiveRecovery(after: error)
            phase = .saveFailed
            session.appError = .persistenceFailed
            return
        }
        await finish(session: session)
    }

    private func finish(session: AppSession) async {
        phase = .explaining
        let request = Self.explanationRequest(for: session.activeSession)
        do {
            session.cachedExplanation = try await backend.explain(request)
        } catch {
            session.cachedExplanation = Self.fallbackExplanation(for: request)
        }
        brightness.restore()
        phase = .finished
        guard !Task.isCancelled, session.path.last == .processing else { return }
        session.navigate(to: .results)
    }

    static func explanationRequest(for screening: ScreeningSession) -> ExplanationRequest {
        let summary = ScreeningIntegritySummary(screening: screening)
        let integrity = summary.allPresentResultsValid
        let presentation = ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: summary.right?.isValid == true && summary.left?.isValid == true,
            gaborIntegrityValid: summary.rightGabor?.isValid == true && summary.leftGabor?.isValid == true
        )
        let rightResult = ResultsPresentationPolicy.presentableEyeResult(
            screening.rightEyeResult,
            numericResultsAllowed: screening.numericResultsAllowed
        )
        let leftResult = ResultsPresentationPolicy.presentableEyeResult(
            screening.leftEyeResult,
            numericResultsAllowed: screening.numericResultsAllowed
        )
        let results = [rightResult, leftResult].compactMap { $0 }
        let action: ExplanationRequest.ActionCode
        if presentation.reliability != .reliable {
            action = .noReliableResult
        } else if presentation.recommendation == .professionalReviewRecommended {
            action = .professionalExamRecommended
        } else {
            action = .routineExamRecommended
        }

        let comparison: ExplanationRequest.ComparisonCode
        if screening.numericResultsAllowed == true,
           let right = rightResult,
           let left = leftResult,
           let rightValue = right.displayedEstimateDiopter,
           let leftValue = left.displayedEstimateDiopter {
            comparison = abs(rightValue - leftValue) >= 0.75
                ? .eyesNoticeablyDifferent
                : .eyesBroadlySimilar
        } else if presentation.reliability != .reliable || results.count < 2 {
            comparison = .repeatNeeded
        } else {
            comparison = .reviewEyesSeparately
        }

        return ExplanationRequest(
            locale: "en-AU",
            rightEye: rightResult.map {
                .init(status: $0.status, quality: $0.trackingQuality)
            },
            leftEye: leftResult.map {
                .init(status: $0.status, quality: $0.trackingQuality)
            },
            comparisonCode: comparison,
            actionCode: action,
            limitations: [
                .notAPrescription,
                .hyperopiaNotAssessed,
                .clinicalAccuracyNotEstablished,
                .phonePOCNotClinicallyValidated
            ],
            localIntegrityCode: integrity ? .consistent : .reviewRequired
        )
    }

    static func fallbackExplanation(for request: ExplanationRequest) -> ExplanationResponse {
        let statuses = [request.rightEye?.status, request.leftEye?.status].compactMap { $0 }
        let isNonnumeric = statuses.contains { status in
            switch status {
            case .experimentalThresholdObserved, .experimentalFarthestTargetPassed,
                 .experimentalAdverseBoundary, .experimentalTaskCompleted:
                return true
            default:
                return false
            }
        }
        let comparison: String = switch request.comparisonCode {
        case .eyesBroadlySimilar: "The two eye results were broadly similar."
        case .eyesNoticeablyDifferent: "The two eye results were noticeably different."
        case .reviewEyesSeparately: "Your answers were recorded for both eyes."
        case .repeatNeeded: "One or more tasks need repeating."
        }
        let needsRepeat = request.actionCode == .noReliableResult
        return ExplanationResponse(
            headline: needsRepeat ? "Repeat needed" : "Tasks complete",
            plainMeaning: isNonnumeric && !needsRepeat
                ? "Your answers were recorded for both eyes."
                : comparison,
            limitations: [
                "This task is not a glasses prescription.",
                "It cannot diagnose eye conditions."
            ],
            nextSteps: ["Continue routine eye checks with an eye care professional."],
            disclaimer: "This task is not a diagnosis or glasses prescription.",
            verification: request.localIntegrityCode != .consistent
                ? .reviewRequired
                : isNonnumeric ? .notApplicable : .consistent,
            usedFallback: true
        )
    }
}

struct ProcessingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var model: ProcessingViewModel
    @State private var confirmingRecoveryDeletion = false

    init(model: ProcessingViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 18) {
            if model.phase == .saveFailed {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(model.phase == .saveFailed ? "Session not saved" : "Preparing your summary")
                .font(.title2.bold())
            Text(model.phase == .saveFailed
                 ? "You can retry, or continue with a volatile result that will disappear when you leave it."
                 : "Your responses are being prepared on this iPhone.")
                .font(.body)
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
            if model.phase == .saveFailed {
                Button("Retry save") {
                    Task { await model.retrySave(session: session) }
                }
                .buttonStyle(PrimaryActionStyle())
                if model.recoveryDeletionAllowed {
                    Button("Delete unreadable history and retry") {
                        confirmingRecoveryDeletion = true
                    }
                    .buttonStyle(SecondaryActionStyle())
                }
                Button("Continue without saving") {
                    Task { await model.continueWithoutSaving(session: session) }
                }
                .buttonStyle(SecondaryActionStyle())
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task {
            await model.begin(session: session)
        }
        .confirmationDialog(
            "Delete all previous saved sessions?",
            isPresented: $confirmingRecoveryDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete history and retry", role: .destructive) {
                Task { await model.deleteUnreadableHistoryAndRetry(session: session) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this only if saved history is unreadable. The current session will then be saved again.")
        }
    }
}

@MainActor
@Observable
final class ResultsViewModel {
    let screening: ScreeningSession
    let integrity: ScreeningIntegritySummary
    let presentation: ResultsPresentation
    private let cachedExplanation: ExplanationResponse?

    init(screening: ScreeningSession, cachedExplanation: ExplanationResponse?) {
        self.screening = screening
        self.cachedExplanation = cachedExplanation
        let integrity = ScreeningIntegritySummary(screening: screening)
        self.integrity = integrity
        presentation = ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: integrity.right?.isValid == true && integrity.left?.isValid == true,
            gaborIntegrityValid: integrity.rightGabor?.isValid == true && integrity.leftGabor?.isValid == true
        )
    }

    var displayedExplanation: String {
        ResultsPresentationPolicy.explanation(
            local: presentation.localMeaning,
            remote: cachedExplanation?.plainMeaning,
            remoteVerified: cachedExplanation?.verification == .consistent,
            remoteWasGenerated: cachedExplanation?.usedFallback == false,
            reliability: presentation.reliability
        )
    }

    var spokenOpening: String { presentation.headline }
}

struct ResultsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model: ResultsViewModel
    @State private var hasSpoken = false
    @State private var activeSpeechID: UUID?
    @State private var showingAnswers = false

    init(model: ResultsViewModel) {
        _model = State(initialValue: model)
    }

    private var displayedExplanation: String {
        model.displayedExplanation
    }

    var body: some View {
        ScrollView(showsIndicators: dynamicTypeSize.isAccessibilitySize) {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.presentation.headline)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                if session.persistenceState == .volatile {
                    Label("Not saved — this result is available only on this screen", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.body.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 14))
                }

                ResultPair(
                    eye: .right,
                    landolt: model.screening.rightEyeResult,
                    gabor: model.screening.rightGaborResult,
                    integrity: model.integrity.right,
                    gaborIntegrity: model.integrity.rightGabor,
                    numericResultsAllowed: model.screening.numericResultsAllowed
                )
                ResultPair(
                    eye: .left,
                    landolt: model.screening.leftEyeResult,
                    gabor: model.screening.leftGaborResult,
                    integrity: model.integrity.left,
                    gaborIntegrity: model.integrity.leftGabor,
                    numericResultsAllowed: model.screening.numericResultsAllowed
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What this means").font(.headline)
                    Text(displayedExplanation)
                        .font(.body)
                        .foregroundStyle(SEENATheme.secondaryInk)
                }
                .padding(16)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))

                Label(nextStepText, systemImage: "arrow.right.circle.fill")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                voiceControls

                if model.presentation.canOpenAnswerAudit {
                    Button("See answers", action: showAnswers)
                        .buttonStyle(SecondaryActionStyle())
                }

                Button("Start again") {
                    dependencies.resetForNewScreening()
                    session.startNewSession()
                }
                    .buttonStyle(PrimaryActionStyle())

                Text("This task is not a diagnosis or glasses prescription.")
                    .font(.caption)
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showingAnswers) {
            ResultsAnswerAuditView(
                screening: model.screening,
                isScreeningComplete: model.presentation.structurallyFinished
            )
        }
        .task {
#if DEBUG
            if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
                print("SEENA_DEBUG_AUTOMATION_RESULT_READY")
            }
#endif
            guard !hasSpoken else { return }
            hasSpoken = true
            dependencies.brightness.restore()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .screenChanged, argument: conciseSpokenSummary)
            } else {
                await speakAndTrack(conciseSpokenSummary)
            }
        }
        .onDisappear {
            activeSpeechID = nil
            dependencies.spokenPrompts.stop()
        }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Listen", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                Spacer()
                if activeSpeechID != nil {
                    Text("Speaking")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SEENATheme.secondaryInk)
                        .accessibilityHidden(true)
                }
            }

            Button(action: speakFullResult) {
                Label("Hear full result", systemImage: "text.bubble.fill")
            }
            .buttonStyle(SecondaryActionStyle())
            .accessibilityHint("Reads both eye results, their meaning, and the next step")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { secondaryVoiceControls }
                } else {
                    HStack(spacing: 12) { secondaryVoiceControls }
                }
            }
        }
        .padding(16)
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SEENATheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var secondaryVoiceControls: some View {
        Button(action: repeatConciseResult) {
            Label("Repeat", systemImage: "repeat")
        }
        .buttonStyle(SecondaryActionStyle())
        .accessibilityHint("Repeats the short result summary")

        Button(action: stopVoice) {
            Label("Stop voice", systemImage: "stop.fill")
        }
        .buttonStyle(SecondaryActionStyle())
        .accessibilityHint("Stops SeeNA from speaking")
    }

    private var conciseSpokenSummary: String {
        "\(model.spokenOpening) \(nextStepText)"
    }

    private var fullSpokenSummary: String {
        let right = ResultPair.spokenSummary(
            eye: .right,
            landolt: model.screening.rightEyeResult,
            gabor: model.screening.rightGaborResult,
            integrity: model.integrity.right,
            gaborIntegrity: model.integrity.rightGabor,
            numericResultsAllowed: model.screening.numericResultsAllowed
        )
        let left = ResultPair.spokenSummary(
            eye: .left,
            landolt: model.screening.leftEyeResult,
            gabor: model.screening.leftGaborResult,
            integrity: model.integrity.left,
            gaborIntegrity: model.integrity.leftGabor,
            numericResultsAllowed: model.screening.numericResultsAllowed
        )
        let explanationText = " \(displayedExplanation)"

        // All measurement numbers above come from local deterministic state.
        // Model prose is appended only after the separate consistency pass;
        // otherwise this is the deterministic local comparison above.
        let opening = model.spokenOpening
        return "\(opening). \(right) \(left)\(explanationText) This does not diagnose eye conditions or provide a glasses prescription. \(nextStepText)"
    }

    private func speakFullResult() {
        startSpeech(fullSpokenSummary, allowsLongForm: true)
    }

    private func repeatConciseResult() {
        startSpeech(conciseSpokenSummary, allowsLongForm: false)
    }

    private func startSpeech(_ text: String, allowsLongForm: Bool) {
        let speechID = UUID()
        activeSpeechID = speechID
        Task { @MainActor in
            if allowsLongForm {
                _ = await dependencies.spokenPrompts.speakLocallyAndWait(text)
            } else {
                _ = await dependencies.spokenPrompts.speakLocallyForTransition(text)
            }
            guard activeSpeechID == speechID else { return }
            activeSpeechID = nil
        }
    }

    private func speakAndTrack(_ text: String) async {
        let speechID = UUID()
        activeSpeechID = speechID
        _ = await dependencies.spokenPrompts.speakLocallyForTransition(text)
        guard activeSpeechID == speechID else { return }
        activeSpeechID = nil
    }

    private func stopVoice() {
        activeSpeechID = nil
        dependencies.spokenPrompts.stop()
        HapticFeedback.impact(.light)
        UIAccessibility.post(notification: .announcement, argument: "Voice stopped")
    }

    private func showAnswers() {
        guard model.presentation.canOpenAnswerAudit else { return }
        showingAnswers = true
    }

    private var nextStepText: String {
        switch model.presentation.recommendation {
        case .professionalReviewRecommended:
            return "Arrange a professional eye examination."
        case .repeatRequired:
            return "Repeat the affected task."
        case .routineExamRecommended, .unavailable:
            return "Continue routine eye checks with an eye care professional."
        }
    }
}

@MainActor
@Observable
final class SessionHistoryViewModel {
    private(set) var sessions: [ScreeningSession] = []
    private(set) var errorMessage: String?
    private(set) var recoveryDeletionRequired = false
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
    }

    func load() async {
        do {
            sessions = try await store.loadSessions()
            errorMessage = nil
            recoveryDeletionRequired = false
        } catch {
            recoveryDeletionRequired = SessionStore.allowsDestructiveRecovery(after: error)
            errorMessage = recoveryDeletionRequired
                ? "Saved history is unreadable or unsupported. You can delete it below after confirmation."
                : "Saved sessions could not be loaded. Try again later; existing history will not be deleted."
        }
    }

    func delete(id: UUID) async {
        do {
            try await store.delete(sessionID: id)
            sessions.removeAll { $0.id == id }
        } catch {
            errorMessage = "That session could not be deleted."
        }
    }

    func deleteAll() async {
        do {
            try await store.deleteAll()
            sessions.removeAll()
            errorMessage = nil
            recoveryDeletionRequired = false
        } catch {
            errorMessage = "Saved sessions could not be deleted."
        }
    }
}

struct SessionHistoryView: View {
    @State private var model: SessionHistoryViewModel
    @State private var pendingDeleteID: UUID?
    @State private var confirmingDeleteAll = false

    init(model: SessionHistoryViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            Section {
                Text("Saved only on this iPhone. Audio recordings are deleted after each response.")
                    .font(.body)
                    .foregroundStyle(SEENATheme.secondaryInk)
            }

            if let errorMessage = model.errorMessage {
                Section("Needs attention") {
                    Label {
                        Text(errorMessage)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(SEENATheme.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("History error. \(errorMessage)")
                }
            }

            Section("Previous sessions") {
                if model.sessions.isEmpty {
                    Text("No saved sessions")
                        .foregroundStyle(SEENATheme.secondaryInk)
                } else {
                    ForEach(model.sessions) { screening in
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink {
                                SavedSessionDetailView(screening: screening)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(screening.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Text(historySummary(screening))
                                        .font(.body)
                                        .foregroundStyle(SEENATheme.secondaryInk)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingDeleteID = screening.id
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Delete session")
                        }
                    }
                }
            }

            if !model.sessions.isEmpty {
                Section {
                    Button("Delete all sessions", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                }
            }
            if model.recoveryDeletionRequired {
                Section("Recovery") {
                    Text("The saved file is corrupt or uses an unsupported format. Deletion remains available without decoding it.")
                        .font(.body)
                    Button("Delete unreadable history", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                }
            }

        }
        .navigationTitle("Previous sessions")
        .task { await model.load() }
        .onChange(of: model.errorMessage) { _, errorMessage in
            guard let errorMessage else { return }
            UIAccessibility.post(notification: .announcement, argument: "History error. \(errorMessage)")
        }
        .alert("Delete this session?", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await model.delete(id: id) }
            }
        } message: {
            Text("This removes the saved result and answers from this iPhone.")
        }
        .confirmationDialog(
            "Delete every saved session?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                Task { await model.deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func historySummary(_ screening: ScreeningSession) -> String {
        let integrity = ScreeningIntegritySummary(screening: screening)
        return ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: integrity.right?.isValid == true && integrity.left?.isValid == true,
            gaborIntegrityValid: integrity.rightGabor?.isValid == true && integrity.leftGabor?.isValid == true
        ).headline
    }
}

private struct SavedSessionDetailView: View {
    let screening: ScreeningSession
    @State private var showingAnswers = false

    private var integrity: ScreeningIntegritySummary { ScreeningIntegritySummary(screening: screening) }

    private var presentation: ResultsPresentation {
        ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: integrity.right?.isValid == true && integrity.left?.isValid == true,
            gaborIntegrityValid: integrity.rightGabor?.isValid == true && integrity.leftGabor?.isValid == true
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(screening.createdAt.formatted(date: .long, time: .shortened))
                    .font(.title2.bold())
                Text("Saved result")
                    .font(.body)
                    .foregroundStyle(SEENATheme.secondaryInk)
                ResultPair(eye: .right, landolt: screening.rightEyeResult, gabor: screening.rightGaborResult, integrity: integrity.right, gaborIntegrity: integrity.rightGabor, numericResultsAllowed: screening.numericResultsAllowed)
                ResultPair(eye: .left, landolt: screening.leftEyeResult, gabor: screening.leftGaborResult, integrity: integrity.left, gaborIntegrity: integrity.leftGabor, numericResultsAllowed: screening.numericResultsAllowed)
                Text(presentation.localMeaning).font(.body)
                Label("\(screening.rightEyeTrials.count + screening.leftEyeTrials.count) circle answers saved", systemImage: "doc.text.magnifyingglass")
                Label("\((screening.rightGaborTrials ?? []).count + (screening.leftGaborTrials ?? []).count) pattern answers saved", systemImage: "checklist")
                Button("See answers") { showingAnswers = true }
                    .buttonStyle(SecondaryActionStyle())
            }
            .padding(20)
        }
        .navigationTitle("Saved session")
        .sheet(isPresented: $showingAnswers) {
            ResultsAnswerAuditView(screening: screening, isScreeningComplete: presentation.structurallyFinished)
        }
    }
}
