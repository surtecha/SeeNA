import Foundation

/// Machine-readable consistency failures for an `EyeScreeningResult`.
///
/// These checks are intentionally limited to local data integrity. A passing
/// validation does not establish clinical validity, diagnostic accuracy, or
/// suitability for a prescription.
enum ResultIntegrityIssue: String, CaseIterable, Equatable, Sendable {
    case missingRequiredValue
    case unexpectedValueForStatus
    case nonFiniteDistance
    case nonPositiveDistance
    case nonFiniteDiopter
    case nonQuarterDiopter
    case farPointMismatch
    case invalidBracketOrdering
    case invalidBracketWidth
    case nonFiniteUncertainty
    case negativeUncertainty
    case nonFiniteRepeatability
    case negativeRepeatability
    case invalidBoundaryBracket
    case invalidUnavailableQuality
    case wrongEyeEvidence
    case malformedSupportingEvidence
    case missingSupportingEvidence
    case thresholdOutsideValidatedRange
    case displayedOutsideBracket
    case uncertaintyExceedsBracket
    case repeatabilityExceedsBracket
    case uncertaintyExceedsProfile
}

/// Compact, deterministic result of a local data-consistency validation.
struct ResultIntegrityValidation: Equatable, Sendable {
    let isValid: Bool
    let issues: [ResultIntegrityIssue]
}

/// Validates persisted/output screening values against the app's own far-point
/// calculation and result-state contract. It is not a clinical validator.
enum ResultIntegrityValidator {
    private static let tolerance = 0.000_001
    private static let maximumBracketWidth = 0.25
    private static let supportedClosestDiopter = -2.50
    private static let supportedFarthestDiopter = -0.50

    static func validate(_ result: EyeScreeningResult) -> ResultIntegrityValidation {
        var issues: Set<ResultIntegrityIssue> = []

        switch result.status {
        case .validEstimate:
            validateEstimate(result, issues: &issues)
        case .noMyopiaDetectedWithinRange:
            validateNoMyopiaBoundary(result, issues: &issues)
        case .strongerThanSupportedRange:
            validateStrongBoundary(result, issues: &issues)
        case .unreliableMeasurement:
            validateNoMeasurement(result, requireUnavailableQuality: false, issues: &issues)
        case .deviceUnsupported, .userIneligible:
            validateNoMeasurement(result, requireUnavailableQuality: true, issues: &issues)
        }

        let orderedIssues = issues.sorted { $0.rawValue < $1.rawValue }
        return ResultIntegrityValidation(isValid: orderedIssues.isEmpty, issues: orderedIssues)
    }

    /// Adds an optional audit of compatible local trial witnesses. The supplied
    /// blocks must belong to `result.eye`; this does not establish that they
    /// were the original immutable source of the result.
    static func validate(
        _ result: EyeScreeningResult,
        against trials: [TrialBlock],
        profile: DeviceProfile? = nil
    ) -> ResultIntegrityValidation {
        var issues = Set(validate(result).issues)

        if trials.contains(where: { $0.eye != result.eye }) {
            issues.insert(.wrongEyeEvidence)
        }

        if let profile, let distance = result.thresholdDistanceMetres,
           distance.isFinite,
           (distance < profile.minimumValidatedDistance - tolerance ||
            distance > profile.maximumValidatedDistance + tolerance) {
            issues.insert(.thresholdOutsideValidatedRange)
        }
        validateProfilePrecision(result, profile: profile, issues: &issues)

        switch result.status {
        case .validEstimate:
            guard let lastFail = result.lastFailDiopter,
                  let firstPass = result.firstPassDiopter,
                  let distance = result.thresholdDistanceMetres else { break }
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: lastFail,
                outcome: .fail,
                minimumCount: 1,
                thresholdDistance: nil,
                issues: &issues
            )
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: firstPass,
                outcome: .pass,
                minimumCount: 2,
                thresholdDistance: distance,
                issues: &issues
            )
        case .noMyopiaDetectedWithinRange:
            guard let distance = result.thresholdDistanceMetres else { break }
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: supportedFarthestDiopter,
                outcome: .pass,
                minimumCount: 2,
                thresholdDistance: distance,
                issues: &issues
            )
        case .strongerThanSupportedRange:
            guard let distance = result.thresholdDistanceMetres else { break }
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: supportedClosestDiopter,
                outcome: .fail,
                minimumCount: 2,
                thresholdDistance: distance,
                issues: &issues
            )
        case .unreliableMeasurement, .deviceUnsupported, .userIneligible:
            break
        }

        let orderedIssues = issues.sorted { $0.rawValue < $1.rawValue }
        return ResultIntegrityValidation(isValid: orderedIssues.isEmpty, issues: orderedIssues)
    }

    private static func validateEstimate(
        _ result: EyeScreeningResult,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard let lastFail = result.lastFailDiopter,
              let firstPass = result.firstPassDiopter,
              let displayed = result.displayedEstimateDiopter,
              let distance = result.thresholdDistanceMetres,
              let uncertainty = result.sensorUncertaintyDiopter,
              let repeatability = result.repeatabilityDiopter else {
            issues.insert(.missingRequiredValue)
            return
        }

        validateDistance(distance, issues: &issues)
        validateNonNegative(uncertainty, nonFinite: .nonFiniteUncertainty, negative: .negativeUncertainty, issues: &issues)
        validateNonNegative(repeatability, nonFinite: .nonFiniteRepeatability, negative: .negativeRepeatability, issues: &issues)
        validateBracket(lastFail: lastFail, firstPass: firstPass, issues: &issues)
        validateDisplayedEstimate(displayed, distance: distance, issues: &issues)

        let bracketWidth = lastFail - firstPass
        guard bracketWidth > tolerance, bracketWidth <= maximumBracketWidth + tolerance else { return }
        if displayed < firstPass - tolerance || displayed > lastFail + tolerance {
            issues.insert(.displayedOutsideBracket)
        }
        // A result cannot claim a narrower response bracket than its own
        // sensor uncertainty or repeatability supports.
        if uncertainty.isFinite, uncertainty > bracketWidth + tolerance {
            issues.insert(.uncertaintyExceedsBracket)
        }
        if repeatability.isFinite, repeatability > bracketWidth + tolerance {
            issues.insert(.repeatabilityExceedsBracket)
        }
    }

    private static func validateNoMyopiaBoundary(
        _ result: EyeScreeningResult,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard result.lastFailDiopter == nil,
              result.displayedEstimateDiopter == nil,
              let firstPass = result.firstPassDiopter,
              approximatelyEqual(firstPass, supportedFarthestDiopter) else {
            issues.insert(.invalidBoundaryBracket)
            return
        }
        validateMeasuredBoundaryValues(result, issues: &issues)
    }

    private static func validateStrongBoundary(
        _ result: EyeScreeningResult,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard result.firstPassDiopter == nil,
              result.displayedEstimateDiopter == nil,
              let lastFail = result.lastFailDiopter,
              approximatelyEqual(lastFail, supportedClosestDiopter) else {
            issues.insert(.invalidBoundaryBracket)
            return
        }
        validateMeasuredBoundaryValues(result, issues: &issues)
    }

    private static func validateMeasuredBoundaryValues(
        _ result: EyeScreeningResult,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard let distance = result.thresholdDistanceMetres,
              let uncertainty = result.sensorUncertaintyDiopter,
              let repeatability = result.repeatabilityDiopter else {
            issues.insert(.missingRequiredValue)
            return
        }
        validateDistance(distance, issues: &issues)
        validateNonNegative(uncertainty, nonFinite: .nonFiniteUncertainty, negative: .negativeUncertainty, issues: &issues)
        validateNonNegative(repeatability, nonFinite: .nonFiniteRepeatability, negative: .negativeRepeatability, issues: &issues)
    }

    private static func validateNoMeasurement(
        _ result: EyeScreeningResult,
        requireUnavailableQuality: Bool,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        if result.lastFailDiopter != nil || result.firstPassDiopter != nil ||
            result.displayedEstimateDiopter != nil || result.thresholdDistanceMetres != nil ||
            result.sensorUncertaintyDiopter != nil || result.repeatabilityDiopter != nil {
            issues.insert(.unexpectedValueForStatus)
        }
        if requireUnavailableQuality &&
            (result.trackingQuality != .unavailable || result.responseConsistency != .unavailable) {
            issues.insert(.invalidUnavailableQuality)
        }
    }

    private static func validateDistance(_ distance: Double, issues: inout Set<ResultIntegrityIssue>) {
        guard distance.isFinite else {
            issues.insert(.nonFiniteDistance)
            return
        }
        guard distance > 0 else {
            issues.insert(.nonPositiveDistance)
            return
        }
    }

    private static func validateNonNegative(
        _ value: Double,
        nonFinite: ResultIntegrityIssue,
        negative: ResultIntegrityIssue,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard value.isFinite else {
            issues.insert(nonFinite)
            return
        }
        if value < 0 { issues.insert(negative) }
    }

    private static func validateBracket(
        lastFail: Double,
        firstPass: Double,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard lastFail.isFinite, firstPass.isFinite else {
            issues.insert(.nonFiniteDiopter)
            return
        }
        if !isQuarterDiopter(lastFail) || !isQuarterDiopter(firstPass) {
            issues.insert(.nonQuarterDiopter)
        }
        let width = lastFail - firstPass
        if width <= tolerance { issues.insert(.invalidBracketOrdering) }
        if width > maximumBracketWidth + tolerance { issues.insert(.invalidBracketWidth) }
    }

    private static func validateDisplayedEstimate(
        _ displayed: Double,
        distance: Double,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard displayed.isFinite else {
            issues.insert(.nonFiniteDiopter)
            return
        }
        if !isQuarterDiopter(displayed) { issues.insert(.nonQuarterDiopter) }
        guard distance.isFinite, distance > 0 else { return }
        let expected = RefractionEstimator.roundedToQuarterDiopter(-1 / distance)
        if !approximatelyEqual(displayed, expected) { issues.insert(.farPointMismatch) }
    }

    private static func isQuarterDiopter(_ value: Double) -> Bool {
        approximatelyEqual(value, RefractionEstimator.roundedToQuarterDiopter(value))
    }

    private static func requireWitnesses(
        _ trials: [TrialBlock],
        eye: Eye,
        candidate: Double,
        outcome: TrialOutcome,
        minimumCount: Int,
        thresholdDistance: Double?,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        let candidates = trials.filter {
            $0.eye == eye && approximatelyEqual($0.candidateDiopter, candidate) && $0.outcome == outcome
        }
        let validWitnesses = candidates.filter(isWellFormedWitness)
        if candidates.count != validWitnesses.count { issues.insert(.malformedSupportingEvidence) }
        guard validWitnesses.count >= minimumCount else {
            issues.insert(.missingSupportingEvidence)
            return
        }
        if let thresholdDistance,
           !validWitnesses.contains(where: { approximatelyEqual($0.actualMedianDistanceMetres, thresholdDistance) }) {
            issues.insert(.missingSupportingEvidence)
        }
    }

    private static func isWellFormedWitness(_ block: TrialBlock) -> Bool {
        guard block.quality.isValid,
              block.candidateDiopter.isFinite,
              block.candidateDiopter >= supportedClosestDiopter - tolerance,
              block.candidateDiopter <= supportedFarthestDiopter + tolerance,
              isQuarterDiopter(block.candidateDiopter),
              block.targetDistanceMetres.isFinite,
              block.targetDistanceMetres > 0,
              approximatelyEqual(block.targetDistanceMetres, 1 / abs(block.candidateDiopter)),
              block.actualMedianDistanceMetres.isFinite,
              block.actualMedianDistanceMetres > 0,
              block.distanceStandardDeviation.isFinite,
              block.distanceStandardDeviation >= 0,
              block.targets.count == 7,
              block.responses.count == 7 else {
            return false
        }
        let correctCount = zip(block.targets, block.responses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }
        return block.correctCount == correctCount &&
            block.outcome == TrialScorer.outcome(correctCount: correctCount, hasExactlySevenResponses: true)
    }

    private static func validateProfilePrecision(
        _ result: EyeScreeningResult,
        profile: DeviceProfile?,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        guard let profile,
              let distance = result.thresholdDistanceMetres,
              let uncertainty = result.sensorUncertaintyDiopter,
              distance.isFinite,
              distance > 0,
              uncertainty.isFinite else {
            return
        }
        let maximumDistanceSD = distance < 1
            ? profile.qualityThresholds.maximumDistanceSDNearMetres
            : profile.qualityThresholds.maximumDistanceSDFarMetres
        let maximumUncertainty = maximumDistanceSD / pow(distance, 2)
        if uncertainty > maximumUncertainty + tolerance {
            issues.insert(.uncertaintyExceedsProfile)
        }
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}

/// Local consistency checks for the non-diagnostic Gabor orientation task.
///
/// A valid result here means only that the stored task record can be replayed
/// deterministically. It does not turn the renderer input contrast into a
/// calibrated contrast-sensitivity threshold or a clinical result.
enum GaborResultIntegrityIssue: String, CaseIterable, Equatable, Sendable {
    case missingSupportingEvidence
    case wrongEyeEvidence
    case malformedSupportingEvidence
    case invalidResultState
}

struct GaborResultIntegrityValidation: Equatable, Sendable {
    let isValid: Bool
    let issues: [GaborResultIntegrityIssue]
}

enum GaborResultIntegrityValidator {
    private static let tolerance = 0.000_001

    static func validate(
        _ result: GaborScreeningResult,
        against trials: [GaborTrial]
    ) -> GaborResultIntegrityValidation {
        var issues = Set<GaborResultIntegrityIssue>()

        if trials.isEmpty { issues.insert(.missingSupportingEvidence) }
        if trials.contains(where: { $0.eye != result.eye }) {
            issues.insert(.wrongEyeEvidence)
        }
        if trials.contains(where: { !isWellFormed($0) }) {
            issues.insert(.malformedSupportingEvidence)
        }

        guard issues.isEmpty else { return validation(issues) }

        var replay = GaborContrastEngine(eye: result.eye)
        var replayResult: GaborScreeningResult?
        for (index, trial) in trials.enumerated() {
            let action = replay.submit(trial)
            switch action {
            case .test:
                if index == trials.indices.last { issues.insert(.invalidResultState) }
            case .completed(let completed):
                if index != trials.indices.last {
                    issues.insert(.invalidResultState)
                }
                replayResult = completed
            }
        }

        guard let replayResult,
              replayResult.status == result.status,
              replayResult.responseConsistency == result.responseConsistency else {
            issues.insert(.invalidResultState)
            return validation(issues)
        }

        return validation(issues)
    }

    private static func isWellFormed(_ trial: GaborTrial) -> Bool {
        guard trial.contrast.isFinite,
              trial.contrast > 0,
              trial.contrast <= 1,
              GaborContrastEngine.contrastLevels.contains(where: {
                  abs($0 - trial.contrast) <= tolerance
              }),
              trial.targets.count == SequentialGaborSession.requiredTargetCount,
              trial.responses.count == SequentialGaborSession.requiredTargetCount else {
            return false
        }

        let correct = GaborScorer.correctCount(targets: trial.targets, responses: trial.responses)
        return trial.correctCount == correct
            && trial.outcome == GaborScorer.outcome(
                correctCount: correct,
                hasExactlySevenResponses: true
            )
    }

    private static func validation(
        _ issues: Set<GaborResultIntegrityIssue>
    ) -> GaborResultIntegrityValidation {
        let ordered = issues.sorted { $0.rawValue < $1.rawValue }
        return GaborResultIntegrityValidation(isValid: ordered.isEmpty, issues: ordered)
    }
}
