import XCTest
@testable import SEENACore

/// Independent reference cases and boundary sweeps for the dimensional math.
/// These tests prove internal arithmetic and fail-closed behavior; they do not
/// claim that the current visual-response protocol is a clinically valid
/// refraction method.
final class MathematicalSafetyOracleTests: XCTestCase {
    func testFiveArcMinuteGeometryMatchesHandCalculatedOneMetreReference() throws {
        // theta = (5 / 60) degrees = 0.0014544410433286077 radians
        // h = 2 * 1 m * tan(theta / 2) = 0.0014544412997222254 m
        // pixels = h / 0.0254 m/in * 460 px/in = 26.34027550678046 px
        let height = try XCTUnwrap(VisualAngleGeometry.physicalHeightMetres(
            forArcMinutes: 5,
            atDistanceMetres: 1
        ))
        let pixels = try XCTUnwrap(VisualAngleGeometry.pixels(
            forPhysicalHeightMetres: height,
            pixelsPerInch: 460
        ))
        let geometry = try XCTUnwrap(OptotypeGeometry.calculate(
            distanceMetres: 1,
            pixelsPerInch: 460,
            displayScale: 3,
            presentationMode: .clinicalFiveArcMinute
        ))

        XCTAssertEqual(height, 0.0014544412997222254, accuracy: 1e-15)
        XCTAssertEqual(pixels, 26.34027550678046, accuracy: 1e-12)
        XCTAssertEqual(geometry.pixelHeight, 25)
        XCTAssertEqual(geometry.pointHeight, 25.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(geometry.effectiveArcMinutes, 4.745584462593461, accuracy: 1e-12)
    }

    func testVisualAngleGeometryRoundTripsAcrossSupportedDistances() throws {
        for distanceIndex in 40...200 {
            let distance = Double(distanceIndex) / 100
            for angle in [1.0, 5.0, 30.0, 96.0, 180.0] {
                let height = try XCTUnwrap(VisualAngleGeometry.physicalHeightMetres(
                    forArcMinutes: angle,
                    atDistanceMetres: distance
                ))
                let recovered = try XCTUnwrap(VisualAngleGeometry.arcMinutes(
                    forPhysicalHeightMetres: height,
                    atDistanceMetres: distance
                ))
                XCTAssertEqual(recovered, angle, accuracy: 1e-10)
            }
        }
    }

    func testPixelAndPointGeometryRoundTripsAndPreservesLandoltProportions() throws {
        // The supported iPhone 14-and-newer profiles use the 458/460 ppi
        // display families. Lower-density legacy panels can correctly fail the
        // minimum-raster gate for a five-arcminute target at 40 cm.
        for ppi in [458.0, 460.0] {
            for scale in [2.0, 3.0] {
                for distance in NumericResultEligibility.requiredCalibrationDistances {
                    let presented = try XCTUnwrap(PresentedOptotypeGeometry.calculate(
                        distanceMetres: distance,
                        pixelsPerInch: ppi,
                        nativeScale: scale,
                        presentationMode: .clinicalFiveArcMinute
                    ))
                    let geometry = presented.geometry
                    let recovered = try XCTUnwrap(presented.computedArcMinutes(at: distance))

                    XCTAssertEqual(geometry.pixelHeight % 5, 0)
                    XCTAssertEqual(geometry.strokePixels * 5, geometry.pixelHeight)
                    XCTAssertEqual(geometry.gapPixels, geometry.strokePixels)
                    XCTAssertEqual(
                        geometry.innerDiameterPixels + 2 * geometry.strokePixels,
                        geometry.pixelHeight
                    )
                    XCTAssertEqual(geometry.pointHeight * scale, Double(geometry.pixelHeight), accuracy: 1e-12)
                    XCTAssertEqual(recovered, geometry.effectiveArcMinutes, accuracy: 1e-12)
                }
            }
        }
    }

    func testGeometryRejectsEveryNonFiniteOrImpossibleDomainValue() {
        let invalidValues = [Double.nan, .infinity, -.infinity, 0, -1]
        for value in invalidValues {
            XCTAssertNil(VisualAngleGeometry.physicalHeightMetres(forArcMinutes: value, atDistanceMetres: 1))
            XCTAssertNil(VisualAngleGeometry.physicalHeightMetres(forArcMinutes: 5, atDistanceMetres: value))
            XCTAssertNil(VisualAngleGeometry.arcMinutes(forPhysicalHeightMetres: value, atDistanceMetres: 1))
            XCTAssertNil(VisualAngleGeometry.arcMinutes(forPhysicalHeightMetres: 0.001, atDistanceMetres: value))
            XCTAssertNil(VisualAngleGeometry.pixels(forPhysicalHeightMetres: value, pixelsPerInch: 460))
            XCTAssertNil(VisualAngleGeometry.pixels(forPhysicalHeightMetres: 0.001, pixelsPerInch: value))
            XCTAssertNil(OptotypeGeometry.calculate(distanceMetres: value, pixelsPerInch: 460, displayScale: 3))
            XCTAssertNil(OptotypeGeometry.calculate(distanceMetres: 1, pixelsPerInch: value, displayScale: 3))
            XCTAssertNil(OptotypeGeometry.calculate(distanceMetres: 1, pixelsPerInch: 460, displayScale: value))
        }
        XCTAssertNil(VisualAngleGeometry.physicalHeightMetres(
            forArcMinutes: VisualAngleGeometry.maximumArcMinutesExclusive,
            atDistanceMetres: 1
        ))
        XCTAssertNil(OptotypeGeometry.calculate(
            distanceMetres: Double.greatestFiniteMagnitude,
            pixelsPerInch: Double.greatestFiniteMagnitude,
            displayScale: 3
        ))
    }

    func testFarPointDiopterRoundTripAndMonotonicitySweep() throws {
        var previousDiopter = -Double.infinity
        for distanceIndex in 40...200 {
            let distance = Double(distanceIndex) / 100
            let diopter = try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: distance))
            let recovered = try XCTUnwrap(RefractionEstimator.distanceMetres(forMyopicDiopter: diopter))

            XCTAssertEqual(recovered, distance, accuracy: 1e-12)
            XCTAssertGreaterThan(diopter, previousDiopter)
            previousDiopter = diopter
        }

        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(RefractionEstimator.diopter(forDistanceMetres: invalid))
        }
        for invalid in [Double.nan, .infinity, -.infinity, 0, 0.25] {
            XCTAssertNil(RefractionEstimator.distanceMetres(forMyopicDiopter: invalid))
        }
    }

    func testDistanceUncertaintyPropagationMatchesHandCalculatedReferences() throws {
        let cases: [(distance: Double, sigma: Double, expected: Double)] = [
            (0.40, 0.01, 0.0625),
            (0.50, 0.01, 0.04),
            (1.00, 0.01, 0.01),
            (2.00, 0.01, 0.0025)
        ]
        var previous = Double.infinity
        for item in cases {
            let propagated = try XCTUnwrap(RefractionEstimator.sensorUncertainty(
                distanceMetres: item.distance,
                standardDeviationMetres: item.sigma
            ))
            XCTAssertEqual(propagated, item.expected, accuracy: 1e-14)
            XCTAssertLessThan(propagated, previous)
            previous = propagated
        }

        XCTAssertNil(RefractionEstimator.sensorUncertainty(distanceMetres: .nan, standardDeviationMetres: 0.01))
        XCTAssertNil(RefractionEstimator.sensorUncertainty(distanceMetres: 1, standardDeviationMetres: .infinity))
        XCTAssertNil(RefractionEstimator.sensorUncertainty(distanceMetres: 1, standardDeviationMetres: -0.01))
        XCTAssertNil(RefractionEstimator.sensorUncertainty(distanceMetres: 1, standardDeviationMetres: 1))
    }

    func testQuarterDiopterRoundingUsesDefinedTieRuleAndNeverEmitsNegativeZero() {
        XCTAssertEqual(RefractionEstimator.roundedToQuarterDiopter(-2.125), -2.25)
        XCTAssertEqual(RefractionEstimator.roundedToQuarterDiopter(-2.1249), -2.0)
        XCTAssertEqual(RefractionEstimator.roundedToQuarterDiopter(2.125), 2.25)
        XCTAssertEqual(RefractionEstimator.roundedToQuarterDiopter(-0.01).sign, .plus)
        XCTAssertTrue(RefractionEstimator.roundedToQuarterDiopter(.nan).isNaN)
        XCTAssertTrue(RefractionEstimator.roundedToQuarterDiopter(.infinity).isNaN)
    }

    func testActiveEnlargedLocatorCannotUnlockNumericOutputWithPlausibleProfileFlags() {
        let profile = fullyPopulatedProfileMatchingActiveLocator()
        XCTAssertEqual(LandoltProtocolDescriptor.activePhoneLocator.presentationMode, .phonePOCLocator)
        XCTAssertFalse(NumericResultEligibility.hasApprovedNumericProtocolRelease)
        XCTAssertFalse(NumericResultEligibility.allowsNumericResults(
            profile: profile,
            supportsSecondFaceDetection: true,
            matchesExactRuntimeDevice: true
        ))
    }

    func testNumericFieldsAreRedactedEvenWhenPersistedEligibilityIsTamperedTrue() {
        let unsafe = EyeScreeningResult(
            eye: .right,
            status: .validEstimate,
            lastFailDiopter: -2.0,
            firstPassDiopter: -2.25,
            displayedEstimateDiopter: -2.25,
            thresholdDistanceMetres: 0.44,
            sensorUncertaintyDiopter: 0.04,
            repeatabilityDiopter: 0.02,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
        let safe = NumericResultEligibility.sanitize(unsafe, numericResultsAllowed: true)

        XCTAssertEqual(safe.status, .experimentalThresholdObserved)
        XCTAssertNil(safe.lastFailDiopter)
        XCTAssertNil(safe.firstPassDiopter)
        XCTAssertNil(safe.displayedEstimateDiopter)
        XCTAssertNil(safe.thresholdDistanceMetres)
        XCTAssertNil(safe.sensorUncertaintyDiopter)
        XCTAssertNil(safe.repeatabilityDiopter)
        XCTAssertFalse(
            ResultsPresentationPolicy.landoltDisplayValue(
                result: unsafe,
                integrityValid: true,
                numericResultsAllowed: true
            ).contains("2.25")
        )
        XCTAssertFalse(
            ResultsPresentationPolicy.spokenLandoltSummary(
                eye: .right,
                result: unsafe,
                integrityValid: true,
                numericResultsAllowed: true
            ).contains("2.25")
        )
    }

    func testUnauthorizedSanitizerRedactsNumbersFromEveryStatusContract() {
        for status in ScreeningStatus.allCasesForSafetyTest {
            let malformed = EyeScreeningResult(
                eye: .left,
                status: status,
                lastFailDiopter: -1.0,
                firstPassDiopter: -1.25,
                displayedEstimateDiopter: -1.25,
                thresholdDistanceMetres: 0.8,
                sensorUncertaintyDiopter: 0.02,
                repeatabilityDiopter: 0.03,
                trackingQuality: .good,
                responseConsistency: .good,
                warnings: [],
                recommendedAction: .routineExamRecommended
            )

            let sanitized = NumericResultEligibility.sanitize(
                malformed,
                numericResultsAllowed: true,
                protocolDescriptor: .activePhoneLocator
            )

            XCTAssertNil(sanitized.lastFailDiopter, "status: \(status)")
            XCTAssertNil(sanitized.firstPassDiopter, "status: \(status)")
            XCTAssertNil(sanitized.displayedEstimateDiopter, "status: \(status)")
            XCTAssertNil(sanitized.thresholdDistanceMetres, "status: \(status)")
            XCTAssertNil(sanitized.sensorUncertaintyDiopter, "status: \(status)")
            XCTAssertNil(sanitized.repeatabilityDiopter, "status: \(status)")
        }
    }

    func testNumericPresentationFailsClosedWhenIntegrityIsMissing() {
        let result = EyeScreeningResult(
            eye: .left,
            status: .validEstimate,
            lastFailDiopter: -1.0,
            firstPassDiopter: -1.25,
            displayedEstimateDiopter: -1.25,
            thresholdDistanceMetres: 0.8,
            sensorUncertaintyDiopter: 0.02,
            repeatabilityDiopter: 0.02,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
        XCTAssertEqual(
            ResultsPresentationPolicy.landoltDisplayValue(
                result: result,
                integrityValid: nil,
                numericResultsAllowed: true
            ),
            "Repeat needed · review required"
        )
        XCTAssertFalse(
            ResultsPresentationPolicy.spokenLandoltSummary(
                eye: .left,
                result: result,
                integrityValid: nil,
                numericResultsAllowed: true
            ).localizedCaseInsensitiveContains("diopter")
        )
    }

    func testIntegrityRejectsPositiveAndOutOfRangeDiopterClaims() {
        let impossible = EyeScreeningResult(
            eye: .right,
            status: .validEstimate,
            lastFailDiopter: 1.0,
            firstPassDiopter: 0.75,
            displayedEstimateDiopter: 1.0,
            thresholdDistanceMetres: 1,
            sensorUncertaintyDiopter: 0.01,
            repeatabilityDiopter: 0.01,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
        let validation = ResultIntegrityValidator.validate(impossible)
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.nonMyopicDiopter))
    }

    func testSearchRejectsNonFiniteMeasurementEvidenceWithoutProducingNumbers() {
        var engine = ThresholdSearchEngine(eye: .right)
        let invalid = TrialBlock(
            eye: .right,
            candidateDiopter: -2.5,
            targetDistanceMetres: 0.4,
            actualMedianDistanceMetres: .nan,
            distanceStandardDeviation: 0.01,
            targets: [.up, .right, .down, .left, .up, .right, .down, .left],
            responses: [
                OptotypeResponse.up, .right, .down, .left, .up, .right, .down, .left
            ],
            correctCount: SequentialOptotypeSession.requiredTargetCount,
            outcome: .pass,
            quality: validQuality(),
            responseSource: .voice,
            transcript: nil
        )

        guard case .completed(let result) = engine.submit(block: invalid) else {
            return XCTFail("Non-finite evidence must terminate fail-closed")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
        XCTAssertNil(result.displayedEstimateDiopter)
        XCTAssertNil(result.thresholdDistanceMetres)
    }

    func testCalibrationFitRejectsNonFiniteOrUndersampledEvidence() throws {
        XCTAssertNil(CalibrationFitter.affineFit(observations: [
            .init(groundTruthMetres: 0.4, rawDistanceMetres: 0.4),
            .init(groundTruthMetres: .nan, rawDistanceMetres: 0.8)
        ]))

        let twoPoint = [
            CalibrationObservation(groundTruthMetres: 0.4, rawDistanceMetres: 0.4),
            CalibrationObservation(groundTruthMetres: 2.0, rawDistanceMetres: 2.0)
        ]
        let fit = try XCTUnwrap(CalibrationFitter.affineFit(observations: twoPoint))
        XCTAssertFalse(CalibrationFitter.passesAcceptance(observations: twoPoint, fit: fit))
    }

    private func validQuality() -> BlockQuality {
        BlockQuality(
            trackingCoverage: 0.98,
            phoneStable: true,
            headPoseValid: true,
            distanceStable: true,
            audioLevelAdequate: true,
            targetGeometryValid: true,
            gazeCoverage: 0.98,
            discardReasons: []
        )
    }

    private func fullyPopulatedProfileMatchingActiveLocator() -> DeviceProfile {
        let descriptor = LandoltProtocolDescriptor.activePhoneLocator
        return DeviceProfile(
            schemaVersion: 1,
            profileVersion: 99,
            hardwareIdentifiers: ["exact-device"],
            marketingFamily: "Exact test device",
            variant: "Reference",
            nativePixelWidth: 1_206,
            nativePixelHeight: 2_622,
            displayScale: 3,
            pixelsPerInch: 460,
            expectedCameraType: .trueDepth,
            calibration: DistanceCalibration(
                scale: 1,
                offsetMetres: 0,
                baselineDistanceMetres: 0.4,
                validatedDistancesMetres: NumericResultEligibility.requiredCalibrationDistances
            ),
            qualityThresholds: .conservative,
            minimumValidatedDistance: 0.4,
            maximumValidatedDistance: 2,
            validationEvidence: ValidationSummary(
                sampleCount: 1_200,
                maximumMedianErrorBelowOneMetre: 0.01,
                maximumMedianPercentageErrorAtOrAboveOneMetre: 0.02,
                validatedAt: Date(),
                notes: "Test fixture only"
            ),
            displayRasterValidation: DisplayRasterValidation(
                sampleCount: 100,
                nativePixelWidth: 1_206,
                nativePixelHeight: 2_622,
                displayScale: 3,
                pixelsPerInch: 460,
                validatedBrightnessFraction: 0.80,
                blackLuminanceCandelaPerSquareMetre: 0.5,
                whiteLuminanceCandelaPerSquareMetre: 500,
                gammaCharacterizationIdentifier: "fixture-gamma-study",
                validatedAt: Date(),
                notes: "Test fixture only"
            ),
            clinicalValidationEvidence: ClinicalValidationEvidence(
                participantCount: 100,
                observationCount: 1_200,
                protocolIdentifier: descriptor.identifier,
                protocolVersion: descriptor.version,
                presentationMode: descriptor.presentationMode,
                responsesPerLevel: descriptor.responsesPerLevel,
                usedValidatedThresholdModel: descriptor.usesValidatedThresholdModel,
                permittedPointSizeClamping: descriptor.permitsPointSizeClamping,
                agreementMetrics: ClinicalAgreementMetrics(
                    referenceStandard: .cycloplegicRefraction,
                    studyIdentifier: "fixture-clinical-study",
                    predefinedAcceptanceCriteriaIdentifier: "fixture-acceptance-criteria",
                    meanAbsoluteErrorDiopter: 0.10,
                    meanBiasDiopter: 0,
                    lower95AgreementLimitDiopter: -0.25,
                    upper95AgreementLimitDiopter: 0.25,
                    sensitivity: 0.95,
                    specificity: 0.95
                ),
                validatedAt: Date(),
                notes: "Plausible fields must not self-authorize"
            ),
            isValidated: true
        )
    }
}

private extension ScreeningStatus {
    static let allCasesForSafetyTest: [ScreeningStatus] = [
        .validEstimate,
        .noMyopiaDetectedWithinRange,
        .strongerThanSupportedRange,
        .experimentalThresholdObserved,
        .experimentalFarthestTargetPassed,
        .experimentalAdverseBoundary,
        .experimentalTaskCompleted,
        .unreliableMeasurement,
        .deviceUnsupported,
        .userIneligible
    ]
}
