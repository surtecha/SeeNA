import Foundation

enum SequentialOptotypeSubmissionResult: Equatable, Sendable {
    case rejected
    case advanced
    case completed
}

/// Owns the answer-gated progression through one seven-target Landolt block.
/// A target remains current until one valid direction is submitted for it.
struct SequentialOptotypeSession: Equatable, Sendable {
    static let requiredTargetCount = 7

    let targets: [OptotypeDirection]
    private(set) var responses: [OptotypeResponse] = []

    init?(targets: [OptotypeDirection]) {
        guard targets.count == Self.requiredTargetCount else { return nil }
        self.targets = targets
    }

    var currentIndex: Int { responses.count }

    var currentTarget: OptotypeDirection? {
        guard !isComplete else { return nil }
        return targets[currentIndex]
    }

    var isComplete: Bool {
        responses.count == Self.requiredTargetCount
    }

    /// Records at most one answer and advances at most one target per call.
    /// `nil` represents an invalid or incomplete voice answer and never moves
    /// the session forward. `.notVisible` is a complete, auditable answer: it
    /// advances once and is scored incorrect against every direction target.
    @discardableResult
    mutating func submit(_ response: OptotypeResponse?) -> SequentialOptotypeSubmissionResult {
        guard !isComplete, let response else { return .rejected }

        responses.append(response)
        return isComplete ? .completed : .advanced
    }

    /// Explicitly models a retry without changing the displayed target.
    @discardableResult
    func retryCurrentTarget() -> OptotypeDirection? {
        currentTarget
    }
}
