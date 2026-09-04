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
    case nonMyopicDiopter
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
    case numericProtocolNotApproved
    case inconsistentQualityState
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
    /// Release-locked future clinical protocol boundary. Do not derive the
    /// active near-range locator limit from this value.
    private static let supportedFarthestDiopter = -0.50
    /// Historical qualitative boundary retained only for integrity replay of
    /// previously saved locator sessions. The current active task never
    /// presents this 0.80 m candidate.
    private static let legacyPhoneQualitativeFarthestDiopter = -1.25

    static func validate(_ result: EyeScreeningResult) -> ResultIntegrityValidation {
        var issues: Set<ResultIntegrityIssue> = []

        switch result.status {
        case .validEstimate:
            validateEstimate(result, issues: &issues)
        case .noMyopiaDetectedWithinRange:
            validateNoMyopiaBoundary(result, issues: &issues)
        case .strongerThanSupportedRange:
            validateStrongBoundary(result, issues: &issues)
        case .experimentalThresholdObserved, .experimentalFarthestTargetPassed,
             .experimentalAdverseBoundary, .experimentalTaskCompleted:
            validateNoMeasurement(result, requireUnavailableQuality: false, issues: &issues)
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
        if profile != nil, isNumericStatus(result.status),
           !NumericResultEligibility.hasApprovedNumericProtocolRelease {
            issues.insert(.numericProtocolNotApproved)
        }

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
        case .experimentalFarthestTargetPassed:
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: legacyPhoneQualitativeFarthestDiopter,
                outcome: .pass,
                minimumCount: 2,
                thresholdDistance: nil,
                issues: &issues
            )
        case .experimentalAdverseBoundary:
            requireWitnesses(
                trials,
                eye: result.eye,
                candidate: supportedClosestDiopter,
                outcome: .fail,
                minimumCount: 2,
                thresholdDistance: nil,
                issues: &issues
            )
        case .experimentalThresholdObserved:
            requireQualitativeThresholdWitnesses(trials, eye: result.eye, issues: &issues)
        case .experimentalTaskCompleted:
            requireActiveTaskWitness(trials, eye: result.eye, issues: &issues)
        case .unreliableMeasurement, .deviceUnsupported, .userIneligible:
            break
        }

        let orderedIssues = issues.sorted { $0.rawValue < $1.rawValue }
        return ResultIntegrityValidation(isValid: orderedIssues.isEmpty, issues: orderedIssues)
    }

    private static func requireQualitativeThresholdWitnesses(
        _ trials: [TrialBlock],
        eye: Eye,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        let eyeTrials = trials.filter { $0.eye == eye }
        let valid = eyeTrials.filter(isWellFormedWitness)
        if eyeTrials.count != valid.count { issues.insert(.malformedSupportingEvidence) }

        let passCandidates = Dictionary(grouping: valid.filter { $0.outcome == .pass }) {
            $0.candidateDiopter
        }
        let hasBracket = passCandidates.contains { pass, witnesses in
            witnesses.count >= 2 && valid.contains {
                $0.outcome == .fail && approximatelyEqual($0.candidateDiopter, pass + 0.25)
            }
        }
        if !hasBracket { issues.insert(.missingSupportingEvidence) }
    }

    private static func requireActiveTaskWitness(
        _ trials: [TrialBlock],
        eye: Eye,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        let eyeTrials = trials.filter { $0.eye == eye }
        let valid = eyeTrials.filter {
            isWellFormedWitness($0) &&
                approximatelyEqual($0.candidateDiopter, supportedClosestDiopter) &&
                approximatelyEqual($0.targetDistanceMetres, 0.40)
        }

        // Rejected retry attempts are retained for audit and do not poison a
        // later valid block. An accepted-looking but malformed block does.
        if eyeTrials.contains(where: { trial in
            guard trial.outcome != .invalid else { return false }
            return !isWellFormedWitness(trial) ||
                !approximatelyEqual(trial.candidateDiopter, supportedClosestDiopter) ||
                !approximatelyEqual(trial.targetDistanceMetres, 0.40)
        }) {
            issues.insert(.malformedSupportingEvidence)
        }
        if valid.count != 1 { issues.insert(.missingSupportingEvidence) }
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
        validateNumericResultQuality(result, issues: &issues)
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
        validateNumericResultQuality(result, issues: &issues)
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

    private static func validateNumericResultQuality(
        _ result: EyeScreeningResult,
        issues: inout Set<ResultIntegrityIssue>
    ) {
        let trackingIsUsable = result.trackingQuality == .good || result.trackingQuality == .moderate
        if !trackingIsUsable || result.responseConsistency != .good {
            issues.insert(.inconsistentQualityState)
        }
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
        if lastFail >= 0 || firstPass >= 0 ||
            lastFail < supportedClosestDiopter - tolerance ||
            lastFail > supportedFarthestDiopter + tolerance ||
            firstPass < supportedClosestDiopter - tolerance ||
            firstPass > supportedFarthestDiopter + tolerance {
            issues.insert(.nonMyopicDiopter)
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
        if displayed >= 0 ||
            displayed < supportedClosestDiopter - tolerance ||
            displayed > supportedFarthestDiopter + tolerance {
            issues.insert(.nonMyopicDiopter)
        }
        if !isQuarterDiopter(displayed) { issues.insert(.nonQuarterDiopter) }
        guard distance.isFinite, distance > 0 else { return }
        guard let measured = RefractionEstimator.diopter(forDistanceMetres: distance) else { return }
        let expected = RefractionEstimator.roundedToQuarterDiopter(measured)
        if !expected.isFinite || !approximatelyEqual(displayed, expected) {
            issues.insert(.farPointMismatch)
        }
    }

    private static func isQuarterDiopter(_ value: Double) -> Bool {
        let rounded = RefractionEstimator.roundedToQuarterDiopter(value)
        return rounded.isFinite && approximatelyEqual(value, rounded)
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
              block.quality.trackingCoverage.isFinite,
              (0...1).contains(block.quality.trackingCoverage),
              block.quality.phoneStable,
              block.quality.headPoseValid,
              block.quality.distanceStable,
              block.quality.audioLevelAdequate,
              block.quality.targetGeometryValid,
              block.quality.gazeCoverage.map({ $0.isFinite && (0...1).contains($0) }) != false,
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
              SequentialOptotypeSession.isValidTargetSequence(block.targets),
              block.responses.count == SequentialOptotypeSession.requiredTargetCount,
              geometryEvidenceIsWellFormed(block) else {
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

    private static func geometryEvidenceIsWellFormed(_ block: TrialBlock) -> Bool {
        // Legacy blocks with nil geometry remain Codable so their history can
        // still be viewed, but they cannot serve as reliable evidence. Every
        // current reliable witness must carry both the frozen presentation and
        // the complete scalar geometry audit trail.
        guard let frozen = block.presentedGeometry,
              let recalculated = PresentedOptotypeGeometry.calculate(
                distanceMetres: frozen.presentationDistanceMetres,
                pixelsPerInch: frozen.pixelsPerInch,
                nativeScale: frozen.nativeScale,
                presentationMode: frozen.geometry.presentationMode
              ),
              let presentationDistance = block.presentationDistanceMetres,
              let pixelHeight = block.renderedPixelHeight,
              let pointHeight = block.renderedPointHeight,
              let renderedAngle = block.renderedAngularSizeArcMinutes,
              let actualAngle = block.actualAngularSizeArcMinutes,
              let drift = block.geometryDistanceDriftFraction,
              frozen.presentationDistanceMetres.isFinite,
              frozen.presentationDistanceMetres > 0,
              frozen.nativeScale.isFinite,
              frozen.nativeScale > 0,
              frozen.pixelsPerInch.isFinite,
              frozen.pixelsPerInch > 0,
              frozen.geometry.pixelHeight > 0,
              frozen.geometry.pixelHeight.isMultiple(of: 5),
              frozen.geometry.strokePixels * 5 == frozen.geometry.pixelHeight,
              frozen.geometry.innerDiameterPixels + frozen.geometry.strokePixels * 2 == frozen.geometry.pixelHeight,
              frozen.geometry.gapPixels == frozen.geometry.strokePixels,
              frozen.geometry.requestedArcMinutes.isFinite,
              frozen.geometry.requestedArcMinutes > 0,
              frozen.geometry.effectiveArcMinutes.isFinite,
              frozen.geometry.effectiveArcMinutes > 0,
              frozen.geometry == recalculated.geometry,
              abs(frozen.geometry.pointHeight - Double(frozen.geometry.pixelHeight) / frozen.nativeScale) <= tolerance,
              presentationDistance.isFinite,
              presentationDistance > 0,
              approximatelyEqual(presentationDistance, frozen.presentationDistanceMetres),
              pixelHeight > 0,
              pixelHeight == frozen.geometry.pixelHeight,
              pointHeight.isFinite,
              pointHeight > 0,
              approximatelyEqual(pointHeight, frozen.geometry.pointHeight),
              renderedAngle.isFinite,
              renderedAngle > 0,
              approximatelyEqual(renderedAngle, frozen.geometry.effectiveArcMinutes),
              actualAngle.isFinite,
              actualAngle > 0,
              let recomputedActualAngle = frozen.computedArcMinutes(
                at: block.actualMedianDistanceMetres
              ),
              approximatelyEqual(actualAngle, recomputedActualAngle),
              drift.isFinite,
              drift >= 0,
              drift <= 0.10 + tolerance else { return false }
        let expectedDrift = abs(actualAngle - renderedAngle) / renderedAngle
        return abs(expectedDrift - drift) <= 0.002
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
        guard let maximumUncertainty = RefractionEstimator.sensorUncertainty(
            distanceMetres: distance,
            standardDeviationMetres: maximumDistanceSD
        ) else {
            issues.insert(.uncertaintyExceedsProfile)
            return
        }
        if uncertainty > maximumUncertainty + tolerance {
            issues.insert(.uncertaintyExceedsProfile)
        }
    }

    private static func isNumericStatus(_ status: ScreeningStatus) -> Bool {
        switch status {
        case .validEstimate, .noMyopiaDetectedWithinRange, .strongerThanSupportedRange:
            return true
        default:
            return false
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
    static func validate(
        _ result: GaborScreeningResult,
        against trials: [GaborTrial]
    ) -> GaborResultIntegrityValidation {
        var issues = Set<GaborResultIntegrityIssue>()

        if trials.isEmpty { issues.insert(.missingSupportingEvidence) }
        if trials.contains(where: { $0.eye != result.eye }) {
            issues.insert(.wrongEyeEvidence)
        }
        if trials.contains(where: { !GaborContrastEngine.isWellFormedTrialEvidence($0) }) {
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

    private static func validation(
        _ issues: Set<GaborResultIntegrityIssue>
    ) -> GaborResultIntegrityValidation {
        let ordered = issues.sorted { $0.rawValue < $1.rawValue }
        return GaborResultIntegrityValidation(isValid: ordered.isEmpty, issues: ordered)
    }
}
