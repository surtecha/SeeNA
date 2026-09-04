import XCTest
@testable import SEENACore

final class SequentialGaborSessionTests: XCTestCase {
    private let targets: [GaborOrientation] = [
        .left, .right, .left, .right, .left, .right, .left, .right
    ]

    func testRequiresExactlyEightBalancedTargetsWithoutRunsOfThree() {
        XCTAssertNil(SequentialGaborSession(targets: Array(targets.prefix(7))))
        XCTAssertNil(SequentialGaborSession(targets: targets + [.left]))
        XCTAssertNil(SequentialGaborSession(targets: Array(repeating: .left, count: 8)))
        XCTAssertNil(SequentialGaborSession(targets: [
            .left, .left, .left, .right, .right, .left, .right, .right
        ]))
        XCTAssertNotNil(SequentialGaborSession(targets: targets))
    }

    func testGeneratedSequenceIsBalancedWithoutForcedAlternation() {
        var observedShortPair = false
        for seed in 1...32 {
            var generator = GaborSeededGenerator(seed: UInt64(seed))
            let generated = GaborTargetSequence.make(using: &generator)

            XCTAssertEqual(generated.count, 8)
            XCTAssertEqual(generated.filter { $0 == .left }.count, 4)
            XCTAssertEqual(generated.filter { $0 == .right }.count, 4)
            XCTAssertFalse(generated.indices.dropFirst(2).contains { index in
                generated[index] == generated[index - 1]
                    && generated[index] == generated[index - 2]
            })
            observedShortPair = observedShortPair
                || zip(generated, generated.dropFirst()).contains { $0 == $1 }
        }
        XCTAssertTrue(observedShortPair, "Balanced schedules must not be forced to alternate")
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
        XCTAssertEqual(session.currentTarget, .left)
        XCTAssertEqual(session.responses, [.right, .left])
    }

    func testCompletesOnlyAfterEightValidAnswers() throws {
        var session = try XCTUnwrap(SequentialGaborSession(targets: targets))
        let answers: [OptotypeDirection] = [.left, .right, .left, .right, .left, .right, .left, .right]

        for answer in answers.dropLast() {
            XCTAssertEqual(session.submit(.direction(answer)), .advanced)
            XCTAssertFalse(session.isComplete)
        }

        XCTAssertEqual(session.submit(answers.last.map(SequentialGaborAnswer.direction)), .completed)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.currentIndex, 8)
        XCTAssertNil(session.currentTarget)
        XCTAssertEqual(session.responses, targets.map(GaborResponse.init))

        XCTAssertEqual(session.submit(.direction(.left)), .rejected)
        XCTAssertEqual(session.responses.count, 8)
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
            7
        )
    }
}

private struct GaborSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xD1B5_4A32_D192_ED03 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
