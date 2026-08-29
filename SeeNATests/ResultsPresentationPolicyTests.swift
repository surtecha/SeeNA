import XCTest
@testable import SEENACore

final class ResultsPresentationPolicyTests: XCTestCase {
    func testCurrentIneligibleSessionCannotRenderOrSpeakNumericResult() {
        let result = numericResult(.right)

        let displayed = ResultsPresentationPolicy.landoltDisplayValue(
            result: result,
            integrityValid: true,
            numericResultsAllowed: false
        )
        let spoken = ResultsPresentationPolicy.spokenLandoltSummary(
            eye: .right,
            result: result,
            integrityValid: true,
            numericResultsAllowed: false
        )

        XCTAssertEqual(displayed, "Performance boundary recorded")
        XCTAssertFalse(displayed.contains("D"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("diopter"))
        XCTAssertFalse(spoken.contains("2.25"))
    }

    func testLegacySavedSessionWithMissingEligibilityCannotRenderOrSpeakNumericResult() {
        var legacySavedSession = completedQualitativeSession()
        legacySavedSession.numericResultsAllowed = nil
        legacySavedSession.rightEyeResult = numericResult(.right)

        let displayed = ResultsPresentationPolicy.landoltDisplayValue(
            result: legacySavedSession.rightEyeResult,
            integrityValid: true,
            numericResultsAllowed: legacySavedSession.numericResultsAllowed
        )
        let spoken = ResultsPresentationPolicy.spokenLandoltSummary(
            eye: .right,
            result: legacySavedSession.rightEyeResult,
            integrityValid: true,
            numericResultsAllowed: legacySavedSession.numericResultsAllowed
        )
        let presentation = ResultsPresentationPolicy.evaluate(
            screening: legacySavedSession,
            landoltIntegrityValid: true,
            gaborIntegrityValid: true
        )

        XCTAssertEqual(displayed, "Performance boundary recorded")
        XCTAssertFalse(displayed.contains("D"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("diopter"))
        XCTAssertFalse(spoken.contains("2.25"))
        XCTAssertEqual(presentation.numericVerification, .notApplicableEvidenceIntact)
        XCTAssertFalse(presentation.localMeaning.localizedCaseInsensitiveContains("estimate"))
    }

    func testPreservesAdverseAndFarthestQualitativeBoundaries() {
        let adverse = NumericResultEligibility.sanitize(
            eyeResult(.right, status: .strongerThanSupportedRange),
            numericResultsAllowed: false
        )
        XCTAssertEqual(adverse.status, .experimentalAdverseBoundary)
        XCTAssertEqual(adverse.recommendedAction, .professionalReviewRecommended)

        let farthest = NumericResultEligibility.sanitize(
            eyeResult(.left, status: .noMyopiaDetectedWithinRange),
            numericResultsAllowed: false
        )
        XCTAssertEqual(farthest.status, .experimentalFarthestTargetPassed)
        XCTAssertEqual(farthest.recommendedAction, .routineExamRecommended)
    }

    func testGaborFailureMakesStructurallyFinishedSessionRequireRepeat() {
        var screening = completedQualitativeSession()
        screening.leftGaborResult = GaborScreeningResult(
            eye: .left,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )

        let result = ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: true,
            gaborIntegrityValid: true
        )

        XCTAssertTrue(result.structurallyFinished)
        XCTAssertEqual(result.reliability, .repeatRequired)
        XCTAssertEqual(result.recommendation, .repeatRequired)
        XCTAssertEqual(result.headline, "Screening complete, but repeat needed")
    }

    func testUnreliableEvidenceUsesNeutralNonnumericVerification() {
        let screening = completedQualitativeSession()
        let valid = ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: true,
            gaborIntegrityValid: true
        )
        XCTAssertEqual(valid.numericVerification, .notApplicableEvidenceIntact)

        let invalid = ResultsPresentationPolicy.evaluate(
            screening: screening,
            landoltIntegrityValid: false,
            gaborIntegrityValid: true
        )
        XCTAssertEqual(invalid.reliability, .reviewRequired)
        XCTAssertEqual(invalid.numericVerification, .reviewNeeded)
    }

    func testBackendTextNeverOverridesFallbackForUnreliableOrUnverifiedResult() {
        let local = "Local fail-closed explanation"
        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: "Remote reassurance",
            remoteVerified: true,
            reliability: .repeatRequired
        ), local)
        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: "Remote reassurance",
            remoteVerified: false,
            reliability: .reliable
        ), local)
    }

    func testPersistenceFailureRequiresExplicitRecoveryOrVolatileDecision() {
        var state = ResultsPersistenceReducer.reduce(.saving, event: .saveFailedUnreadableHistory)
        XCTAssertEqual(state, .recoveryDeletionRequired)
        state = ResultsPersistenceReducer.reduce(state, event: .recoveryDeletionConfirmed)
        XCTAssertEqual(state, .saving)

        state = ResultsPersistenceReducer.reduce(.saving, event: .saveFailedUnreadableHistory)
        state = ResultsPersistenceReducer.reduce(state, event: .continueVolatile)
        XCTAssertEqual(state, .volatile)

        state = ResultsPersistenceReducer.reduce(.saving, event: .saveFailedRetryable)
        XCTAssertEqual(state, .retryableFailure)
        XCTAssertEqual(
            ResultsPersistenceReducer.reduce(state, event: .recoveryDeletionConfirmed),
            .retryableFailure
        )
    }

    private func completedQualitativeSession() -> ScreeningSession {
        var session = ScreeningSession()
        session.numericResultsAllowed = false
        session.rightEyeResult = qualitativeResult(.right)
        session.leftEyeResult = qualitativeResult(.left)
        session.rightGaborResult = GaborScreeningResult(
            eye: .right,
            status: .completed,
            responseConsistency: .good
        )
        session.leftGaborResult = GaborScreeningResult(
            eye: .left,
            status: .completed,
            responseConsistency: .good
        )
        return session
    }

    private func qualitativeResult(_ eye: Eye) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: .experimentalFarthestTargetPassed,
            lastFailDiopter: nil,
            firstPassDiopter: nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: nil,
            sensorUncertaintyDiopter: nil,
            repeatabilityDiopter: nil,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: [.researchPrototype],
            recommendedAction: .routineExamRecommended
        )
    }

    private func eyeResult(_ eye: Eye, status: ScreeningStatus) -> EyeScreeningResult {
        let boundary = status == .strongerThanSupportedRange ? -2.50 : -0.50
        return EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: status == .strongerThanSupportedRange ? boundary : nil,
            firstPassDiopter: status == .noMyopiaDetectedWithinRange ? boundary : nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: 1 / abs(boundary),
            sensorUncertaintyDiopter: 0.05,
            repeatabilityDiopter: 0.05,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
    }

    private func numericResult(_ eye: Eye) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: .validEstimate,
            lastFailDiopter: -2.00,
            firstPassDiopter: -2.50,
            displayedEstimateDiopter: -2.25,
            thresholdDistanceMetres: 1 / 2.25,
            sensorUncertaintyDiopter: 0.05,
            repeatabilityDiopter: 0.05,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
    }
}
