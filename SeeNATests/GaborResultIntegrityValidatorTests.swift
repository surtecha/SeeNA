import XCTest
@testable import SEENACore

final class GaborResultIntegrityValidatorTests: XCTestCase {
    func testAcceptsReplayableCompletedOrientationTask() {
        let trials = [
            trial(contrast: 0.40, outcome: .pass),
            trial(contrast: 0.25, outcome: .pass),
            trial(contrast: 0.16, outcome: .pass),
            trial(contrast: 0.10, outcome: .pass),
            trial(contrast: 0.06, outcome: .pass)
        ]
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

    func testRejectsMalformedTrialAndInvalidResultState() {
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

        let incomplete = GaborResultIntegrityValidator.validate(
            result,
            against: [trial(contrast: 0.40, outcome: .pass)]
        )
        XCTAssertEqual(incomplete.issues, [.invalidResultState])
    }

    private func trial(
        contrast: Double,
        outcome: TrialOutcome,
        eye: Eye = .right,
        responses: [GaborOrientation]? = nil,
        correctCount: Int? = nil
    ) -> GaborTrial {
        let targets: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left]
        let defaultResponses: [GaborOrientation]
        switch outcome {
        case .pass:
            defaultResponses = targets
        case .fail:
            defaultResponses = [.right, .left, .right, .left, .right, .left, .right]
        case .borderline:
            defaultResponses = [.left, .right, .left, .right, .right, .left, .right]
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
            transcript: nil
        )
    }
}
