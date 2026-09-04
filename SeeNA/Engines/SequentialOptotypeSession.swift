import Foundation

enum SequentialOptotypeSubmissionResult: Equatable, Sendable {
    case rejected
    case advanced
    case completed
}

/// Produces the active eight-target Landolt sequence.
///
/// Every direction appears exactly twice. Adjacent targets never repeat, so a
/// participant cannot receive an accidental run of identical openings.
enum LandoltTargetSequence {
    static func make() -> [OptotypeDirection] {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    static func make<R: RandomNumberGenerator>(
        using generator: inout R
    ) -> [OptotypeDirection] {
        let candidates = OptotypeDirection.allCases.flatMap { direction in
            Array(repeating: direction, count: 2)
        }

        for _ in 0..<64 {
            let shuffled = candidates.shuffled(using: &generator)
            if SequentialOptotypeSession.isValidTargetSequence(shuffled) {
                return shuffled
            }
        }

        // Deterministic valid fallback if repeated random shuffles do not find
        // an eligible order. It preserves both balance and no-repeat rules.
        return [.up, .right, .down, .left, .up, .right, .down, .left]
    }
}

/// Owns the answer-gated progression through one eight-target Landolt block.
/// A target remains current until one valid direction is submitted for it.
struct SequentialOptotypeSession: Equatable, Sendable {
    static let requiredTargetCount = 8

    let targets: [OptotypeDirection]
    private(set) var responses: [OptotypeResponse] = []

    init?(targets: [OptotypeDirection]) {
        guard Self.isValidTargetSequence(targets) else { return nil }
        self.targets = targets
    }

    static func isValidTargetSequence(_ targets: [OptotypeDirection]) -> Bool {
        guard targets.count == requiredTargetCount,
              OptotypeDirection.allCases.allSatisfy({ direction in
                  targets.filter { $0 == direction }.count == 2
              }) else { return false }
        return !zip(targets, targets.dropFirst()).contains { $0 == $1 }
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
