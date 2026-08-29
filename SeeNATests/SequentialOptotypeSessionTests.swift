import XCTest
@testable import SEENACore

final class SequentialOptotypeSessionTests: XCTestCase {
    private let targets: [OptotypeDirection] = [
        .up, .right, .down, .left, .right, .up, .down
    ]

    func testRequiresExactlySevenTargets() {
        XCTAssertNil(SequentialOptotypeSession(targets: Array(targets.prefix(6))))
        XCTAssertNil(SequentialOptotypeSession(targets: targets + [.left]))
        XCTAssertNotNil(SequentialOptotypeSession(targets: targets))
    }

    func testStartsOnOnlyTheFirstTarget() throws {
        let session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.currentTarget, .up)
        XCTAssertEqual(session.responses, [])
        XCTAssertFalse(session.isComplete)
    }

    func testInvalidAnswerAndRetryDoNotAdvance() throws {
        var session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        XCTAssertEqual(session.submit(nil), .rejected)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.currentTarget, .up)
        XCTAssertEqual(session.retryCurrentTarget(), .up)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.responses, [])
    }

    func testEachValidAnswerAdvancesExactlyOneTarget() throws {
        var session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        XCTAssertEqual(session.submit(.left), .advanced)
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.currentTarget, .right)
        XCTAssertEqual(session.responses, [.left])

        XCTAssertEqual(session.submit(.down), .advanced)
        XCTAssertEqual(session.currentIndex, 2)
        XCTAssertEqual(session.currentTarget, .down)
        XCTAssertEqual(session.responses, [.left, .down])
    }

    func testNotVisibleIsAcceptedOnceAndNeverMatchesATarget() throws {
        var session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        XCTAssertEqual(session.submit(.notVisible), .advanced)
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.currentTarget, .right)
        XCTAssertEqual(session.responses, [.notVisible])
        XCTAssertFalse(OptotypeResponse.notVisible.matches(.up))
        XCTAssertFalse(OptotypeResponse.notVisible.matches(.right))
        XCTAssertNil(OptotypeResponse.notVisible.direction)
    }

    func testNotVisibleScoresIncorrectWithoutInvalidatingSevenAnswers() {
        let responses: [OptotypeResponse] = [
            .notVisible, .right, .down, .left, .right, .up, .down
        ]
        let correct = zip(targets, responses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }

        XCTAssertEqual(responses.count, 7)
        XCTAssertEqual(correct, 6)
        XCTAssertEqual(
            TrialScorer.outcome(correctCount: correct, hasExactlySevenResponses: true),
            .pass
        )
    }

    func testLegacyDirectionStringsAndNotVisibleRemainCodable() throws {
        let data = Data(#"["up","right","down","left","notVisible"]"#.utf8)
        let decoded = try JSONDecoder().decode([OptotypeResponse].self, from: data)

        XCTAssertEqual(decoded, [.up, .right, .down, .left, .notVisible])
        XCTAssertEqual(try JSONEncoder().encode(decoded), data)
    }

    func testCompletesOnlyAfterSeventhAnswerAndCannotAdvanceAgain() throws {
        var session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        for index in 0..<6 {
            XCTAssertEqual(session.submit(OptotypeResponse(targets[index])), .advanced)
            XCTAssertFalse(session.isComplete)
            XCTAssertEqual(session.currentIndex, index + 1)
        }

        XCTAssertEqual(session.submit(OptotypeResponse(targets[6])), .completed)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.currentIndex, 7)
        XCTAssertNil(session.currentTarget)
        XCTAssertEqual(session.responses.count, 7)

        XCTAssertEqual(session.submit(.left), .rejected)
        XCTAssertEqual(session.currentIndex, 7)
        XCTAssertEqual(session.responses.count, 7)
    }
}
