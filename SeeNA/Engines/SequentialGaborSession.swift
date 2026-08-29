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

/// Owns the answer-gated progression through one seven-target Gabor block.
/// Only a single left/right answer can advance the currently displayed patch.
struct SequentialGaborSession: Equatable, Sendable {
    static let requiredTargetCount = 7

    let targets: [GaborOrientation]
    private(set) var responses: [GaborResponse] = []

    init?(targets: [GaborOrientation]) {
        guard targets.count == Self.requiredTargetCount else { return nil }
        self.targets = targets
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
    /// is represented as the opposite orientation so the unchanged persisted
    /// `GaborTrial` records a not-visible response explicitly, and the scorer
    /// counts it as incorrect without conflating it with the opposite tilt.
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
