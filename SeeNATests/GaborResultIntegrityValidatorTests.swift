import Foundation
import XCTest
@testable import SEENACore

final class GaborResultIntegrityValidatorTests: XCTestCase {
    func testAcceptsOneReplayableLowScoreOrientationBlock() {
        let trials = [trial(contrast: 0.40, outcome: .fail)]
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )

        let validation = GaborResultIntegrityValidator.validate(result, against: trials)

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.issues, [])
    }

    func testRejectsMissingOrWrongEyeEvidence() {
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )
        let missing = GaborResultIntegrityValidator.validate(result, against: [])
        XCTAssertEqual(missing.issues, [.missingSupportingEvidence])

        let wrongEye = GaborResultIntegrityValidator.validate(
            result,
            against: [trial(contrast: 0.40, outcome: .fail, eye: .left)]
        )
        XCTAssertEqual(wrongEye.issues, [.wrongEyeEvidence])
    }

    func testRejectsMalformedTrialAndMismatchedOrExtraEvidence() {
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )
        let malformed = trial(
            contrast: 0.40,
            outcome: .pass,
            responses: Array(repeating: .left, count: 7),
            correctCount: 7
        )
        let malformedValidation = GaborResultIntegrityValidator.validate(result, against: [malformed])
        XCTAssertEqual(malformedValidation.issues, [.malformedSupportingEvidence])

        let mismatched = GaborResultIntegrityValidator.validate(
            GaborScreeningResult(
                eye: .right,
                status: .unreliableMeasurement,
                responseConsistency: .poor
            ),
            against: [trial(contrast: 0.40, outcome: .pass)]
        )
        XCTAssertEqual(mismatched.issues, [.invalidResultState])

        let extra = GaborResultIntegrityValidator.validate(
            result,
            against: [
                trial(contrast: 0.40, outcome: .pass),
                trial(contrast: 0.40, outcome: .pass)
            ]
        )
        XCTAssertEqual(extra.issues, [.invalidResultState])
    }

    func testRejectsMissingOrInvalidBlockQualityEvidence() {
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )

        let missingQuality = trial(
            contrast: 0.40,
            outcome: .fail,
            omitQuality: true
        )
        XCTAssertEqual(
            GaborResultIntegrityValidator.validate(
                result,
                against: [missingQuality]
            ).issues,
            [.malformedSupportingEvidence]
        )

        let invalidQuality = BlockQuality(
            trackingCoverage: .nan,
            phoneStable: false,
            headPoseValid: true,
            distanceStable: true,
            audioLevelAdequate: true,
            targetGeometryValid: false,
            gazeCoverage: 1.2,
            discardReasons: [.phoneMoved, .targetGeometry]
        )
        XCTAssertEqual(
            GaborResultIntegrityValidator.validate(
                result,
                against: [trial(
                    contrast: 0.40,
                    outcome: .fail,
                    qualityOverride: invalidQuality
                )]
            ).issues,
            [.malformedSupportingEvidence]
        )
    }

    func testGazeOnlyQualityReasonRemainsAdvisory() {
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )
        let advisoryQuality = validQuality(
            gazeCoverage: 0.2,
            discardReasons: [.gazeOffCentre]
        )

        let validation = GaborResultIntegrityValidator.validate(
            result,
            against: [trial(
                contrast: 0.40,
                outcome: .fail,
                qualityOverride: advisoryQuality
            )]
        )

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.issues, [])
    }

    func testRejectsMissingStructuredPresentationGeometry() {
        let result = GaborScreeningResult(
            eye: .right,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )

        let validation = GaborResultIntegrityValidator.validate(
            result,
            against: [trial(
                contrast: 0.40,
                outcome: .fail,
                omitGeometry: true
            )]
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.malformedSupportingEvidence])
    }

    func testRejectsPointPixelAndScaleGeometryTampering() {
        let canonical = validGeometry()
        let tamperedGeometries = [
            geometry(canonical, pointDiameter: canonical.pointDiameter + 0.25),
            geometry(canonical, rasterPixelDiameter: canonical.rasterPixelDiameter + 1),
            geometry(canonical, displayScale: canonical.displayScale + 0.25)
        ]
        let result = GaborScreeningResult(
            eye: .right,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )

        for tampered in tamperedGeometries {
            let validation = GaborResultIntegrityValidator.validate(
                result,
                against: [trial(
                    contrast: 0.40,
                    outcome: .fail,
                    geometryOverride: tampered
                )]
            )
            XCTAssertFalse(validation.isValid)
            XCTAssertEqual(validation.issues, [.malformedSupportingEvidence])
        }
    }

    func testLegacyTrialWithoutGeometryDecodesButIsNotVerified() throws {
        let currentTrial = trial(contrast: 0.40, outcome: .fail)
        let encoded = try JSONEncoder().encode(currentTrial)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "presentationGeometry")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try JSONDecoder().decode(GaborTrial.self, from: legacyData)

        XCTAssertNil(decoded.presentationGeometry)
        XCTAssertEqual(decoded.targets, currentTrial.targets)
        XCTAssertEqual(decoded.responses, currentTrial.responses)

        let result = GaborScreeningResult(
            eye: .right,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )
        let validation = GaborResultIntegrityValidator.validate(result, against: [decoded])
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.malformedSupportingEvidence])
    }

    func testCurrentStructuredGeometryRoundTripRemainsVerified() throws {
        let trials = [trial(contrast: 0.40, outcome: .borderline)]
        let persisted = try JSONEncoder().encode(trials)
        let decoded = try JSONDecoder().decode([GaborTrial].self, from: persisted)
        let result = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )

        XCTAssertEqual(decoded, trials)
        XCTAssertTrue(
            GaborResultIntegrityValidator.validate(result, against: decoded).isValid
        )
    }

    func testPresentationGeometryEnforcesRendererRasterBudget() {
        XCTAssertNotNil(
            GaborPresentationGeometry(pointDiameter: 600, displayScale: 3)
        )
        XCTAssertNil(
            GaborPresentationGeometry(pointDiameter: 700, displayScale: 3)
        )

        let canonical = validGeometry()
        let oversized = geometry(
            canonical,
            pointDiameter: 700,
            rasterPixelDiameter: 2_100
        )
        XCTAssertFalse(oversized.isValidCurrentEvidence)
    }

    private func trial(
        contrast: Double,
        outcome: TrialOutcome,
        eye: Eye = .right,
        responses: [GaborOrientation]? = nil,
        correctCount: Int? = nil,
        geometryOverride: GaborPresentationGeometry? = nil,
        omitGeometry: Bool = false,
        qualityOverride: BlockQuality? = nil,
        omitQuality: Bool = false
    ) -> GaborTrial {
        let targets: [GaborOrientation] = [
            .left, .right, .left, .right, .left, .right, .left, .right
        ]
        let defaultResponses: [GaborOrientation]
        switch outcome {
        case .pass:
            defaultResponses = targets
        case .fail:
            defaultResponses = [.right, .left, .right, .left, .right, .left, .right, .left]
        case .borderline:
            defaultResponses = [.left, .right, .left, .right, .left, .right, .right, .left]
        case .invalid:
            defaultResponses = targets
        }
        let storedResponses = responses ?? defaultResponses
        let storedCorrect = correctCount ?? GaborScorer.correctCount(
            targets: targets,
            responses: storedResponses
        )
        return GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: storedResponses,
            correctCount: storedCorrect,
            outcome: outcome,
            responseSource: .voice,
            transcript: nil,
            presentationGeometry: omitGeometry
                ? nil
                : (geometryOverride ?? validGeometry()),
            quality: omitQuality ? nil : (qualityOverride ?? validQuality())
        )
    }

    private func validGeometry() -> GaborPresentationGeometry {
        GaborPresentationGeometry(pointDiameter: 360, displayScale: 3)!
    }

    private func geometry(
        _ canonical: GaborPresentationGeometry,
        pointDiameter: Double? = nil,
        rasterPixelDiameter: Int? = nil,
        displayScale: Double? = nil
    ) -> GaborPresentationGeometry {
        GaborPresentationGeometry(
            evidenceSchemaVersion: canonical.evidenceSchemaVersion,
            rendererVersion: canonical.rendererVersion,
            pointDiameter: pointDiameter ?? canonical.pointDiameter,
            rasterPixelDiameter: rasterPixelDiameter ?? canonical.rasterPixelDiameter,
            displayScale: displayScale ?? canonical.displayScale,
            carrierCyclesPerPatch: canonical.carrierCyclesPerPatch,
            gaussianSigmaFraction: canonical.gaussianSigmaFraction,
            orientationMagnitudeDegrees: canonical.orientationMagnitudeDegrees,
            carrierPhaseRadians: canonical.carrierPhaseRadians,
            meanLuminance: canonical.meanLuminance,
            contrastAmplitudeScale: canonical.contrastAmplitudeScale
        )
    }

    private func validQuality(
        gazeCoverage: Double? = 0.98,
        discardReasons: [BlockDiscardReason] = []
    ) -> BlockQuality {
        BlockQuality(
            trackingCoverage: 0.98,
            phoneStable: true,
            headPoseValid: true,
            distanceStable: true,
            audioLevelAdequate: true,
            targetGeometryValid: true,
            gazeCoverage: gazeCoverage,
            discardReasons: discardReasons
        )
    }
}
