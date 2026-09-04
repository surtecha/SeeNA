import Foundation

enum GaborScorer {
    /// Exact binomial probability that random binary guessing reaches the
    /// active 7-of-8 pass threshold: P(X >= 7), X ~ Binomial(8, 0.5).
    static let randomGuessPassProbability = 0.035_156_25

    static func correctCount(targets: [GaborOrientation], responses: [GaborResponse]) -> Int {
        guard SequentialGaborSession.isValidTargetSequence(targets),
              responses.count == SequentialGaborSession.requiredTargetCount else {
            return 0
        }
        return zip(targets, responses).reduce(0) { count, pair in
            count + (pair.1.matches(pair.0) ? 1 : 0)
        }
    }

    static func correctCount(targets: [GaborOrientation], responses: [GaborOrientation]) -> Int {
        correctCount(targets: targets, responses: responses.map(GaborResponse.init))
    }

    static func outcome(correctCount: Int, responseCount: Int) -> TrialOutcome {
        guard responseCount == SequentialGaborSession.requiredTargetCount else {
            return .invalid
        }
        switch correctCount {
        case 7...SequentialGaborSession.requiredTargetCount: return .pass
        case 6: return .borderline
        case 0...5: return .fail
        default: return .invalid
        }
    }
}

enum GaborAction: Equatable, Sendable {
    case test(contrast: Double)
    case completed(GaborScreeningResult)
}

enum GaborCompletionDisposition: Equatable, Sendable {
    case reliableCompletion
    case repeatNeeded

    var phaseTitle: String {
        switch self {
        case .reliableCompletion: return "TASK COMPLETE"
        case .repeatNeeded: return "REPEAT NEEDED"
        }
    }

    var screenMessage: String {
        switch self {
        case .reliableCompletion: return "Pattern task complete"
        case .repeatNeeded: return "The pattern task needs another try"
        }
    }

    func spokenMessage(for eye: Eye) -> String {
        switch self {
        case .reliableCompletion:
            return "\(eye.displayName) eye pattern task complete."
        case .repeatNeeded:
            return "The \(eye.displayName.lowercased()) eye pattern task needs another try."
        }
    }
}

enum GaborCompletionPolicy {
    static func disposition(
        for result: GaborScreeningResult,
        integrityIsValid: Bool
    ) -> GaborCompletionDisposition {
        result.status == .completed && integrityIsValid
            ? .reliableCompletion
            : .repeatNeeded
    }
}

struct GaborContrastEngine: Sendable {
    /// The active task presents one clearly visible contrast. The stored block
    /// retains the exact balanced targets, answers, score, quality, and raster
    /// geometry for deterministic audit; it is not a contrast threshold.
    static let contrastLevels = [0.40]

    private static let tolerance = 0.000_001
    private static let advisoryDiscardReasons: Set<BlockDiscardReason> = [
        .gazeUnavailable, .gazeOffCentre
    ]

    let eye: Eye
    private var trials: [GaborTrial] = []
    private var isComplete = false
    private var completedResult: GaborScreeningResult?

    init(eye: Eye) {
        self.eye = eye
    }

    var nextAction: GaborAction {
        guard !isComplete else { return .completed(completedResult ?? unreliableResult()) }
        return .test(contrast: Self.contrastLevels[0])
    }

    mutating func submit(_ trial: GaborTrial) -> GaborAction {
        if isComplete { return .completed(completedResult ?? unreliableResult()) }
        guard trial.eye == eye else {
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)
        }
        guard case .test(let requestedContrast) = nextAction,
              abs(trial.contrast - requestedContrast) <= Self.tolerance,
              Self.isWellFormedTrialEvidence(trial) else {
            // Stale, incomplete, or quality-invalid evidence can never produce
            // a completed task. The caller presents its repeat path.
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)
        }
        trials.append(trial)
        isComplete = true
        let result = result()
        completedResult = result
        return .completed(result)
    }

    private func result() -> GaborScreeningResult {
        return GaborScreeningResult(
            eye: eye,
            status: .completed,
            responseConsistency: .good
        )
    }

    private func unreliableResult() -> GaborScreeningResult {
        GaborScreeningResult(
            eye: eye,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )
    }

    /// Shared by the state machine and replay validator so completion and
    /// persisted-integrity checks cannot drift apart.
    static func isWellFormedTrialEvidence(_ trial: GaborTrial) -> Bool {
        guard let quality = trial.quality,
              let geometry = trial.presentationGeometry,
              geometry.isValidCurrentEvidence,
              quality.trackingCoverage.isFinite,
              (0...1).contains(quality.trackingCoverage),
              quality.gazeCoverage.map({ $0.isFinite && (0...1).contains($0) }) != false,
              quality.phoneStable,
              quality.headPoseValid,
              quality.distanceStable,
              quality.audioLevelAdequate,
              quality.targetGeometryValid,
              quality.discardReasons.allSatisfy({ advisoryDiscardReasons.contains($0) }),
              trial.contrast.isFinite,
              abs(trial.contrast - contrastLevels[0]) <= tolerance,
              SequentialGaborSession.isValidTargetSequence(trial.targets),
              trial.responses.count == SequentialGaborSession.requiredTargetCount else {
            return false
        }

        let correct = GaborScorer.correctCount(targets: trial.targets, responses: trial.responses)
        return trial.correctCount == correct &&
            trial.outcome != .invalid &&
            trial.outcome == GaborScorer.outcome(
                correctCount: correct,
                responseCount: trial.responses.count
            )
    }
}
