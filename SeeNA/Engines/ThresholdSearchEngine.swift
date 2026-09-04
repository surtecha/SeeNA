import Foundation

struct ScreeningCandidate: Equatable, Sendable {
    let diopter: Double
    var distanceMetres: Double {
        RefractionEstimator.distanceMetres(forMyopicDiopter: diopter) ?? .nan
    }
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
        case fine(lastFail: Double, firstPass: Double, firstPassActualDistanceMetres: Double)
        case confirm(lastFail: Double?, firstPass: Double, initialActualDistanceMetres: Double, disagreements: Int)
        case confirmStrongBoundary(disagreements: Int)
        case completed
    }

    // The active enlarged phone task is one complete, balanced block at the
    // close 40 cm setup distance. Its score remains available in TrialBlock for
    // answer review, but the active path deliberately does not interpret the
    // score as a threshold, referral signal, or refractive measurement.
    static let coarseCandidates = [-2.50]
    static let maximumActivePhoneLocatorDistanceMetres = 0.40

    // Keep the pre-existing range available only to a future approved
    // five-arcminute protocol. Changing the practical phone journey must not
    // silently redefine a separately validated protocol's range.
    private static let validatedProtocolCoarseCandidates = [-2.50, -1.25, -0.50]

    let eye: Eye
    private let protocolDescriptor: LandoltProtocolDescriptor
    private var phase: Phase = .coarse(index: 0)
    private var borderlineRepeats: [Double: Int] = [:]
    private var invalidRetries: [Double: Int] = [:]
    /// The measured distance for the nearest coarse candidate that most
    /// recently passed. The active phone locator retains distance only as
    /// navigation/search state; it never turns that distance into a refractive
    /// result. A future approved clinical protocol may use two measured
    /// distances to calculate a repeatability component.
    private var actualDistanceForMostRecentPass: Double?

    init(
        eye: Eye,
        protocolDescriptor: LandoltProtocolDescriptor = .activePhoneLocator
    ) {
        self.eye = eye
        self.protocolDescriptor = protocolDescriptor
    }

    private var searchCandidates: [Double] {
        protocolDescriptor.presentationMode == .phonePOCLocator
            ? Self.coarseCandidates
            : Self.validatedProtocolCoarseCandidates
    }

    private var isActivePhoneTask: Bool {
        protocolDescriptor.presentationMode == .phonePOCLocator
    }

    var nextAction: SearchAction {
        switch phase {
        case .coarse(let index):
            return .test(candidate: ScreeningCandidate(diopter: searchCandidates[index]), stage: .coarse)
        case .fine(let lastFail, let firstPass, _):
            return .test(candidate: ScreeningCandidate(diopter: RefractionEstimator.roundedToQuarterDiopter((lastFail + firstPass) / 2)), stage: .fine)
        case .confirm(_, let firstPass, _, _):
            return .test(candidate: ScreeningCandidate(diopter: firstPass), stage: .confirmation)
        case .confirmStrongBoundary:
            return .test(
                candidate: ScreeningCandidate(diopter: searchCandidates[0]),
                stage: .boundaryConfirmation
            )
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
              block.candidateDiopter < 0,
              block.targetDistanceMetres.isFinite,
              block.targetDistanceMetres > 0,
              block.actualMedianDistanceMetres.isFinite,
              block.actualMedianDistanceMetres > 0,
              block.distanceStandardDeviation.isFinite,
              block.distanceStandardDeviation >= 0,
              block.distanceStandardDeviation < block.actualMedianDistanceMetres,
              block.quality.trackingCoverage.isFinite,
              (0...1).contains(block.quality.trackingCoverage),
              block.quality.gazeCoverage.map({ $0.isFinite && (0...1).contains($0) }) != false,
              abs(block.candidateDiopter - requestedCandidate.diopter) <= 0.000_001,
              abs(block.targetDistanceMetres - requestedCandidate.distanceMetres) <= 0.000_001,
              !isActivePhoneTask ||
                requestedCandidate.distanceMetres <= Self.maximumActivePhoneLocatorDistanceMetres + 0.000_001 else {
            phase = .completed
            return .completed(unreliableResult())
        }
        guard block.quality.isValid,
              block.quality.phoneStable,
              block.quality.headPoseValid,
              block.quality.distanceStable,
              block.quality.audioLevelAdequate,
              block.quality.targetGeometryValid,
              block.outcome != .invalid,
              blockHasCompleteBalancedEvidence(block) else {
            let count = invalidRetries[block.candidateDiopter, default: 0] + 1
            invalidRetries[block.candidateDiopter] = count
            if count > 2 {
                phase = .completed
                return .completed(unreliableResult())
            }
            return nextAction
        }

        // One quality-valid block is the whole active task. Pass, borderline,
        // and fail remain auditable score labels only; none changes the neutral
        // completion status or creates a medical recommendation.
        if isActivePhoneTask {
            phase = .completed
            return .completed(qualitativeResult(
                status: .experimentalTaskCompleted,
                action: .unavailable,
                block: block
            ))
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
                guard let firstPassActualDistance = actualDistanceForMostRecentPass else {
                    phase = .completed
                    return .completed(unreliableResult())
                }
                phase = .fine(
                    lastFail: searchCandidates[index],
                    firstPass: searchCandidates[index - 1],
                    firstPassActualDistanceMetres: firstPassActualDistance
                )
            } else if index == searchCandidates.count - 1 {
                phase = .confirm(
                    lastFail: nil,
                    firstPass: searchCandidates[index],
                    initialActualDistanceMetres: block.actualMedianDistanceMetres,
                    disagreements: 0
                )
            } else {
                actualDistanceForMostRecentPass = block.actualMedianDistanceMetres
                phase = .coarse(index: index + 1)
            }

        case .fine(let lastFail, let firstPass, let firstPassActualDistance):
            let tested = block.candidateDiopter
            let refinedLastFail = block.outcome == .fail ? tested : lastFail
            let refinedFirstPass = block.outcome == .pass ? tested : firstPass
            let refinedFirstPassActualDistance = block.outcome == .pass
                ? block.actualMedianDistanceMetres
                : firstPassActualDistance
            if abs(refinedLastFail - refinedFirstPass) > 0.25 + 0.000_001 {
                phase = .fine(
                    lastFail: refinedLastFail,
                    firstPass: refinedFirstPass,
                    firstPassActualDistanceMetres: refinedFirstPassActualDistance
                )
            } else {
                phase = .confirm(
                    lastFail: refinedLastFail,
                    firstPass: refinedFirstPass,
                    initialActualDistanceMetres: refinedFirstPassActualDistance,
                    disagreements: 0
                )
            }

        case .confirm(let lastFail, let firstPass, let initialActualDistance, let disagreements):
            guard block.outcome == .pass else {
                if disagreements == 0 {
                    phase = .confirm(
                        lastFail: lastFail,
                        firstPass: firstPass,
                        initialActualDistanceMetres: initialActualDistance,
                        disagreements: 1
                    )
                    return nextAction
                }
                phase = .completed
                return .completed(unreliableResult())
            }
            phase = .completed
            if lastFail == nil, firstPass == searchCandidates.last {
                return .completed(completedBoundaryResult(
                    numericStatus: .noMyopiaDetectedWithinRange,
                    qualitativeStatus: .experimentalFarthestTargetPassed,
                    block: block
                ))
            }
            return .completed(completedThresholdResult(
                lastFail: lastFail,
                firstPass: firstPass,
                initialActualDistanceMetres: initialActualDistance,
                block: block
            ))

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
            return .completed(completedBoundaryResult(
                numericStatus: .strongerThanSupportedRange,
                qualitativeStatus: .experimentalAdverseBoundary,
                block: block
            ))

        case .completed:
            return .completed(unreliableResult())
        }
        return nextAction
    }

    private func blockHasCompleteBalancedEvidence(_ block: TrialBlock) -> Bool {
        guard SequentialOptotypeSession.isValidTargetSequence(block.targets),
              block.responses.count == SequentialOptotypeSession.requiredTargetCount else {
            return false
        }
        let correctCount = zip(block.targets, block.responses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }
        return block.correctCount == correctCount &&
            block.outcome == TrialScorer.outcome(
                correctCount: correctCount,
                responseCount: block.responses.count
            )
    }

    /// Numeric construction is a separate, future-only branch. In particular,
    /// `phonePOCLocator` short-circuits before any far-point conversion or
    /// numeric `EyeScreeningResult` is constructed.
    private var mayConstructValidatedNumericResult: Bool {
        protocolDescriptor.presentationMode == .clinicalFiveArcMinute &&
            NumericResultEligibility.protocolReleaseIsApproved(protocolDescriptor)
    }

    private func completedThresholdResult(
        lastFail: Double?,
        firstPass: Double,
        initialActualDistanceMetres: Double,
        block: TrialBlock
    ) -> EyeScreeningResult {
        guard mayConstructValidatedNumericResult else {
            return qualitativeResult(
                status: .experimentalThresholdObserved,
                action: .professionalReviewRecommended,
                block: block
            )
        }
        return validatedNumericThresholdResult(
            lastFail: lastFail,
            firstPass: firstPass,
            initialActualDistanceMetres: initialActualDistanceMetres,
            block: block
        )
    }

    private func validatedNumericThresholdResult(
        lastFail: Double?,
        firstPass: Double,
        initialActualDistanceMetres: Double,
        block: TrialBlock
    ) -> EyeScreeningResult {
        guard let actual = RefractionEstimator.diopter(
                forDistanceMetres: block.actualMedianDistanceMetres
              ),
              let initialActual = RefractionEstimator.diopter(
                forDistanceMetres: initialActualDistanceMetres
              ),
              let uncertainty = RefractionEstimator.sensorUncertainty(
                distanceMetres: block.actualMedianDistanceMetres,
                standardDeviationMetres: block.distanceStandardDeviation
              ) else { return unreliableResult() }
        let display = RefractionEstimator.roundedToQuarterDiopter(actual)
        guard display.isFinite else { return unreliableResult() }
        let result = EyeScreeningResult(
            eye: eye,
            status: .validEstimate,
            lastFailDiopter: lastFail,
            firstPassDiopter: firstPass,
            displayedEstimateDiopter: display,
            thresholdDistanceMetres: block.actualMedianDistanceMetres,
            sensorUncertaintyDiopter: uncertainty,
            repeatabilityDiopter: abs(initialActual - actual),
            trackingQuality: block.quality.trackingCoverage >= 0.95 ? .good : .moderate,
            responseConsistency: .good,
            warnings: baseWarnings(for: block)
        )
        guard ResultIntegrityValidator.validate(result).isValid else { return unreliableResult() }
        return result
    }

    private func completedBoundaryResult(
        numericStatus: ScreeningStatus,
        qualitativeStatus: ScreeningStatus,
        block: TrialBlock
    ) -> EyeScreeningResult {
        guard mayConstructValidatedNumericResult else {
            let action: ScreeningAction = qualitativeStatus == .experimentalFarthestTargetPassed
                ? .routineExamRecommended
                : .professionalReviewRecommended
            return qualitativeResult(status: qualitativeStatus, action: action, block: block)
        }
        return validatedNumericBoundaryResult(status: numericStatus, block: block)
    }

    private func validatedNumericBoundaryResult(
        status: ScreeningStatus,
        block: TrialBlock
    ) -> EyeScreeningResult {
        guard let uncertainty = RefractionEstimator.sensorUncertainty(
            distanceMetres: block.actualMedianDistanceMetres,
            standardDeviationMetres: block.distanceStandardDeviation
        ) else { return unreliableResult() }
        let result = EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: status == .strongerThanSupportedRange ? searchCandidates.first : nil,
            firstPassDiopter: status == .noMyopiaDetectedWithinRange ? searchCandidates.last : nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: block.actualMedianDistanceMetres,
            sensorUncertaintyDiopter: uncertainty,
            repeatabilityDiopter: 0,
            trackingQuality: block.quality.trackingCoverage >= 0.95 ? .good : .moderate,
            responseConsistency: .good,
            warnings: baseWarnings(for: block)
        )
        guard ResultIntegrityValidator.validate(result).isValid else { return unreliableResult() }
        return result
    }

    private func qualitativeResult(
        status: ScreeningStatus,
        action: ScreeningAction,
        block: TrialBlock
    ) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: nil,
            firstPassDiopter: nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: nil,
            sensorUncertaintyDiopter: nil,
            repeatabilityDiopter: nil,
            trackingQuality: block.quality.trackingCoverage >= 0.95 ? .good : .moderate,
            responseConsistency: .good,
            warnings: baseWarnings(for: block),
            recommendedAction: action
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
