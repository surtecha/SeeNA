import Foundation

struct ScreeningCandidate: Equatable, Sendable {
    let diopter: Double
    var distanceMetres: Double { 1 / abs(diopter) }
}

enum SearchStage: Equatable, Sendable {
    case coarse
    case fine
    case confirmation
    case boundaryConfirmation
}

enum SearchAction: Equatable, Sendable {
    case test(candidate: ScreeningCandidate, stage: SearchStage)
    case completed(EyeScreeningResult)
}

struct ThresholdSearchEngine: Sendable {
    private enum Phase: Sendable {
        case coarse(index: Int)
        case fine(lastFail: Double, firstPass: Double)
        case confirm(lastFail: Double?, firstPass: Double, initialActualDiopter: Double, disagreements: Int)
        case confirmStrongBoundary(disagreements: Int)
        case completed
    }

    static let coarseCandidates = [-0.50, -1.00, -1.50, -2.00, -2.50]

    let eye: Eye
    private var phase: Phase = .coarse(index: 0)
    private var borderlineRepeats: [Double: Int] = [:]
    private var invalidRetries: [Double: Int] = [:]

    init(eye: Eye) {
        self.eye = eye
    }

    var nextAction: SearchAction {
        switch phase {
        case .coarse(let index):
            return .test(candidate: ScreeningCandidate(diopter: Self.coarseCandidates[index]), stage: .coarse)
        case .fine(let lastFail, let firstPass):
            return .test(candidate: ScreeningCandidate(diopter: RefractionEstimator.roundedToQuarterDiopter((lastFail + firstPass) / 2)), stage: .fine)
        case .confirm(_, let firstPass, _, _):
            return .test(candidate: ScreeningCandidate(diopter: firstPass), stage: .confirmation)
        case .confirmStrongBoundary:
            return .test(candidate: ScreeningCandidate(diopter: -2.50), stage: .boundaryConfirmation)
        case .completed:
            return .completed(unreliableResult())
        }
    }

    mutating func submit(block: TrialBlock) -> SearchAction {
        guard block.eye == eye else {
            phase = .completed
            return .completed(unreliableResult())
        }
        guard block.quality.isValid, block.outcome != .invalid else {
            let count = invalidRetries[block.candidateDiopter, default: 0] + 1
            invalidRetries[block.candidateDiopter] = count
            if count > 2 {
                phase = .completed
                return .completed(unreliableResult())
            }
            return nextAction
        }
        if block.outcome == .borderline {
            let count = borderlineRepeats[block.candidateDiopter, default: 0] + 1
            borderlineRepeats[block.candidateDiopter] = count
            if count > 1 {
                phase = .completed
                return .completed(unreliableResult())
            }
            return nextAction
        }

        switch phase {
        case .coarse(let index):
            if block.outcome == .pass {
                let firstPass = Self.coarseCandidates[index]
                let lastFail = index == 0 ? nil : Self.coarseCandidates[index - 1]
                if let lastFail {
                    phase = .fine(lastFail: lastFail, firstPass: firstPass)
                } else {
                    phase = .confirm(lastFail: nil, firstPass: firstPass, initialActualDiopter: actualDiopter(block), disagreements: 0)
                }
            } else if index == Self.coarseCandidates.count - 1 {
                phase = .confirmStrongBoundary(disagreements: 0)
            } else {
                phase = .coarse(index: index + 1)
            }

        case .fine(let lastFail, let firstPass):
            let tested = block.candidateDiopter
            let refinedLastFail = block.outcome == .fail ? tested : lastFail
            let refinedFirstPass = block.outcome == .pass ? tested : firstPass
            phase = .confirm(
                lastFail: refinedLastFail,
                firstPass: refinedFirstPass,
                initialActualDiopter: actualDiopter(block),
                disagreements: 0
            )

        case .confirm(let lastFail, let firstPass, let initialActualDiopter, let disagreements):
            guard block.outcome == .pass else {
                if disagreements == 0 {
                    phase = .confirm(lastFail: lastFail, firstPass: firstPass, initialActualDiopter: initialActualDiopter, disagreements: 1)
                    return nextAction
                }
                phase = .completed
                return .completed(unreliableResult())
            }
            phase = .completed
            if lastFail == nil, firstPass == -0.50 {
                return .completed(boundaryResult(status: .noMyopiaDetectedWithinRange, block: block))
            }
            return .completed(validResult(lastFail: lastFail, firstPass: firstPass, initialActualDiopter: initialActualDiopter, block: block))

        case .confirmStrongBoundary(let disagreements):
            guard block.outcome == .fail else {
                if disagreements == 0 {
                    phase = .confirmStrongBoundary(disagreements: 1)
                    return nextAction
                }
                phase = .completed
                return .completed(unreliableResult())
            }
            phase = .completed
            return .completed(boundaryResult(status: .strongerThanSupportedRange, block: block))

        case .completed:
            return .completed(unreliableResult())
        }
        return nextAction
    }

    private func actualDiopter(_ block: TrialBlock) -> Double {
        RefractionEstimator.diopter(forDistanceMetres: block.actualMedianDistanceMetres) ?? block.candidateDiopter
    }

    private func validResult(lastFail: Double?, firstPass: Double, initialActualDiopter: Double, block: TrialBlock) -> EyeScreeningResult {
        let actual = actualDiopter(block)
        let display = RefractionEstimator.roundedToQuarterDiopter(actual)
        return EyeScreeningResult(
            eye: eye,
            status: .validEstimate,
            lastFailDiopter: lastFail,
            firstPassDiopter: firstPass,
            displayedEstimateDiopter: display,
            thresholdDistanceMetres: block.actualMedianDistanceMetres,
            sensorUncertaintyDiopter: RefractionEstimator.sensorUncertainty(
                distanceMetres: block.actualMedianDistanceMetres,
                standardDeviationMetres: block.distanceStandardDeviation
            ),
            repeatabilityDiopter: abs(initialActualDiopter - actual),
            trackingQuality: block.quality.trackingCoverage >= 0.95 ? .good : .moderate,
            responseConsistency: .good,
            warnings: baseWarnings(for: block)
        )
    }

    private func boundaryResult(status: ScreeningStatus, block: TrialBlock) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: status == .strongerThanSupportedRange ? -2.50 : nil,
            firstPassDiopter: status == .noMyopiaDetectedWithinRange ? -0.50 : nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: block.actualMedianDistanceMetres,
            sensorUncertaintyDiopter: RefractionEstimator.sensorUncertainty(
                distanceMetres: block.actualMedianDistanceMetres,
                standardDeviationMetres: block.distanceStandardDeviation
            ),
            repeatabilityDiopter: 0,
            trackingQuality: block.quality.trackingCoverage >= 0.95 ? .good : .moderate,
            responseConsistency: .good,
            warnings: baseWarnings(for: block)
        )
    }

    private func unreliableResult() -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: .unreliableMeasurement,
            lastFailDiopter: nil,
            firstPassDiopter: nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: nil,
            sensorUncertaintyDiopter: nil,
            repeatabilityDiopter: nil,
            trackingQuality: .poor,
            responseConsistency: .poor,
            warnings: [.researchPrototype, .notPrescription, .clinicalAccuracyNotEstablished]
        )
    }

    private func baseWarnings(for block: TrialBlock) -> [ResultWarning] {
        var warnings: [ResultWarning] = [.researchPrototype, .notPrescription, .hyperopiaNotAssessed, .clinicalAccuracyNotEstablished]
        if block.responseSource == .operatorInput { warnings.append(.operatorResponseUsed) }
        return warnings
    }
}
