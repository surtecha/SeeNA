import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var didStart = false

    var body: some View {
        VStack(spacing: 22) {
            ProgressView().scaleEffect(1.6)
            Text("Preparing your screening")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text("Measurements and accessibility settings are calculated locally. AI supplies explanatory wording only.")
                .font(.title3)
                .foregroundColor(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SEENATheme.background.ignoresSafeArea())
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
            locale: session.accessibilityProfile?.preferredLanguage ?? "en-AU",
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
        if results.isEmpty { return "accessibility_only" }
        if results.contains(where: { $0.status == .unreliableMeasurement }) { return "no_reliable_result" }
        if results.contains(where: { $0.status == .validEstimate || $0.status == .strongerThanSupportedRange }) {
            return "professional_exam_recommended"
        }
        return "routine_exam_recommended"
    }

    private var localComparison: String {
        guard let right = session.activeSession.rightEyeResult,
              let left = session.activeSession.leftEyeResult else {
            return "Numeric screening was not completed for both eyes."
        }
        guard let rightValue = right.displayedEstimateDiopter,
              let leftValue = left.displayedEstimateDiopter else {
            return "Review each eye separately because at least one eye returned a boundary or no-result status."
        }
        return abs(rightValue - leftValue) >= 0.75
            ? "The eyes produced meaningfully different screening estimates."
            : "The two eye screening estimates were broadly similar."
    }

    static func fallbackExplanation(for request: ExplanationRequest) -> ExplanationResponse {
        let isUnreliable = request.actionCode == "no_reliable_result" || request.actionCode == "accessibility_only"
        return ExplanationResponse(
            headline: isUnreliable ? "No reliable numeric screening result was obtained." : "Your SeeNA screening is ready to review.",
            plainMeaning: request.comparison,
            limitations: [
                "This research prototype is not an eyeglass prescription.",
                "It does not assess hyperopia, astigmatism or eye disease.",
                "SeeNA v0 has not undergone clinical validation."
            ],
            nextSteps: ["Arrange a complete professional eye examination when accessible."],
            disclaimer: "Research prototype only — not a diagnosis or prescription.",
            usedFallback: true
        )
    }
}

struct ResultsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ScreenScaffold(
            title: "SeeNA screening result",
            subtitle: session.cachedExplanation?.headline ?? "Review the locally calculated result and its limitations."
        ) {
            if let right = session.activeSession.rightEyeResult {
                EyeResultCard(result: right)
            }
            if let left = session.activeSession.leftEyeResult {
                EyeResultCard(result: left)
            }
            if session.activeSession.rightEyeResult == nil && session.activeSession.leftEyeResult == nil {
                StatusRow(
                    title: "Accessibility-only session",
                    detail: "No eye-power number was produced because numeric screening was unavailable or not suitable.",
                    state: .warning
                )
            }

            if let explanation = session.cachedExplanation {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Plain interpretation").font(.title2.bold())
                    Text(explanation.plainMeaning).font(.title3)
                    ForEach(explanation.nextSteps, id: \.self) { step in Label(step, systemImage: "arrow.right.circle.fill") }
                    Divider()
                    ForEach(explanation.limitations, id: \.self) { limitation in
                        Label(limitation, systemImage: "exclamationmark.triangle")
                            .foregroundColor(SEENATheme.secondaryInk)
                    }
                    Text(explanation.disclaimer).font(.footnote.bold())
                    if explanation.usedFallback == true {
                        Text("Built-in deterministic wording was used because the explanation service was unavailable.")
                            .font(.caption)
                            .foregroundColor(SEENATheme.secondaryInk)
                    }
                }
                .padding(20)
                .background(SEENATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            if let profile = session.accessibilityProfile {
                AccessibilityProfileCard(profile: profile)
            }

            Button("View measurement evidence") { session.navigate(to: .evidence) }
                .buttonStyle(PrimaryActionStyle())
            if session.accessibilityProfile != nil {
                Button("Open transformed service demo") { session.navigate(to: .accessibleDemo) }
                    .buttonStyle(SecondaryActionStyle())
            }
            ShareLink(item: shareText) {
                Label("Share text summary", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle())
            Button("Delete this local session", role: .destructive) { session.navigate(to: .deletionConfirmation) }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            Button("Start a new session") { session.startNewSession() }
                .buttonStyle(SecondaryActionStyle())
        }
        .navigationBarBackButtonHidden()
        .onAppear { dependencies.brightness.restore() }
    }

    private var shareText: String {
        var lines = ["SeeNA research-prototype screening — not a prescription."]
        for result in [session.activeSession.rightEyeResult, session.activeSession.leftEyeResult].compactMap({ $0 }) {
            lines.append("\(result.eye.displayName) eye: \(EyeResultCard.summary(for: result))")
        }
        lines.append("A complete professional eye examination is recommended when accessible.")
        return lines.joined(separator: "\n")
    }
}

struct EyeResultCard: View {
    let result: EyeScreeningResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(result.eye.displayName) eye").font(.title2.bold())
                Spacer()
                QualityPill(label: result.trackingQuality)
            }
            Text(Self.summary(for: result))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(result.status == .validEstimate ? SEENATheme.teal : SEENATheme.warning)
            if let distance = result.thresholdDistanceMetres {
                Text(String(format: "Measured threshold distance %.2f m", distance))
            }
            if let uncertainty = result.sensorUncertaintyDiopter {
                Text(String(format: "Sensor contribution approximately ±%.2f D", uncertainty))
            }
            if let repeatability = result.repeatabilityDiopter {
                Text(String(format: "Within-test repeatability spread %.2f D", repeatability))
            }
            Text("Human response and clinical uncertainty are not included in the sensor contribution.")
                .font(.caption)
                .foregroundColor(SEENATheme.secondaryInk)
        }
        .padding(20)
        .background(SEENATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    static func summary(for result: EyeScreeningResult) -> String {
        switch result.status {
        case .validEstimate:
            if let fail = result.lastFailDiopter, let pass = result.firstPassDiopter {
                let weaker = max(fail, pass)
                let stronger = min(fail, pass)
                return String(format: "Approximate myopia screening range %.2f D to %.2f D", weaker, stronger)
            }
            return "Approximate myopia screening estimate available"
        case .noMyopiaDetectedWithinRange:
            return "No significant myopia detected within −0.50 D to −2.50 D; normal refraction, weaker myopia and hyperopia cannot be distinguished."
        case .strongerThanSupportedRange:
            return "Outside the supported range; stronger myopia, another visual limitation or an unreliable test is possible."
        case .unreliableMeasurement:
            return "No reliable numeric result"
        case .deviceUnsupported:
            return "Numeric screening unsupported on this device"
        case .userIneligible:
            return "Numeric screening was not suitable"
        }
    }
}

private struct QualityPill: View {
    let label: QualityLabel
    var body: some View {
        Text(label.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(label == .good ? SEENATheme.teal : SEENATheme.warning)
            .background((label == .good ? SEENATheme.teal : SEENATheme.warning).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct AccessibilityProfileCard: View {
    let profile: AccessibilityProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your local accessibility profile").font(.title2.bold())
            profileRow("Comfortable text", "\(Int(profile.comfortablePointSize)) pt")
            profileRow("Dynamic Type", profile.recommendedDynamicType.displayName)
            profileRow("Contrast", profile.highContrastEnabled ? "High" : "Standard")
            profileRow("Controls", profile.largeControlsEnabled ? "Large" : "Standard")
            profileRow("Line spacing", profile.increasedLineSpacing ? "Increased" : "Standard")
            profileRow("Read aloud", profile.readAloudEnabled ? "Enabled" : "Off")
            profileRow("Simplified content", profile.simplifiedContentEnabled ? "Enabled" : "Off")
        }
        .padding(20)
        .background(SEENATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.bold) }
            .accessibilityElement(children: .combine)
    }
}

private extension DynamicTypeRecommendation {
    var displayName: String {
        switch self {
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .extraExtraLarge: return "XX Large"
        case .extraExtraExtraLarge: return "XXX Large"
        case .accessibility1: return "Accessibility 1"
        case .accessibility2: return "Accessibility 2"
        case .accessibility3: return "Accessibility 3"
        }
    }
}
