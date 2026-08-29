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
            rightEye: session.activeSession.rightEyeResult.map { .init(status: $0.status, quality: $0.trackingQuality) },
            leftEye: session.activeSession.leftEyeResult.map { .init(status: $0.status, quality: $0.trackingQuality) },
            comparison: localComparison,
            actionCode: actionCode,
            limitations: ["not_a_prescription", "hyperopia_not_assessed", "clinical_accuracy_not_established"]
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
            usedFallback: true
        )
    }
}

struct ResultsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var hasSpoken = false

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

                ResultPair(
                    eye: .right,
                    landolt: session.activeSession.rightEyeResult,
                    gabor: session.activeSession.rightGaborResult
                )
                ResultPair(
                    eye: .left,
                    landolt: session.activeSession.leftEyeResult,
                    gabor: session.activeSession.leftGaborResult
                )

                if let explanation = session.cachedExplanation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What this means").font(.headline)
                        Text(explanation.plainMeaning)
                            .font(.body)
                            .foregroundStyle(SEENATheme.secondaryInk)
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                }

                Label("Arrange a complete eye examination when accessible.", systemImage: "arrow.right.circle.fill")
                    .font(.body.weight(.semibold))

                Button("How this was measured") { session.navigate(to: .evidence) }
                    .buttonStyle(SecondaryActionStyle())
                Button("Start again") { session.startNewSession() }
                    .buttonStyle(PrimaryActionStyle())

                Text("Not a prescription. Gabor contrast screening does not diagnose eye disease.")
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
            gabor: session.activeSession.rightGaborResult
        )
        let left = ResultPair.spokenSummary(
            eye: .left,
            landolt: session.activeSession.leftEyeResult,
            gabor: session.activeSession.leftGaborResult
        )
        return "Your screening is complete. \(right) \(left) This is not a prescription. Please arrange a complete eye examination when accessible."
    }
}

private struct ResultPair: View {
    let eye: Eye
    let landolt: EyeScreeningResult?
    let gabor: GaborScreeningResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(eye.displayName) eye")
                .font(.title3.bold())
            Divider()
            ResultMetric(label: "Landolt C", value: landoltValue)
            ResultMetric(label: "Gabor contrast", value: gaborValue)
        }
        .padding(16)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var landoltValue: String {
        guard let landolt else { return "Repeat needed" }
        switch landolt.status {
        case .validEstimate:
            if let fail = landolt.lastFailDiopter, let pass = landolt.firstPassDiopter {
                return String(format: "%.2f to %.2f D", max(fail, pass), min(fail, pass))
            }
            return "Estimate available"
        case .noMyopiaDetectedWithinRange: return "No myopia detected in POC range"
        case .strongerThanSupportedRange: return "Outside POC range"
        case .unreliableMeasurement: return "Repeat needed"
        case .deviceUnsupported: return "Device unsupported"
        case .userIneligible: return "Not suitable"
        }
    }

    private var gaborValue: String {
        guard let gabor, let contrast = gabor.lowestPassedContrast else { return "Repeat needed" }
        return "Detected at \(Int((contrast * 100).rounded()))% contrast"
    }

    static func spokenSummary(eye: Eye, landolt: EyeScreeningResult?, gabor: GaborScreeningResult?) -> String {
        let eyeName = eye.displayName
        let landoltText: String
        if let landolt, landolt.status == .validEstimate,
           let fail = landolt.lastFailDiopter, let pass = landolt.firstPassDiopter {
            landoltText = String(
                format: "%@ eye approximate myopia range, minus %.2f to minus %.2f diopters.",
                eyeName,
                abs(max(fail, pass)),
                abs(min(fail, pass))
            )
        } else if landolt?.status == .noMyopiaDetectedWithinRange {
            landoltText = "\(eyeName) eye showed no myopia within the supported POC range."
        } else if landolt?.status == .strongerThanSupportedRange {
            landoltText = "\(eyeName) eye was outside the supported POC range."
        } else {
            landoltText = "\(eyeName) eye Landolt test needs repeating."
        }

        if let contrast = gabor?.lowestPassedContrast {
            return "\(landoltText) Gabor patterns were detected at \(Int((contrast * 100).rounded())) percent contrast."
        }
        return "\(landoltText) The Gabor check needs repeating."
    }
}

private struct ResultMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(SEENATheme.secondaryInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
