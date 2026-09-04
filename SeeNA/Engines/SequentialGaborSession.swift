import Foundation

enum SequentialGaborSubmissionResult: Equatable, Sendable {
    case rejected
    case advanced
    case completed
}

enum SequentialGaborAnswer: Equatable, Sendable {
    case direction(OptotypeDirection)
    case notVisible
}

/// Produces the active eight-target Gabor sequence.
///
/// The two orientations appear four times each. The order is shuffled while
/// runs of three are rejected. Short pairs remain possible, avoiding a fully
/// alternating sequence that would let later targets be predicted.
enum GaborTargetSequence {
    static func make() -> [GaborOrientation] {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    static func make<R: RandomNumberGenerator>(
        using generator: inout R
    ) -> [GaborOrientation] {
        let candidates = Array(repeating: GaborOrientation.left, count: 4)
            + Array(repeating: GaborOrientation.right, count: 4)

        for _ in 0..<64 {
            let shuffled = candidates.shuffled(using: &generator)
            if SequentialGaborSession.isValidTargetSequence(shuffled) {
                return shuffled
            }
        }

        // Balanced and free of three-item runs, while deliberately retaining
        // short pairs so the sequence is not a predictable alternation.
        return [.left, .right, .left, .left, .right, .left, .right, .right]
    }
}

/// Owns the answer-gated progression through one eight-target Gabor block.
/// Only a single left/right answer can advance the currently displayed patch.
struct SequentialGaborSession: Equatable, Sendable {
    static let requiredTargetCount = 8

    let targets: [GaborOrientation]
    private(set) var responses: [GaborResponse] = []

    init?(targets: [GaborOrientation]) {
        guard Self.isValidTargetSequence(targets) else { return nil }
        self.targets = targets
    }

    static func isValidTargetSequence(_ targets: [GaborOrientation]) -> Bool {
        guard targets.count == requiredTargetCount,
              targets.filter({ $0 == .left }).count == requiredTargetCount / 2,
              targets.filter({ $0 == .right }).count == requiredTargetCount / 2 else {
            return false
        }
        guard targets.count >= 3 else { return true }
        return !targets.indices.dropFirst(2).contains { index in
            targets[index] == targets[index - 1]
                && targets[index] == targets[index - 2]
        }
    }

    var currentIndex: Int { responses.count }

    var currentTarget: GaborOrientation? {
        guard !isComplete else { return nil }
        return targets[currentIndex]
    }

    var isComplete: Bool {
        responses.count == Self.requiredTargetCount
    }

    /// Converts the constrained transcription result into a Gabor response.
    /// Up, down, silence, ambiguity, and extra answers are rejected without
    /// changing the current target. A not-visible response advances once and
    /// is persisted explicitly, so the scorer counts it as incorrect without
    /// conflating it with the opposite tilt.
    @discardableResult
    mutating func submit(_ answer: SequentialGaborAnswer?) -> SequentialGaborSubmissionResult {
        guard !isComplete, let answer else { return .rejected }

        let response: GaborResponse
        switch answer {
        case .direction(let direction):
            switch direction {
            case .left:
                response = .left
            case .right:
                response = .right
            case .up, .down:
                return .rejected
            }
        case .notVisible:
            response = .notVisible
        }

        responses.append(response)
        return isComplete ? .completed : .advanced
    }
}
