import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var didStart = false

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Calculating your result")
                .font(.title2.bold())
            Text("Your measurements and answers are calculated on this iPhone.")
                .font(.body)
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task {
            guard !didStart else { return }
            didStart = true
            await process()
        }
    }

    private func process() async {
        do {
            try await dependencies.sessionStore.save(session.activeSession)
        } catch {
            session.appError = .persistenceFailed
        }

        let request = ExplanationRequest(
            locale: "en-AU",
            rightEye: explanationFacts(for: session.activeSession.rightEyeResult),
            leftEye: explanationFacts(for: session.activeSession.leftEyeResult),
            comparison: localComparison,
            actionCode: actionCode,
            limitations: [
                "not_a_prescription",
                "hyperopia_not_assessed",
                "clinical_accuracy_not_established",
                "phone_screen_far_point_poc_not_clinically_validated"
            ],
            localMathConsistent: localMathConsistent
        )
        do {
            session.cachedExplanation = try await dependencies.backend.explain(request)
        } catch {
            session.cachedExplanation = Self.fallbackExplanation(for: request)
        }
        dependencies.brightness.restore()
        session.navigate(to: .results)
    }

    private var actionCode: String {
        guard localMathConsistent else { return "no_reliable_result" }
        let results = [session.activeSession.rightEyeResult, session.activeSession.leftEyeResult].compactMap { $0 }
        if results.isEmpty || results.contains(where: { $0.status == .unreliableMeasurement }) {
            return "no_reliable_result"
        }
        if results.contains(where: { $0.status == .validEstimate || $0.status == .strongerThanSupportedRange }) {
            return "professional_exam_recommended"
        }
        return "routine_exam_recommended"
    }

    private var localComparison: String {
        guard let right = session.activeSession.rightEyeResult,
              let left = session.activeSession.leftEyeResult else {
            return "One or both eyes need the visual screening repeated."
        }
        guard let rightValue = right.displayedEstimateDiopter,
              let leftValue = left.displayedEstimateDiopter else {
            return "Review each eye separately because at least one result is at the supported range boundary."
        }
        return abs(rightValue - leftValue) >= 0.75
            ? "The two eyes produced noticeably different screening estimates."
            : "The two eye screening estimates were broadly similar."
    }

    static func fallbackExplanation(for request: ExplanationRequest) -> ExplanationResponse {
        let unreliable = request.actionCode == "no_reliable_result"
        return ExplanationResponse(
            headline: unreliable ? "One or both eyes need a repeat." : "Your screening is complete.",
            plainMeaning: request.comparison,
            limitations: [
                "This is an approximate screening result, not a glasses prescription.",
                "It does not assess hyperopia, astigmatism, or eye disease."
            ],
            nextSteps: ["Arrange a complete eye examination when accessible."],
            disclaimer: "Research POC only — not a diagnosis or prescription.",
            verification: request.localMathConsistent ? .consistent : .reviewRequired,
            usedFallback: true
        )
    }

    private var localMathConsistent: Bool {
        ScreeningIntegritySummary(screening: session.activeSession).allPresentResultsValid
    }

    private func explanationFacts(
        for result: EyeScreeningResult?
    ) -> ExplanationRequest.EyeFacts? {
        result.map {
            ExplanationRequest.EyeFacts(
                status: $0.status,
                quality: $0.trackingQuality,
                displayedEstimateDiopter: $0.displayedEstimateDiopter,
                thresholdDistanceMetres: $0.thresholdDistanceMetres,
                lastFailDiopter: $0.lastFailDiopter,
                firstPassDiopter: $0.firstPassDiopter,
                sensorUncertaintyDiopter: $0.sensorUncertaintyDiopter,
                repeatabilityDiopter: $0.repeatabilityDiopter
            )
        }
    }
}

struct ResultsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var hasSpoken = false
    @State private var showingAnswers = false

    private var isScreeningComplete: Bool {
        session.activeSession.rightEyeResult != nil
            && session.activeSession.leftEyeResult != nil
            && session.activeSession.rightGaborResult != nil
            && session.activeSession.leftGaborResult != nil
    }

    private var eyeResults: [EyeScreeningResult] {
        [session.activeSession.rightEyeResult, session.activeSession.leftEyeResult]
            .compactMap { $0 }
    }

    private var integritySummary: ScreeningIntegritySummary {
        ScreeningIntegritySummary(screening: session.activeSession)
    }

    private var verificationNeedsReview: Bool {
        if !integritySummary.allPresentResultsValid { return true }
        if case .reviewRequired? = session.cachedExplanation?.verification { return true }
        return false
    }

    /// Never substitute model wording for the deterministic local summary
    /// unless the separate consistency pass explicitly approved it.
    private var displayedExplanation: String {
        guard session.cachedExplanation?.verification == .consistent,
              let modelText = session.cachedExplanation?.plainMeaning
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !modelText.isEmpty else {
            return localFallbackComparison
        }
        return modelText
    }

    private var localFallbackComparison: String {
        guard let right = session.activeSession.rightEyeResult,
              let left = session.activeSession.leftEyeResult else {
            return "One or both eyes need the visual screening repeated."
        }
        guard let rightValue = right.displayedEstimateDiopter,
              let leftValue = left.displayedEstimateDiopter else {
            return "Review each eye separately because at least one result is at the supported range boundary."
        }
        return abs(rightValue - leftValue) >= 0.75
            ? "The two eyes produced noticeably different screening estimates."
            : "The two eye screening estimates were broadly similar."
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your results")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                Text("Approximate screening")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SEENATheme.secondaryInk)

                if session.activeSession.deviceProfile?.isValidated == false {
                    Label("POC sensor calibration", systemImage: "wrench.and.screwdriver")
                        .font(.footnote.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }

                if !eyeResults.isEmpty {
                    ResultVerificationBadge(
                        needsReview: verificationNeedsReview,
                        issueCount: integritySummary.issueCount
                    )
                }

                ResultPair(
                    eye: .right,
                    landolt: session.activeSession.rightEyeResult,
                    gabor: session.activeSession.rightGaborResult,
                    integrity: integritySummary.right
                )
                ResultPair(
                    eye: .left,
                    landolt: session.activeSession.leftEyeResult,
                    gabor: session.activeSession.leftGaborResult,
                    integrity: integritySummary.left
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What this means").font(.headline)
                    Text(displayedExplanation)
                        .font(.body)
                        .foregroundStyle(SEENATheme.secondaryInk)
                }
                .padding(16)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))

                Label("Arrange a complete eye examination when accessible.", systemImage: "arrow.right.circle.fill")
                    .font(.body.weight(.semibold))

                if isScreeningComplete {
                    Button("See answers", action: showAnswers)
                        .buttonStyle(SecondaryActionStyle())
                }

                Button("How this was measured") { session.navigate(to: .evidence) }
                    .buttonStyle(SecondaryActionStyle())
                Button("Start again") { session.startNewSession() }
                    .buttonStyle(PrimaryActionStyle())

                Text("Not a prescription. The Gabor orientation task does not diagnose eye disease.")
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
                screening: session.activeSession,
                isScreeningComplete: isScreeningComplete
            )
        }
        .task {
            guard !hasSpoken else { return }
            hasSpoken = true
            dependencies.brightness.restore()
            await dependencies.spokenPrompts.speakAndWait(spokenSummary)
        }
    }

    private var spokenSummary: String {
        let right = ResultPair.spokenSummary(
            eye: .right,
            landolt: session.activeSession.rightEyeResult,
            gabor: session.activeSession.rightGaborResult,
            integrity: integritySummary.right
        )
        let left = ResultPair.spokenSummary(
            eye: .left,
            landolt: session.activeSession.leftEyeResult,
            gabor: session.activeSession.leftGaborResult,
            integrity: integritySummary.left
        )
        let explanationText = " \(displayedExplanation)"

        // All measurement numbers above come from local deterministic state.
        // Model prose is appended only after the separate consistency pass;
        // otherwise this is the deterministic local comparison above.
        let opening = isScreeningComplete
            ? "Your screening is complete."
            : "Your screening needs a repeat."
        return "\(opening) \(right) \(left)\(explanationText) This is not a prescription. Please arrange a complete eye examination when accessible."
    }

    private func showAnswers() {
        guard isScreeningComplete else { return }
        showingAnswers = true
    }
}
