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

        XCTAssertEqual(displayed, "Task complete")
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

        XCTAssertEqual(displayed, "Task complete")
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
        XCTAssertEqual(result.headline, "Repeat needed")
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
            remoteWasGenerated: true,
            reliability: .repeatRequired
        ), local)
        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: "Remote reassurance",
            remoteVerified: false,
            remoteWasGenerated: true,
            reliability: .reliable
        ), local)
    }

    func testActiveQualitativeStatusesUseOnlyNeutralTaskCompletionCopy() {
        let completedStatuses: [ScreeningStatus] = [
            .experimentalThresholdObserved,
            .experimentalFarthestTargetPassed,
            .experimentalAdverseBoundary,
            .experimentalTaskCompleted
        ]
        let disallowedClaims = [
            "acuity", "myopia", "contrast sensitivity", "threshold", "diagnos",
            "prescription", "professional review", "referral", "score", "estimate",
            "farthest", "strongest", "performance boundary"
        ]

        for status in completedStatuses {
            var screening = completedQualitativeSession()
            screening.rightEyeResult = qualitativeResult(
                .right,
                status: status,
                recommendedAction: .professionalReviewRecommended
            )
            screening.leftEyeResult = qualitativeResult(
                .left,
                status: status,
                recommendedAction: .professionalReviewRecommended
            )

            let presentation = ResultsPresentationPolicy.evaluate(
                screening: screening,
                landoltIntegrityValid: true,
                gaborIntegrityValid: true
            )
            let display = ResultsPresentationPolicy.landoltDisplayValue(
                result: screening.rightEyeResult,
                integrityValid: true,
                numericResultsAllowed: false
            )
            let spoken = ResultsPresentationPolicy.spokenLandoltSummary(
                eye: .right,
                result: screening.rightEyeResult,
                integrityValid: true,
                numericResultsAllowed: false
            )
            let publicCopy = [display, spoken, presentation.headline, presentation.localMeaning]
                .joined(separator: " ")

            XCTAssertEqual(display, "Task complete", "Unexpected display for \(status)")
            XCTAssertEqual(spoken, "Right eye circle task complete.", "Unexpected speech for \(status)")
            XCTAssertEqual(presentation.headline, "Tasks complete", "Unexpected headline for \(status)")
            XCTAssertEqual(presentation.localMeaning, "Your answers were recorded for both eyes.")
            XCTAssertEqual(presentation.recommendation, .routineExamRecommended)
            for claim in disallowedClaims {
                XCTAssertFalse(
                    publicCopy.localizedCaseInsensitiveContains(claim),
                    "Active qualitative copy contains a disallowed claim: \(claim)"
                )
            }
        }
    }

    func testSafeGeneratedQualitativeProseDisplaysAfterAllGatesPass() {
        let local = "Your answers were recorded for both eyes."
        let remote = "All tasks are complete, and your responses were recorded for each eye."

        XCTAssertEqual(
            ResultsPresentationPolicy.explanation(
                local: local,
                remote: remote,
                remoteVerified: true,
                remoteWasGenerated: true,
                reliability: .reliable
            ),
            remote
        )
    }

    func testUnsafeGeneratedQualitativeProseAlwaysFallsBackLocally() {
        let local = "Your answers were recorded for both eyes."
        let unsafe = [
            "Your score was eight.",
            "Your result suggests myopia.",
            "Your visual acuity looks normal.",
            "Your contrast sensitivity is good.",
            "This screening is clinically validated.",
            "The model recommends a referral.",
            "Your answers were not recorded.",
            "The right eye performed better.",
            "Your tasks are complete at one metre.",
            "Your answers were recorded and everything looks clear."
        ]

        for remote in unsafe {
            XCTAssertEqual(
                ResultsPresentationPolicy.explanation(
                    local: local,
                    remote: remote,
                    remoteVerified: true,
                    remoteWasGenerated: true,
                    reliability: .reliable
                ),
                local,
                "Unsafe model prose crossed the client boundary: \(remote)"
            )
        }
    }

    func testFallbackOrBackendReviewCannotOverrideLocalMeaning() {
        let local = "Your answers were recorded for both eyes."
        let safeRemote = "All tasks are complete, and your responses were recorded for each eye."

        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: safeRemote,
            remoteVerified: false,
            remoteWasGenerated: true,
            reliability: .reliable
        ), local)
        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: safeRemote,
            remoteVerified: true,
            remoteWasGenerated: false,
            reliability: .reliable
        ), local)
        XCTAssertEqual(ResultsPresentationPolicy.explanation(
            local: local,
            remote: safeRemote,
            remoteVerified: true,
            remoteWasGenerated: true,
            reliability: .reviewRequired
        ), local)
    }

    func testRepeatCopyIsShortAndContainsNoInternalReviewJargon() {
        let display = ResultsPresentationPolicy.landoltDisplayValue(
            result: qualitativeResult(.right),
            integrityValid: false,
            numericResultsAllowed: false
        )
        let spoken = ResultsPresentationPolicy.spokenLandoltSummary(
            eye: .right,
            result: qualitativeResult(.right),
            integrityValid: false,
            numericResultsAllowed: false
        )

        XCTAssertEqual(display, "Repeat needed")
        XCTAssertEqual(spoken, "Right eye circle task needs repeating.")
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("evidence"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("consistency"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("review"))
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

    private func qualitativeResult(
        _ eye: Eye,
        status: ScreeningStatus = .experimentalFarthestTargetPassed,
        recommendedAction: ScreeningAction = .routineExamRecommended
    ) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: nil,
            firstPassDiopter: nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: nil,
            sensorUncertaintyDiopter: nil,
            repeatabilityDiopter: nil,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: [.researchPrototype],
            recommendedAction: recommendedAction
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
