import XCTest
@testable import SEENACore

final class ResultIntegrityValidatorTests: XCTestCase {
    func testAcceptsEngineCompatibleValidEstimate() {
        let validation = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -2.0,
                firstPass: -2.25,
                displayed: -2.25,
                distance: 0.44,
                uncertainty: 0.02,
                repeatability: 0.05
            )
        )

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.issues, [])
    }

    func testRejectsEstimateThatDoesNotMatchFarPointMathOrQuarterRounding() {
        let validation = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -2.0,
                firstPass: -2.25,
                displayed: -2.10,
                distance: 0.44,
                uncertainty: 0.02,
                repeatability: 0.05
            )
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.farPointMismatch, .nonQuarterDiopter])
    }

    func testRejectsReversedOrOverwideBracket() {
        let reversed = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -2.25,
                firstPass: -2.0,
                displayed: -2.25,
                distance: 0.44,
                uncertainty: 0,
                repeatability: 0
            )
        )
        let overwide = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -1.50,
                firstPass: -2.0,
                displayed: -2.25,
                distance: 0.44,
                uncertainty: 0,
                repeatability: 0
            )
        )

        XCTAssertEqual(reversed.issues, [.invalidBracketOrdering])
        XCTAssertEqual(overwide.issues, [.invalidBracketWidth])
    }

    func testRejectsFarPointOutsideClaimedBracketAndImpreciseEstimate() {
        let validation = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -2.0,
                firstPass: -2.25,
                displayed: -2.5,
                distance: 0.4,
                uncertainty: 0.3,
                repeatability: 0.3
            )
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(
            validation.issues,
            [.displayedOutsideBracket, .repeatabilityExceedsBracket, .uncertaintyExceedsBracket]
        )
    }

    func testRejectsUncertaintyAboveTheActiveProfileQualityLimit() {
        let screeningResult = result(
            status: .validEstimate,
            lastFail: -2.0,
            firstPass: -2.25,
            displayed: -2.25,
            distance: 0.44,
            uncertainty: 0.20,
            repeatability: 0.01
        )

        let validation = ResultIntegrityValidator.validate(
            screeningResult,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                trial(candidate: -2.25, distance: 0.445, outcome: .pass),
                trial(candidate: -2.25, distance: 0.44, outcome: .pass)
            ],
            profile: profile()
        )

        XCTAssertEqual(validation.issues, [.uncertaintyExceedsProfile])
    }

    func testRejectsInvalidMeasuredValues() {
        let validation = ResultIntegrityValidator.validate(
            result(
                status: .validEstimate,
                lastFail: -.infinity,
                firstPass: -2.25,
                displayed: -2.25,
                distance: .nan,
                uncertainty: -.infinity,
                repeatability: -0.1
            )
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(
            validation.issues,
            [.negativeRepeatability, .nonFiniteDiopter, .nonFiniteDistance, .nonFiniteUncertainty]
        )
    }

    func testAcceptsEngineCompatibleBoundaryAndUnreliableResults() {
        let noMyopia = ResultIntegrityValidator.validate(
            result(
                status: .noMyopiaDetectedWithinRange,
                lastFail: nil,
                firstPass: -0.5,
                displayed: nil,
                distance: 1.98,
                uncertainty: 0.01,
                repeatability: 0
            )
        )
        let strong = ResultIntegrityValidator.validate(
            result(
                status: .strongerThanSupportedRange,
                lastFail: -2.5,
                firstPass: nil,
                displayed: nil,
                distance: 0.4,
                uncertainty: 0.01,
                repeatability: 0
            )
        )
        let unreliable = ResultIntegrityValidator.validate(
            result(
                status: .unreliableMeasurement,
                lastFail: nil,
                firstPass: nil,
                displayed: nil,
                distance: nil,
                uncertainty: nil,
                repeatability: nil,
                tracking: .poor,
                response: .poor
            )
        )

        XCTAssertTrue(noMyopia.isValid)
        XCTAssertTrue(strong.isValid)
        XCTAssertTrue(unreliable.isValid)
    }

    func testRejectsIncompatibleStatusPayload() {
        let validation = ResultIntegrityValidator.validate(
            result(
                status: .deviceUnsupported,
                lastFail: nil,
                firstPass: nil,
                displayed: nil,
                distance: 0.5,
                uncertainty: nil,
                repeatability: nil,
                tracking: .poor,
                response: .poor
            )
        )

        XCTAssertEqual(validation.issues, [.invalidUnavailableQuality, .unexpectedValueForStatus])
    }

    func testTrialAwareValidationAcceptsCompatibleConfirmationWitnesses() {
        let screeningResult = result(
            status: .validEstimate,
            lastFail: -2.0,
            firstPass: -2.25,
            displayed: -2.25,
            distance: 0.44,
            uncertainty: 0.02,
            repeatability: 0.01
        )

        let validation = ResultIntegrityValidator.validate(
            screeningResult,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                trial(candidate: -2.25, distance: 0.445, outcome: .pass),
                trial(candidate: -2.25, distance: 0.44, outcome: .pass)
            ]
        )

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.issues, [])
    }

    func testTrialAwareValidationRejectsMissingAndMalformedSupportingWitnesses() {
        let screeningResult = result(
            status: .validEstimate,
            lastFail: -2.0,
            firstPass: -2.25,
            displayed: -2.25,
            distance: 0.44,
            uncertainty: 0.02,
            repeatability: 0.01
        )
        let malformedPass = trial(candidate: -2.25, distance: 0.44, outcome: .pass, responses: Array(repeating: .left, count: 7), correctCount: 7)

        let validation = ResultIntegrityValidator.validate(
            screeningResult,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                malformedPass
            ]
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.malformedSupportingEvidence, .missingSupportingEvidence])
    }

    func testTrialAwareValidationRejectsWitnessWithWrongCandidateTargetDistance() {
        let screeningResult = result(
            status: .validEstimate,
            lastFail: -2.0,
            firstPass: -2.25,
            displayed: -2.25,
            distance: 0.44,
            uncertainty: 0.02,
            repeatability: 0.01
        )
        let validation = ResultIntegrityValidator.validate(
            screeningResult,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                trial(candidate: -2.25, distance: 0.445, outcome: .pass),
                trial(candidate: -2.25, distance: 0.44, outcome: .pass, targetDistance: 0.50)
            ]
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.malformedSupportingEvidence, .missingSupportingEvidence])
    }

    func testTrialAwareQualitativeBoundariesRequireMatchingWitnesses() {
        let farthest = NumericResultEligibility.sanitize(
            result(
                status: .noMyopiaDetectedWithinRange,
                lastFail: nil,
                firstPass: -0.5,
                displayed: nil,
                distance: 1.98,
                uncertainty: 0.01,
                repeatability: 0
            ),
            numericResultsAllowed: false
        )
        let adverse = NumericResultEligibility.sanitize(
            result(
                status: .strongerThanSupportedRange,
                lastFail: -2.5,
                firstPass: nil,
                displayed: nil,
                distance: 0.4,
                uncertainty: 0.01,
                repeatability: 0
            ),
            numericResultsAllowed: false
        )

        XCTAssertTrue(
            ResultIntegrityValidator.validate(
                farthest,
                against: [
                    trial(candidate: -0.5, distance: 1.99, outcome: .pass),
                    trial(candidate: -0.5, distance: 1.98, outcome: .pass)
                ]
            ).isValid
        )
        XCTAssertTrue(
            ResultIntegrityValidator.validate(
                adverse,
                against: [
                    trial(candidate: -2.5, distance: 0.40, outcome: .fail),
                    trial(candidate: -2.5, distance: 0.405, outcome: .fail)
                ]
            ).isValid
        )
        XCTAssertEqual(
            ResultIntegrityValidator.validate(farthest, against: []).issues,
            [.missingSupportingEvidence]
        )
        XCTAssertEqual(
            ResultIntegrityValidator.validate(adverse, against: []).issues,
            [.missingSupportingEvidence]
        )
    }

    func testTrialAwareQualitativeThresholdRequiresTwoPassesAndAdjacentFail() {
        let qualitative = NumericResultEligibility.sanitize(
            result(
                status: .validEstimate,
                lastFail: -2.0,
                firstPass: -2.25,
                displayed: -2.25,
                distance: 0.44,
                uncertainty: 0.02,
                repeatability: 0.01
            ),
            numericResultsAllowed: false
        )

        let valid = ResultIntegrityValidator.validate(
            qualitative,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                trial(candidate: -2.25, distance: 0.445, outcome: .pass),
                trial(candidate: -2.25, distance: 0.44, outcome: .pass)
            ]
        )
        let missingConfirmation = ResultIntegrityValidator.validate(
            qualitative,
            against: [
                trial(candidate: -2.0, distance: 0.50, outcome: .fail),
                trial(candidate: -2.25, distance: 0.44, outcome: .pass)
            ]
        )

        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(missingConfirmation.issues, [.missingSupportingEvidence])
    }

    private func result(
        status: ScreeningStatus,
        lastFail: Double?,
        firstPass: Double?,
        displayed: Double?,
        distance: Double?,
        uncertainty: Double?,
        repeatability: Double?,
        tracking: QualityLabel = .good,
        response: QualityLabel = .good
    ) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: .right,
            status: status,
            lastFailDiopter: lastFail,
            firstPassDiopter: firstPass,
            displayedEstimateDiopter: displayed,
            thresholdDistanceMetres: distance,
            sensorUncertaintyDiopter: uncertainty,
            repeatabilityDiopter: repeatability,
            trackingQuality: tracking,
            responseConsistency: response,
            warnings: [.researchPrototype, .notPrescription]
        )
    }

    private func trial(
        candidate: Double,
        distance: Double,
        outcome: TrialOutcome,
        responses: [OptotypeResponse]? = nil,
        correctCount: Int? = nil,
        targetDistance: Double? = nil
    ) -> TrialBlock {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down]
        let actualResponses = responses ?? (outcome == .pass ? targets.map(OptotypeResponse.init) : Array(repeating: .left, count: 7))
        let actualCorrectCount = correctCount ?? zip(targets, actualResponses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }
        return TrialBlock(
            eye: .right,
            candidateDiopter: candidate,
            targetDistanceMetres: targetDistance ?? 1 / abs(candidate),
            actualMedianDistanceMetres: distance,
            distanceStandardDeviation: 0.008,
            targets: targets,
            responses: actualResponses,
            correctCount: actualCorrectCount,
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

    private func profile() -> DeviceProfile {
        DeviceProfile(
            schemaVersion: 1,
            profileVersion: 1,
            hardwareIdentifiers: ["test-device"],
            marketingFamily: "Test Phone",
            variant: "Test",
            nativePixelWidth: 1_080,
            nativePixelHeight: 2_340,
            displayScale: 3,
            pixelsPerInch: 460,
            expectedCameraType: .trueDepth,
            calibration: DistanceCalibration(
                scale: 1,
                offsetMetres: 0,
                baselineDistanceMetres: 0.4,
                validatedDistancesMetres: [0.4, 0.5, 2]
            ),
            qualityThresholds: .conservative,
            minimumValidatedDistance: 0.4,
            maximumValidatedDistance: 2,
            validationEvidence: .notValidated,
            isValidated: true
        )
    }
}
