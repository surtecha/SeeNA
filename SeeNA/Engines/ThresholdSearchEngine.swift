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
        case fine(lastFail: Double, firstPass: Double, firstPassActualDiopter: Double)
        case confirm(lastFail: Double?, firstPass: Double, initialActualDiopter: Double, disagreements: Int)
        case confirmStrongBoundary(disagreements: Int)
        case completed
    }

    // Begin at the closest supported distance so participants only move farther
    // from the phone after demonstrating that they can resolve the target.
    // Three large outward jumps minimise walking and stops. A bounded binary
    // refinement then narrows the first pass/fail bracket to 0.25 D.
    static let coarseCandidates = [-2.50, -1.25, -0.50]

    let eye: Eye
    private var phase: Phase = .coarse(index: 0)
    private var borderlineRepeats: [Double: Int] = [:]
    private var invalidRetries: [Double: Int] = [:]
    /// The sensor-derived diopter for the nearest coarse candidate that most
    /// recently passed. Fine refinement carries this value forward so the
    /// final repeatability figure compares two real measured distances rather
    /// than a nominal target distance.
    private var actualDiopterForMostRecentPass: Double?

    init(eye: Eye) {
        self.eye = eye
    }

    var nextAction: SearchAction {
        switch phase {
        case .coarse(let index):
            return .test(candidate: ScreeningCandidate(diopter: Self.coarseCandidates[index]), stage: .coarse)
        case .fine(let lastFail, let firstPass, _):
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
        guard case .test(let requestedCandidate, _) = nextAction,
              block.candidateDiopter.isFinite,
              block.targetDistanceMetres.isFinite,
              abs(block.candidateDiopter - requestedCandidate.diopter) <= 0.000_001,
              abs(block.targetDistanceMetres - requestedCandidate.distanceMetres) <= 0.000_001 else {
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
            if block.outcome == .fail {
                guard index > 0 else {
                    phase = .confirmStrongBoundary(disagreements: 0)
                    return nextAction
                }

                // The current, farther candidate is the first failure. The
                // preceding, closer candidate is the nearest established pass.
                phase = .fine(
                    lastFail: Self.coarseCandidates[index],
                    firstPass: Self.coarseCandidates[index - 1],
                    firstPassActualDiopter: actualDiopterForMostRecentPass
                        ?? Self.coarseCandidates[index - 1]
                )
            } else if index == Self.coarseCandidates.count - 1 {
                phase = .confirm(
                    lastFail: nil,
                    firstPass: Self.coarseCandidates[index],
                    initialActualDiopter: actualDiopter(block),
                    disagreements: 0
                )
            } else {
                actualDiopterForMostRecentPass = actualDiopter(block)
                phase = .coarse(index: index + 1)
            }

        case .fine(let lastFail, let firstPass, let firstPassActualDiopter):
            let tested = block.candidateDiopter
            let refinedLastFail = block.outcome == .fail ? tested : lastFail
            let refinedFirstPass = block.outcome == .pass ? tested : firstPass
            let refinedFirstPassActual = block.outcome == .pass
                ? actualDiopter(block)
                : firstPassActualDiopter
            if abs(refinedLastFail - refinedFirstPass) > 0.25 + 0.000_001 {
                phase = .fine(
                    lastFail: refinedLastFail,
                    firstPass: refinedFirstPass,
                    firstPassActualDiopter: refinedFirstPassActual
                )
            } else {
                phase = .confirm(
                    lastFail: refinedLastFail,
                    firstPass: refinedFirstPass,
                    initialActualDiopter: refinedFirstPassActual,
                    disagreements: 0
                )
            }

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
