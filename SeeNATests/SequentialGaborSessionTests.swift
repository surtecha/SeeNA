import XCTest
@testable import SEENACore

final class SequentialGaborSessionTests: XCTestCase {
    private let targets: [GaborOrientation] = [
        .left, .right, .right, .left, .right, .left, .left
    ]

    func testRequiresExactlySevenTargets() {
        XCTAssertNil(SequentialGaborSession(targets: Array(targets.prefix(6))))
        XCTAssertNil(SequentialGaborSession(targets: targets + [.right]))
        XCTAssertNotNil(SequentialGaborSession(targets: targets))
    }

    func testStartsWithOnlyFirstTargetCurrent() throws {
        let session = try XCTUnwrap(SequentialGaborSession(targets: targets))

        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.currentTarget, .left)
        XCTAssertEqual(session.responses, [])
        XCTAssertFalse(session.isComplete)
    }

    func testInvalidDirectionsNeverAdvance() throws {
        var session = try XCTUnwrap(SequentialGaborSession(targets: targets))

        XCTAssertEqual(session.submit(nil), .rejected)
        XCTAssertEqual(session.submit(.direction(.up)), .rejected)
        XCTAssertEqual(session.submit(.direction(.down)), .rejected)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.currentTarget, .left)
        XCTAssertEqual(session.responses, [])
    }

    func testEachValidAnswerAdvancesExactlyOnce() throws {
        var session = try XCTUnwrap(SequentialGaborSession(targets: targets))

        XCTAssertEqual(session.submit(.direction(.right)), .advanced)
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.currentTarget, .right)
        XCTAssertEqual(session.responses, [.right])

        XCTAssertEqual(session.submit(.direction(.left)), .advanced)
        XCTAssertEqual(session.currentIndex, 2)
        XCTAssertEqual(session.currentTarget, .right)
        XCTAssertEqual(session.responses, [.right, .left])
    }

    func testCompletesOnlyAfterSevenValidAnswers() throws {
        var session = try XCTUnwrap(SequentialGaborSession(targets: targets))
        let answers: [OptotypeDirection] = [.left, .right, .right, .left, .right, .left, .left]

        for answer in answers.dropLast() {
            XCTAssertEqual(session.submit(.direction(answer)), .advanced)
            XCTAssertFalse(session.isComplete)
        }

        XCTAssertEqual(session.submit(answers.last.map(SequentialGaborAnswer.direction)), .completed)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.currentIndex, 7)
        XCTAssertNil(session.currentTarget)
        XCTAssertEqual(session.responses, targets.map(GaborResponse.init))

        XCTAssertEqual(session.submit(.direction(.left)), .rejected)
        XCTAssertEqual(session.responses.count, 7)
    }

    func testNotVisibleAdvancesOnceIsPersistedAndScoresIncorrect() throws {
        var session = try XCTUnwrap(SequentialGaborSession(targets: targets))

        XCTAssertEqual(session.currentTarget, .left)
        XCTAssertEqual(session.submit(.notVisible), .advanced)
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.responses, [.notVisible])
        XCTAssertEqual(
            GaborScorer.correctCount(
                targets: targets,
                responses: session.responses + Array(targets.dropFirst()).map(GaborResponse.init)
            ),
            6
        )
    }
}
