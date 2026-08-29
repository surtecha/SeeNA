#if DEBUG
import SwiftUI

struct DeviceCalibrationHarnessView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var observations: [CalibrationObservation] = []
    @State private var targetIndex = 0
    @State private var isCollecting = false
    @State private var resultMessage = ""

    private let targets = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]

    var body: some View {
        NavigationStack {
            ScreenScaffold(
                title: "Physical distance calibration",
                subtitle: "Engineering tool. Use a tape measure from the screen plane to the participant’s eye plane. Collect exactly one position at a time."
            ) {
                Text(targetIndex < targets.count ? String(format: "Target %.2f m", targets[targetIndex]) : "All positions collected")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)

                StatusRow(
                    title: "Samples",
                    detail: "\(observations.count) / \(targets.count * 150)",
                    state: observations.count == targets.count * 150 ? .ready : .warning
                )

                if targetIndex < targets.count {
                    Button(isCollecting ? "Collecting 150 samples…" : "Collect at tape mark") {
                        Task { await collect() }
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(isCollecting)
                } else {
                    Button("Save distance-only calibration") { finish() }
                        .buttonStyle(PrimaryActionStyle())
                }

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.body.weight(.semibold))
                        .foregroundColor(SEENATheme.secondaryInk)
                }

                Text("Distance-fit acceptance: median error ≤3 cm below 1 m and ≤5% at/above 1 m, with 150 samples at all eight distances. This tool cannot validate display rasterisation or clinical performance, so numeric output remains locked.")
                    .font(.footnote)
                    .foregroundColor(SEENATheme.secondaryInk)
            }
            .navigationTitle("Device calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { dependencies.sensorCoordinator.start() }
        }
    }

    @MainActor
    private func collect() async {
        guard targetIndex < targets.count else { return }
        isCollecting = true
        defer { isCollecting = false }
        let groundTruth = targets[targetIndex]
        var captured: [CalibrationObservation] = []
        var lastTimestamp: Date?
        let deadline = Date().addingTimeInterval(12)

        while captured.count < 150, Date() < deadline {
            if let sample = dependencies.sensorCoordinator.latestSample,
               sample.timestamp != lastTimestamp,
               sample.faceCount == 1,
               sample.phoneStable,
               abs(sample.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees,
               abs(sample.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees,
               sample.luminance >= 0.12,
               let raw = sample.fusedDistanceMetres {
                captured.append(.init(groundTruthMetres: groundTruth, rawDistanceMetres: raw))
                lastTimestamp = sample.timestamp
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        guard captured.count == 150 else {
            resultMessage = "Only \(captured.count) valid samples were captured. Stabilise the phone and repeat this position."
            return
        }
        observations.append(contentsOf: captured)
        targetIndex += 1
        resultMessage = "Position accepted. Move the eye plane to the next tape mark."
    }

    private func finish() {
        guard let candidate = dependencies.profileRegistry.profile(),
              let fit = CalibrationFitter.affineFit(observations: observations),
              CalibrationFitter.passesAcceptance(observations: observations, fit: fit) else {
            resultMessage = "Calibration failed acceptance. No numeric screening profile was enabled."
            return
        }

        let below = observations.filter { $0.groundTruthMetres < 1 }
        let above = observations.filter { $0.groundTruthMetres >= 1 }
        let belowError = maximumMedianAbsoluteError(below, fit: fit)
        let abovePercentage = maximumMedianPercentageError(above, fit: fit)
        let distanceCalibrated = DeviceProfile(
            schemaVersion: candidate.schemaVersion,
            profileVersion: candidate.profileVersion + 1,
            hardwareIdentifiers: candidate.hardwareIdentifiers,
            marketingFamily: candidate.marketingFamily,
            variant: candidate.variant,
            nativePixelWidth: candidate.nativePixelWidth,
            nativePixelHeight: candidate.nativePixelHeight,
            displayScale: candidate.displayScale,
            pixelsPerInch: candidate.pixelsPerInch,
            expectedCameraType: candidate.expectedCameraType,
            calibration: DistanceCalibration(
                scale: fit.scale,
                offsetMetres: fit.offsetMetres,
                baselineDistanceMetres: 0.40,
                validatedDistancesMetres: targets
            ),
            qualityThresholds: candidate.qualityThresholds,
            minimumValidatedDistance: 0.40,
            maximumValidatedDistance: 2.00,
            validationEvidence: ValidationSummary(
                sampleCount: observations.count,
                maximumMedianErrorBelowOneMetre: belowError,
                maximumMedianPercentageErrorAtOrAboveOneMetre: abovePercentage,
                validatedAt: Date(),
                notes: "Distance-only evidence from eight tape-measured distances; 150 valid samples per distance. This does not validate display rasterisation or clinical performance."
            ),
            displayRasterValidation: nil,
            clinicalValidationEvidence: nil,
            isValidated: false
        )

        do {
            try dependencies.profileRegistry.persistDistanceCalibratedProfile(distanceCalibrated)
            resultMessage = String(format: "Distance fit saved: %.5fx %+.5f m; near median error %.3f m; far median error %.2f%%. Numeric output remains locked until independent display and clinical validation exist.", fit.scale, fit.offsetMetres, belowError, abovePercentage * 100)
        } catch {
            resultMessage = "The distance-only calibration could not be saved. Numeric output remains locked."
        }
    }

    private func maximumMedianAbsoluteError(_ values: [CalibrationObservation], fit: CalibrationFit) -> Double {
        Dictionary(grouping: values, by: \.groundTruthMetres).values.map { group in
            Statistics.median(group.map { abs($0.groundTruthMetres - (fit.scale * $0.rawDistanceMetres + fit.offsetMetres)) }) ?? .infinity
        }.max() ?? .infinity
    }

    private func maximumMedianPercentageError(_ values: [CalibrationObservation], fit: CalibrationFit) -> Double {
        Dictionary(grouping: values, by: \.groundTruthMetres).values.map { group in
            Statistics.median(group.map { abs($0.groundTruthMetres - (fit.scale * $0.rawDistanceMetres + fit.offsetMetres)) / $0.groundTruthMetres }) ?? .infinity
        }.max() ?? .infinity
    }
}
#endif
