import Foundation

enum NumericVerificationDisposition: Equatable, Sendable {
    case reviewNeeded
    case calculationConsistent
    case notApplicableEvidenceIntact
}

enum ResultsReliability: Equatable, Sendable {
    case reliable
    case repeatRequired
    case reviewRequired
}

struct ResultsPresentation: Equatable, Sendable {
    let structurallyFinished: Bool
    let reliability: ResultsReliability
    let recommendation: ScreeningAction
    let numericVerification: NumericVerificationDisposition
    let headline: String
    let localMeaning: String
    let canOpenAnswerAudit: Bool
}

enum ResultsPresentationPolicy {
    /// Presentation is fail-closed: only an explicit `true` may expose numeric
    /// fields. Older saved sessions decode this flag as `nil`, so they receive
    /// the same qualitative redaction as an explicitly ineligible session.
    static func presentableEyeResult(
        _ result: EyeScreeningResult?,
        numericResultsAllowed: Bool?
    ) -> EyeScreeningResult? {
        result.map {
            NumericResultEligibility.sanitize(
                $0,
                numericResultsAllowed: numericResultsAllowed == true
            )
        }
    }

    static func landoltDisplayValue(
        result: EyeScreeningResult?,
        integrityValid: Bool?,
        numericResultsAllowed: Bool?
    ) -> String {
        if integrityValid == false { return "Repeat needed · review required" }
        guard let result = presentableEyeResult(
            result,
            numericResultsAllowed: numericResultsAllowed
        ) else { return "Repeat needed" }

        switch result.status {
        case .validEstimate:
            if let fail = result.lastFailDiopter, let pass = result.firstPassDiopter {
                return String(format: "%.2f to %.2f D", max(fail, pass), min(fail, pass))
            }
            return "Estimate available"
        case .noMyopiaDetectedWithinRange: return "Completed the farthest target in this task"
        case .strongerThanSupportedRange: return "Professional review recommended"
        case .experimentalThresholdObserved: return "Performance boundary recorded"
        case .experimentalFarthestTargetPassed: return "Completed the farthest target"
        case .experimentalAdverseBoundary: return "Professional review recommended"
        case .experimentalTaskCompleted: return "Task completed"
        case .unreliableMeasurement: return "Repeat needed"
        case .deviceUnsupported: return "Device unsupported"
        case .userIneligible: return "Not suitable"
        }
    }

    static func spokenLandoltSummary(
        eye: Eye,
        result: EyeScreeningResult?,
        integrityValid: Bool?,
        numericResultsAllowed: Bool?
    ) -> String {
        let eyeName = eye.displayName
        guard integrityValid != false else {
            return "\(eyeName) eye result needs repeating because its internal consistency checks need review."
        }
        let result = presentableEyeResult(result, numericResultsAllowed: numericResultsAllowed)
        if let result, result.status == .validEstimate,
           let fail = result.lastFailDiopter, let pass = result.firstPassDiopter {
            return String(
                format: "%@ eye approximate myopia range, minus %.2f to minus %.2f diopters.",
                eyeName,
                abs(max(fail, pass)),
                abs(min(fail, pass))
            )
        } else if result?.status == .noMyopiaDetectedWithinRange {
            return "\(eyeName) eye completed the farthest target in this task. This cannot rule out myopia."
        } else if result?.status == .experimentalTaskCompleted {
            return "\(eyeName) eye completed the target task. This screening does not provide a prescription or rule out myopia."
        } else if result?.status == .experimentalThresholdObserved {
            return "\(eyeName) eye reached a performance boundary in the target task. This does not rule out myopia."
        } else if result?.status == .experimentalFarthestTargetPassed {
            return "\(eyeName) eye completed the farthest target. This does not rule out myopia or other eye conditions."
        } else if result?.status == .experimentalAdverseBoundary {
            return "\(eyeName) eye reached the strongest target difficulty. Arrange a professional eye examination."
        } else if result?.status == .strongerThanSupportedRange {
            return "\(eyeName) eye needs professional review."
        }
        return "\(eyeName) eye Landolt test needs repeating."
    }

    static func evaluate(
        screening: ScreeningSession,
        landoltIntegrityValid: Bool,
        gaborIntegrityValid: Bool
    ) -> ResultsPresentation {
        let landolt = [screening.rightEyeResult, screening.leftEyeResult].compactMap {
            presentableEyeResult($0, numericResultsAllowed: screening.numericResultsAllowed)
        }
        let gabor = [screening.rightGaborResult, screening.leftGaborResult].compactMap { $0 }
        let structurallyFinished = landolt.count == 2 && gabor.count == 2
        let evidenceIntact = landoltIntegrityValid && gaborIntegrityValid
        let repeatNeeded = landolt.contains(where: needsRepeat) ||
            gabor.contains(where: { $0.status != .completed }) || !structurallyFinished

        let reliability: ResultsReliability
        if !evidenceIntact {
            reliability = .reviewRequired
        } else if repeatNeeded {
            reliability = .repeatRequired
        } else {
            reliability = .reliable
        }

        let recommendation: ScreeningAction
        if reliability == .reviewRequired || reliability == .repeatRequired {
            recommendation = .repeatRequired
        } else if landolt.contains(where: recommendsProfessionalReview) {
            recommendation = .professionalReviewRecommended
        } else {
            recommendation = .routineExamRecommended
        }

        let numericApplicable = screening.numericResultsAllowed == true &&
            landolt.allSatisfy { statusIsNumeric($0.status) }
        let numericVerification: NumericVerificationDisposition
        if !evidenceIntact {
            numericVerification = .reviewNeeded
        } else if numericApplicable {
            numericVerification = .calculationConsistent
        } else {
            numericVerification = .notApplicableEvidenceIntact
        }

        return ResultsPresentation(
            structurallyFinished: structurallyFinished,
            reliability: reliability,
            recommendation: recommendation,
            numericVerification: numericVerification,
            headline: headline(structurallyFinished: structurallyFinished, reliability: reliability),
            localMeaning: localMeaning(landolt: landolt, reliability: reliability),
            canOpenAnswerAudit: structurallyFinished
        )
    }

    /// Remote prose is presentation-only. It may be shown only after the
    /// local integrity contract and the backend verification flag agree.
    static func explanation(
        local: String,
        remote: String?,
        remoteVerified: Bool,
        reliability: ResultsReliability
    ) -> String {
        guard reliability == .reliable,
              remoteVerified,
              let remote = remote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remote.isEmpty else { return local }
        return remote
    }

    private static func needsRepeat(_ result: EyeScreeningResult) -> Bool {
        switch result.status {
        case .unreliableMeasurement, .deviceUnsupported, .userIneligible:
            return true
        default:
            return result.recommendedAction == .repeatRequired
        }
    }

    private static func recommendsProfessionalReview(_ result: EyeScreeningResult) -> Bool {
        if result.recommendedAction == .professionalReviewRecommended { return true }
        switch result.status {
        case .validEstimate, .strongerThanSupportedRange,
             .experimentalThresholdObserved, .experimentalAdverseBoundary:
            return true
        default:
            return false
        }
    }

    private static func statusIsNumeric(_ status: ScreeningStatus) -> Bool {
        switch status {
        case .validEstimate, .noMyopiaDetectedWithinRange, .strongerThanSupportedRange:
            return true
        default:
            return false
        }
    }

    private static func headline(
        structurallyFinished: Bool,
        reliability: ResultsReliability
    ) -> String {
        guard structurallyFinished else { return "Screening incomplete" }
        switch reliability {
        case .reliable: return "Screening complete"
        case .repeatRequired: return "Screening complete, but repeat needed"
        case .reviewRequired: return "Screening complete, but review needed"
        }
    }

    private static func localMeaning(
        landolt: [EyeScreeningResult],
        reliability: ResultsReliability
    ) -> String {
        guard reliability == .reliable else {
            return "One or more tasks need attention. Repeat the affected task before relying on this screening."
        }
        if landolt.contains(where: {
            $0.status == .strongerThanSupportedRange || $0.status == .experimentalAdverseBoundary
        }) {
            return "At least one eye reached the strongest target difficulty. Arrange a professional eye examination."
        }
        if landolt.allSatisfy({
            $0.status == .noMyopiaDetectedWithinRange ||
            $0.status == .experimentalFarthestTargetPassed
        }) {
            return "Both eyes passed the farthest target presented in this task. That observation cannot rule out myopia or other eye conditions."
        }
        if landolt.allSatisfy({ !$0.status.isNumericStatus }) {
            return "The target task recorded a performance boundary for each eye. It does not provide a prescription or rule out myopia."
        }
        guard landolt.count == 2,
              let right = landolt.first(where: { $0.eye == .right })?.displayedEstimateDiopter,
              let left = landolt.first(where: { $0.eye == .left })?.displayedEstimateDiopter else {
            return "Review each eye separately because at least one result is at the supported task boundary."
        }
        return abs(right - left) >= 0.75
            ? "The two eyes produced noticeably different screening estimates."
            : "The two eye screening estimates were broadly similar."
    }
}

private extension ScreeningStatus {
    var isNumericStatus: Bool {
        switch self {
        case .validEstimate, .noMyopiaDetectedWithinRange, .strongerThanSupportedRange:
            return true
        default:
            return false
        }
    }
}

enum ResultsPersistenceState: Equatable, Sendable {
    case saving
    case saved
    case recoveryDeletionRequired
    case retryableFailure
    case volatile
}

enum ResultsPersistenceEvent: Equatable, Sendable {
    case saveSucceeded
    case saveFailedUnreadableHistory
    case saveFailedRetryable
    case recoveryDeletionConfirmed
    case continueVolatile
}

enum ResultsPersistenceReducer {
    static func reduce(
        _ state: ResultsPersistenceState,
        event: ResultsPersistenceEvent
    ) -> ResultsPersistenceState {
        switch (state, event) {
        case (_, .saveSucceeded): return .saved
        case (.saving, .saveFailedUnreadableHistory): return .recoveryDeletionRequired
        case (.saving, .saveFailedRetryable): return .retryableFailure
        case (.recoveryDeletionRequired, .recoveryDeletionConfirmed): return .saving
        case (.recoveryDeletionRequired, .continueVolatile): return .volatile
        default: return state
        }
    }
}
