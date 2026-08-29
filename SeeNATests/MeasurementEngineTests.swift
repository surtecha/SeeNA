import XCTest
@testable import SEENACore

final class MeasurementEngineTests: XCTestCase {
    func testDiopterConversionUsesMeasuredDistance() throws {
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 2.0)), -0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 1.0)), -1.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.5)), -2.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.4)), -2.5, accuracy: 0.000_001)
        XCTAssertNil(RefractionEstimator.diopter(forDistanceMetres: 0))
    }

    func testOptotypeGeometryIsPixelAlignedAndNearFiveArcMinutes() throws {
        for distance in [0.4, 0.5, 0.67, 0.8, 1.0, 1.33, 1.5, 2.0] {
            let geometry = try XCTUnwrap(
                OptotypeGeometry.calculate(distanceMetres: distance, pixelsPerInch: 460, displayScale: 3)
            )
            XCTAssertEqual(geometry.pixelHeight % 5, 0)
            XCTAssertEqual(geometry.strokePixels * 5, geometry.pixelHeight)
            XCTAssertEqual(geometry.innerDiameterPixels + geometry.strokePixels * 2, geometry.pixelHeight)
            XCTAssertEqual(geometry.gapPixels, geometry.strokePixels)
            XCTAssertLessThan(abs(geometry.effectiveArcMinutes - 5), 1.3)
        }
    }

    func testOptotypeRejectsSubPixelGeometry() {
        XCTAssertNil(
            OptotypeGeometry.calculate(
                distanceMetres: 0.1,
                pixelsPerInch: 460,
                displayScale: 3,
                minimumPixelHeight: 10
            )
        )
    }

    func testQualityGateRejectsEverySafetyFailure() {
        let sample = sample(
            distance: 1,
            standardDeviation: 0.08,
            tracking: 0.7,
            stable: false,
            drift: 3,
            acceleration: 0.04,
            yaw: 20,
            pitch: 15,
            luminance: 0.05,
            faceCount: 2
        )
        let quality = QualityGateEngine.evaluate(
            sample: sample,
            responseCount: 5,
            audioLevelAdequate: false,
            targetGeometryValid: false,
            orientationChanged: true,
            thresholds: .conservative
        )

        XCTAssertFalse(quality.isValid)
        XCTAssertEqual(
            Set(quality.discardReasons),
            Set([
                .trackingCoverage, .phoneMoved, .headPose, .distanceUnstable,
                .multipleFaces, .poorLighting, .responseCount, .audioLevel,
                .targetGeometry, .orientationChanged
            ])
        )
    }

    func testDirectionScoring() {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down]
        let responses: [OptotypeDirection] = [.up, .right, .down, .left, .up, .left, .right]
        XCTAssertEqual(TrialScorer.correctCount(targets: targets, responses: responses), 5)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 5, hasExactlySevenResponses: true), .pass)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 4, hasExactlySevenResponses: true), .borderline)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 3, hasExactlySevenResponses: true), .fail)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 7, hasExactlySevenResponses: false), .invalid)
    }

    func testFirstCandidatePassRequiresConfirmationAndReturnsBoundaryStatus() {
        var engine = ThresholdSearchEngine(eye: .right)
        let first = block(eye: .right, candidate: -0.5, distance: 2, outcome: .pass)
        XCTAssertEqual(engine.submit(block: first), .test(candidate: .init(diopter: -0.5), stage: .confirmation))

        let confirmation = block(eye: .right, candidate: -0.5, distance: 1.98, outcome: .pass)
        guard case .completed(let result) = engine.submit(block: confirmation) else {
            return XCTFail("Expected completed boundary result")
        }
        XCTAssertEqual(result.status, .noMyopiaDetectedWithinRange)
        XCTAssertNil(result.displayedEstimateDiopter)
    }

    func testNormalBracketFineSearchAndConfirmation() {
        var engine = ThresholdSearchEngine(eye: .left)
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -0.5, distance: 2, outcome: .fail)), .test(candidate: .init(diopter: -1), stage: .coarse))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -1, distance: 1, outcome: .pass)), .test(candidate: .init(diopter: -0.75), stage: .fine))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -0.75, distance: 1.33, outcome: .fail)), .test(candidate: .init(diopter: -1), stage: .confirmation))

        guard case .completed(let result) = engine.submit(block: block(eye: .left, candidate: -1, distance: 0.98, outcome: .pass)) else {
            return XCTFail("Expected valid result")
        }
        XCTAssertEqual(result.status, .validEstimate)
        XCTAssertEqual(result.lastFailDiopter, -0.75)
        XCTAssertEqual(result.firstPassDiopter, -1)
        XCTAssertEqual(try XCTUnwrap(result.displayedEstimateDiopter), -1, accuracy: 0.000_001)
    }

    func testFinalCandidateFailRequiresConfirmationAndReturnsStrongBoundary() {
        var engine = ThresholdSearchEngine(eye: .right)
        for candidate in ThresholdSearchEngine.coarseCandidates {
            _ = engine.submit(block: block(eye: .right, candidate: candidate, distance: 1 / abs(candidate), outcome: .fail))
        }
        guard case .completed(let result) = engine.submit(block: block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .fail)) else {
            return XCTFail("Expected completed strong-boundary result")
        }
        XCTAssertEqual(result.status, .strongerThanSupportedRange)
        XCTAssertNil(result.displayedEstimateDiopter)
    }

    func testBorderlineRepeatsOnceThenReturnsUnreliable() {
        var engine = ThresholdSearchEngine(eye: .right)
        let borderline = block(eye: .right, candidate: -0.5, distance: 2, outcome: .borderline)
        XCTAssertEqual(engine.submit(block: borderline), .test(candidate: .init(diopter: -0.5), stage: .coarse))
        guard case .completed(let result) = engine.submit(block: borderline) else {
            return XCTFail("Expected unreliable result")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
    }

    func testCalibrationAcceptanceRequiresAllDistancesAndEnoughAccuracy() throws {
        let required = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]
        let observations = required.flatMap { distance in
            (0..<150).map { index in
                CalibrationObservation(
                    groundTruthMetres: distance,
                    rawDistanceMetres: (distance + 0.008) / 1.018 + Double(index % 3 - 1) * 0.001
                )
            }
        }
        let fit = try XCTUnwrap(CalibrationFitter.affineFit(observations: observations))
        XCTAssertTrue(CalibrationFitter.passesAcceptance(observations: observations, fit: fit))
    }

    func testWordAccuracyUsesEditDistance() {
        XCTAssertEqual(
            ReadabilityEngine.wordAccuracy(
                reference: "The bus arrives near the library at ten.",
                transcript: "the bus arrives near library at ten"
            ),
            0.875,
            accuracy: 0.000_001
        )
    }

    func testAccessibilityProfileIsLocalAndDeterministic() {
        let profile = AccessibilityProfileEngine.makeProfile(
            from: AccessibilityAssessmentAnswers(
                minimumReadablePointSize: 24,
                comfortablePointSize: 34,
                prefersHighContrast: true,
                prefersLargeControls: false,
                prefersReadAloud: true,
                prefersSimplifiedContent: false,
                preferredLanguage: "en-AU"
            )
        )
        XCTAssertEqual(profile.minimumReadablePointSize, 24)
        XCTAssertEqual(profile.comfortablePointSize, 34)
        XCTAssertEqual(profile.recommendedDynamicType, .accessibility1)
        XCTAssertTrue(profile.highContrastEnabled)
        XCTAssertFalse(profile.largeControlsEnabled)
        XCTAssertTrue(profile.readAloudEnabled)
        XCTAssertFalse(profile.simplifiedContentEnabled)
    }

    private func block(eye: Eye, candidate: Double, distance: Double, outcome: TrialOutcome) -> TrialBlock {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down]
        let responses = outcome == .pass ? targets : Array(repeating: OptotypeDirection.left, count: 7)
        return TrialBlock(
            eye: eye,
            candidateDiopter: candidate,
            targetDistanceMetres: 1 / abs(candidate),
            actualMedianDistanceMetres: distance,
            distanceStandardDeviation: 0.008,
            targets: targets,
            responses: responses,
            correctCount: outcome == .pass ? 7 : outcome == .borderline ? 4 : 2,
            outcome: outcome,
            quality: BlockQuality(
                trackingCoverage: 0.98,
                phoneStable: true,
                headPoseValid: true,
                distanceStable: true,
                audioLevelAdequate: true,
                targetGeometryValid: true,
                discardReasons: []
            ),
            responseSource: .voice,
            transcript: nil
        )
    }

    private func sample(
        distance: Double,
        standardDeviation: Double,
        tracking: Double,
        stable: Bool,
        drift: Double,
        acceleration: Double,
        yaw: Double,
        pitch: Double,
        luminance: Double,
        faceCount: Int
    ) -> DistanceSample {
        DistanceSample(
            rawARDistanceMetres: distance,
            relativeScaleDistanceMetres: distance,
            fusedDistanceMetres: distance,
            correctedDistanceMetres: distance,
            distanceStandardDeviation: standardDeviation,
            trackingCoverage: tracking,
            phoneStable: stable,
            attitudeDriftDegrees: drift,
            accelerationRMS: acceleration,
            headYawDegrees: yaw,
            headPitchDegrees: pitch,
            luminance: luminance,
            faceCount: faceCount,
            interEyePixels: 200
        )
    }
}
