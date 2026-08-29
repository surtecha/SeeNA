import Foundation

enum GaborScorer {
    static func correctCount(targets: [GaborOrientation], responses: [GaborOrientation]) -> Int {
        guard targets.count == 7, responses.count == 7 else { return 0 }
        return zip(targets, responses).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 1 : 0)
        }
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

struct GaborContrastEngine: Sendable {
    static let contrastLevels = [0.40, 0.25, 0.16, 0.10, 0.06]

    let eye: Eye
    private var index = 0
    private var borderlineRepeats = 0
    private var trials: [GaborTrial] = []
    private var isComplete = false

    init(eye: Eye) {
        self.eye = eye
    }

    var nextAction: GaborAction {
        guard !isComplete else { return .completed(result()) }
        return .test(contrast: Self.contrastLevels[index])
    }

    mutating func submit(_ trial: GaborTrial) -> GaborAction {
        guard trial.eye == eye, !isComplete else {
            isComplete = true
            return .completed(unreliableResult())
        }
        trials.append(trial)

        switch trial.outcome {
        case .pass:
            borderlineRepeats = 0
            if index == Self.contrastLevels.count - 1 {
                isComplete = true
                return .completed(result())
            }
            index += 1
            return nextAction

        case .fail:
            isComplete = true
            return .completed(result())

        case .borderline:
            if borderlineRepeats == 0 {
                borderlineRepeats = 1
                return nextAction
            }
            isComplete = true
            return .completed(result())

        case .invalid:
            isComplete = true
            return .completed(unreliableResult())
        }
    }

    private func result() -> GaborScreeningResult {
        let passed = trials.filter { $0.outcome == .pass }.map(\.contrast)
        guard let lowest = passed.min() else { return unreliableResult() }
        return GaborScreeningResult(
            eye: eye,
            status: .completed,
            lowestPassedContrast: lowest,
            testedContrasts: trials.map(\.contrast),
            responseConsistency: trials.contains(where: { $0.outcome == .borderline }) ? .moderate : .good
        )
    }

    private func unreliableResult() -> GaborScreeningResult {
        GaborScreeningResult(
            eye: eye,
            status: .unreliableMeasurement,
            lowestPassedContrast: nil,
            testedContrasts: trials.map(\.contrast),
            responseConsistency: .poor
        )
    }
}
