import SwiftUI

struct EvidenceView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            title: "Measurement evidence",
            subtitle: "These values come from local sensors, deterministic scoring and stored trial records. AI does not create any measurement below."
        ) {
            if let profile = session.activeSession.deviceProfile {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device profile").font(.title2.bold())
                    evidenceRow("Model", "\(profile.marketingFamily) \(profile.variant)")
                    evidenceRow("Profile version", "\(profile.profileVersion)")
                    evidenceRow("Display", String(format: "%d ppi / scale %.1f", Int(profile.pixelsPerInch), profile.displayScale))
                    evidenceRow("Calibration samples", "\(profile.validationEvidence.sampleCount)")
                    evidenceRow("Validated range", String(format: "%.2f–%.2f m", profile.minimumValidatedDistance, profile.maximumValidatedDistance))
                }
                .evidenceCard()
            }

            if let sample = session.sensorState {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest live sample").font(.title2.bold())
                    evidenceRow("Raw ARKit", formatMetres(sample.rawARDistanceMetres))
                    evidenceRow("Relative scale", formatMetres(sample.relativeScaleDistanceMetres))
                    evidenceRow("Fused", formatMetres(sample.fusedDistanceMetres))
                    evidenceRow("Corrected", formatMetres(sample.correctedDistanceMetres))
                    evidenceRow("Distance SD", formatMetres(sample.distanceStandardDeviation))
                    evidenceRow("Tracking", String(format: "%.1f%%", sample.trackingCoverage * 100))
                    evidenceRow("Phone drift", String(format: "%.2f°", sample.attitudeDriftDegrees))
                    evidenceRow("Head yaw / pitch", String(format: "%.1f° / %.1f°", sample.headYawDegrees, sample.headPitchDegrees))
                }
                .evidenceCard()
            }

            trials(title: "Right eye", values: session.activeSession.rightEyeTrials)
            trials(title: "Left eye", values: session.activeSession.leftEyeTrials)
            gaborTrials(title: "Right eye Gabor", values: session.activeSession.rightGaborTrials ?? [])
            gaborTrials(title: "Left eye Gabor", values: session.activeSession.leftGaborTrials ?? [])

            VStack(alignment: .leading, spacing: 8) {
                Text("Calculation").font(.title2.bold())
                Text("D = −1 ÷ measured median distance in metres")
                    .font(.system(.body, design: .monospaced))
                Text("Candidate positions guide movement only. The displayed estimate is calculated from the measured distance and rounded locally to 0.25 D.")
                Text("SeeNA v0 has not undergone clinical validation.")
                    .fontWeight(.bold)
            }
            .evidenceCard()
        }
        .navigationTitle("Evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func gaborTrials(title: String, values: [GaborTrial]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.title2.bold())
                ForEach(Array(values.enumerated()), id: \.element.id) { index, trial in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Block \(index + 1) — \(trial.outcome.rawValue.capitalized)").font(.headline)
                        evidenceRow("Contrast", "\(Int((trial.contrast * 100).rounded()))%")
                        evidenceRow("Targets", trial.targets.map { $0.rawValue.prefix(1).uppercased() }.joined(separator: " "))
                        evidenceRow("Responses", trial.responses.map { $0.rawValue.prefix(1).uppercased() }.joined(separator: " "))
                        evidenceRow("Score", "\(trial.correctCount)/7")
                    }
                    if index < values.count - 1 { Divider() }
                }
            }
            .evidenceCard()
        }
    }

    @ViewBuilder
    private func trials(title: String, values: [TrialBlock]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2.bold())
                ForEach(Array(values.enumerated()), id: \.element.id) { index, trial in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Block \(index + 1) — \(trial.outcome.rawValue.capitalized)").font(.headline)
                        evidenceRow("Candidate", String(format: "%.2f D / %.2f m", trial.candidateDiopter, trial.targetDistanceMetres))
                        evidenceRow("Actual median", String(format: "%.3f m", trial.actualMedianDistanceMetres))
                        evidenceRow("Targets", shortDirections(trial.targets))
                        evidenceRow("Responses", shortDirections(trial.responses))
                        evidenceRow("Score", "\(trial.correctCount)/7")
                        evidenceRow("Source", trial.responseSource.rawValue)
                        evidenceRow("Quality", trial.quality.isValid ? "Valid" : trial.quality.discardReasons.map(\.rawValue).joined(separator: ", "))
                        if let profile = session.activeSession.deviceProfile,
                           let geometry = OptotypeGeometry.calculate(
                            distanceMetres: trial.actualMedianDistanceMetres,
                            pixelsPerInch: profile.pixelsPerInch,
                            displayScale: profile.displayScale
                           ) {
                            evidenceRow("Target", String(format: "%d px / %.2f arcmin", geometry.pixelHeight, geometry.effectiveArcMinutes))
                        }
                    }
                    if index < values.count - 1 { Divider() }
                }
            }
            .evidenceCard()
        }
    }

    private func evidenceRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundColor(SEENATheme.secondaryInk)
            Spacer(minLength: 12)
            Text(value).font(.system(.body, design: .monospaced, weight: .semibold)).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func formatMetres(_ value: Double?) -> String { value.map { String(format: "%.3f m", $0) } ?? "—" }
    private func shortDirections(_ values: [OptotypeDirection]) -> String {
        values.map { $0.rawValue.prefix(1).uppercased() }.joined(separator: " ")
    }
}

private extension View {
    func evidenceCard() -> some View {
        padding(20)
            .background(SEENATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
