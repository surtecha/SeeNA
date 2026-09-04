import XCTest
@testable import SEENACore

final class SequentialOptotypeSessionTests: XCTestCase {
    private let targets: [OptotypeDirection] = [
        .up, .right, .down, .left, .right, .up, .left, .down
    ]

    func testRequiresExactlyEightBalancedNonRepeatingTargets() {
        XCTAssertNil(SequentialOptotypeSession(targets: Array(targets.prefix(7))))
        XCTAssertNil(SequentialOptotypeSession(targets: targets + [.up]))
        XCTAssertNil(SequentialOptotypeSession(targets: Array(repeating: .up, count: 8)))
        XCTAssertNil(SequentialOptotypeSession(targets: [
            .up, .up, .right, .down, .left, .right, .down, .left
        ]))
        XCTAssertNotNil(SequentialOptotypeSession(targets: targets))
    }

    func testGeneratedSequenceIsDeterministicallyBalancedWithoutAdjacentRepeats() {
        for seed in 1...64 {
            var generator = OptotypeSeededGenerator(seed: UInt64(seed))
            let generated = LandoltTargetSequence.make(using: &generator)

            XCTAssertEqual(generated.count, 8)
            for direction in OptotypeDirection.allCases {
                XCTAssertEqual(generated.filter { $0 == direction }.count, 2)
            }
            XCTAssertFalse(zip(generated, generated.dropFirst()).contains { $0 == $1 })
        }
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

    func testNotVisibleScoresIncorrectWithoutInvalidatingEightAnswers() {
        let responses: [OptotypeResponse] = [
            .notVisible, .right, .down, .left, .right, .up, .left, .down
        ]
        let correct = zip(targets, responses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }

        XCTAssertEqual(responses.count, 8)
        XCTAssertEqual(correct, 7)
        XCTAssertEqual(
            TrialScorer.outcome(correctCount: correct, responseCount: responses.count),
            .pass
        )
    }

    func testLegacyDirectionStringsAndNotVisibleRemainCodable() throws {
        let data = Data(#"["up","right","down","left","notVisible"]"#.utf8)
        let decoded = try JSONDecoder().decode([OptotypeResponse].self, from: data)

        XCTAssertEqual(decoded, [.up, .right, .down, .left, .notVisible])
        XCTAssertEqual(try JSONEncoder().encode(decoded), data)
    }

    func testCompletesOnlyAfterEighthAnswerAndCannotAdvanceAgain() throws {
        var session = try XCTUnwrap(SequentialOptotypeSession(targets: targets))

        for index in 0..<7 {
            XCTAssertEqual(session.submit(OptotypeResponse(targets[index])), .advanced)
            XCTAssertFalse(session.isComplete)
            XCTAssertEqual(session.currentIndex, index + 1)
        }

        XCTAssertEqual(session.submit(OptotypeResponse(targets[7])), .completed)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.currentIndex, 8)
        XCTAssertNil(session.currentTarget)
        XCTAssertEqual(session.responses.count, 8)

        XCTAssertEqual(session.submit(.left), .rejected)
        XCTAssertEqual(session.currentIndex, 8)
        XCTAssertEqual(session.responses.count, 8)
    }
}

private struct OptotypeSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
