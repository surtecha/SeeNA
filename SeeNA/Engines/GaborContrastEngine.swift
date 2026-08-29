import Foundation

enum GaborScorer {
    static func correctCount(targets: [GaborOrientation], responses: [GaborResponse]) -> Int {
        guard targets.count == 7, responses.count == 7 else { return 0 }
        return zip(targets, responses).reduce(0) { count, pair in
            count + (pair.1.matches(pair.0) ? 1 : 0)
        }
    }

    static func correctCount(targets: [GaborOrientation], responses: [GaborOrientation]) -> Int {
        correctCount(targets: targets, responses: responses.map(GaborResponse.init))
    }

    static func outcome(correctCount: Int, hasExactlySevenResponses: Bool) -> TrialOutcome {
        TrialScorer.outcome(
            correctCount: correctCount,
            hasExactlySevenResponses: hasExactlySevenResponses
        )
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
        case .reliableCompletion: return "ORIENTATION TASK COMPLETE"
        case .repeatNeeded: return "REPEAT NEEDED"
        }
    }

    var screenMessage: String {
        switch self {
        case .reliableCompletion: return "Orientation task complete"
        case .repeatNeeded: return "Finished, but this orientation task needs repeating"
        }
    }

    func spokenMessage(for eye: Eye) -> String {
        switch self {
        case .reliableCompletion:
            return "\(eye.displayName) eye non-clinical Gabor orientation task complete."
        case .repeatNeeded:
            return "\(eye.displayName) eye orientation task finished, but it needs repeating."
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
    static let contrastLevels = [0.40, 0.25, 0.16, 0.10, 0.06]

    let eye: Eye
    private var index = 0
    private var borderlineRepeats = 0
    private var trials: [GaborTrial] = []
    private var isComplete = false
    private var completedResult: GaborScreeningResult?

    init(eye: Eye) {
        self.eye = eye
    }

    var nextAction: GaborAction {
        guard !isComplete else { return .completed(completedResult ?? unreliableResult()) }
        return .test(contrast: Self.contrastLevels[index])
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
              abs(trial.contrast - requestedContrast) <= 0.000_001 else {
            // A delayed block from another contrast level cannot be allowed to
            // advance the staircase or become evidence for the public POC
            // completion state.
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)
        }
        trials.append(trial)

        switch trial.outcome {
        case .pass:
            borderlineRepeats = 0
            if index == Self.contrastLevels.count - 1 {
                isComplete = true
                let result = result()
                completedResult = result
                return .completed(result)
            }
            index += 1
            return nextAction

        case .fail:
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)

        case .borderline:
            if borderlineRepeats == 0 {
                borderlineRepeats = 1
                return nextAction
            }
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)

        case .invalid:
            isComplete = true
            let result = unreliableResult()
            completedResult = result
            return .completed(result)
        }
    }

    private func result() -> GaborScreeningResult {
        return GaborScreeningResult(
            eye: eye,
            status: .completed,
            responseConsistency: trials.contains(where: { $0.outcome == .borderline }) ? .moderate : .good
        )
    }

    private func unreliableResult() -> GaborScreeningResult {
        GaborScreeningResult(
            eye: eye,
            status: .unreliableMeasurement,
            responseConsistency: .poor
        )
    }
}
