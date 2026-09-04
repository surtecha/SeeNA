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
        if numericResultsAllowed == true, integrityValid != true {
            return "Repeat needed · review required"
        }
        if integrityValid == false { return "Repeat needed" }
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
        case .experimentalThresholdObserved,
             .experimentalFarthestTargetPassed,
             .experimentalAdverseBoundary,
             .experimentalTaskCompleted:
            return "Task complete"
        case .unreliableMeasurement: return "Repeat needed"
        case .deviceUnsupported: return "Unavailable on this iPhone"
        case .userIneligible: return "Not suitable for this task"
        }
    }

    static func spokenLandoltSummary(
        eye: Eye,
        result: EyeScreeningResult?,
        integrityValid: Bool?,
        numericResultsAllowed: Bool?
    ) -> String {
        let eyeName = eye.displayName
        if numericResultsAllowed == true, integrityValid != true {
            return "\(eyeName) eye circle task needs repeating."
        }
        guard integrityValid != false else {
            return "\(eyeName) eye circle task needs repeating."
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
        } else if let status = result?.status, status.isQualitativeTaskCompletion {
            return "\(eyeName) eye circle task complete."
        } else if result?.status == .strongerThanSupportedRange {
            return "\(eyeName) eye needs professional review."
        }
        return "\(eyeName) eye circle task needs repeating."
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

        let numericApplicable = screening.numericResultsAllowed == true &&
            NumericResultEligibility.hasApprovedNumericProtocolRelease &&
            landolt.allSatisfy { statusIsNumeric($0.status) }

        let recommendation: ScreeningAction
        if reliability == .reviewRequired || reliability == .repeatRequired {
            recommendation = .repeatRequired
        } else if numericApplicable && landolt.contains(where: recommendsProfessionalReview) {
            recommendation = .professionalReviewRecommended
        } else {
            recommendation = .routineExamRecommended
        }

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
            localMeaning: localMeaning(
                landolt: landolt,
                reliability: reliability,
                numericApplicable: numericApplicable
            ),
            canOpenAnswerAudit: structurallyFinished
        )
    }

    /// Remote prose is presentation-only. It may be shown only after the
    /// local integrity contract and the backend verification flag agree.
    static func explanation(
        local: String,
        remote: String?,
        remoteVerified: Bool,
        remoteWasGenerated: Bool,
        reliability: ResultsReliability
    ) -> String {
        guard reliability == .reliable,
              remoteWasGenerated,
              remoteVerified,
              let remote = remote?.trimmingCharacters(in: .whitespacesAndNewlines),
              qualitativeExplanationIsSafe(remote) else { return local }
        return remote
    }

    /// A second, deterministic boundary on the phone. The backend verdict is
    /// necessary but never sufficient: model prose can describe only neutral
    /// task completion and answer recording, with no measurements or health
    /// interpretation.
    static func qualitativeExplanationIsSafe(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 220 else { return false }
        guard !trimmed.contains(where: { $0.wholeNumberValue != nil }) else { return false }

        let bannedPatterns = [
            #"\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|dozen|scores?|half|quarter|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth)\b"#,
            #"\b(?:d|diopt(?:er|re)s?|met(?:er|re)s?|m|centimet(?:er|re)s?|cm|millimet(?:er|re)s?|mm|kilomet(?:er|re)s?|km|feet|foot|ft|inches?|degrees?|arcmin(?:ute)?s?|pixels?|px|percent(?:age)?)\b"#,
            #"(?:%|°)"#,
            #"\b(?:poc|prototypes?|demos?|simulat\w*|validat\w*|calibrat\w*|ai|models?|providers?|algorithms?|schemas?|internal)\b"#,
            #"\b(?:diagnos\w*|prescri\w*|myopi\w*|refract\w*|acuity|contrast\w*|referr\w*|diseases?|treat\w*|cures?|curing|healthy|normal|abnormal|risks?|concerns?|conditions?|vision|eyesight|sight|power|clinical|medical)\b"#,
            #"\b(?:pass(?:ed|es|ing)?|fail(?:ed|s|ing)?|better|worse|similar|different|difference|accur\w*|reliab\w*|consisten\w*|verif\w*|quality|good|poor|estimate\w*|detect\w*|suggest\w*|indicat\w*|imply\w*|mean(?:s|ing)?|likely|perhaps|possibly)\b"#,
            #"\b(?:not|no|never|repeat\w*|incomplete|missing|unavailable|unable|cannot|couldn['’]?t|didn['’]?t)\b"#,
            #"\b(?:doctor|optometrist|ophthalmologist|professional|appointment|examination|exam|review|screening?|results?)\b"#
        ]
        guard bannedPatterns.allSatisfy({ pattern in
            trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
        }) else { return false }

        // Keep the accepted prose surface deliberately small. A deny-list
        // catches known unsafe claims; this allow-list also prevents a novel
        // euphemism from adding meaning beyond task completion and recording.
        guard trimmed.range(
            of: #"[^A-Za-z\s,.]"#,
            options: .regularExpression
        ) == nil else { return false }
        let allowedWords: Set<String> = [
            "all", "and", "answer", "answers", "are", "been", "both",
            "complete", "completed", "each", "eye", "eyes", "finished",
            "for", "from", "have", "is", "recorded", "response", "responses",
            "saved", "task", "tasks", "the", "these", "was", "we", "were",
            "you", "your"
        ]
        let words = trimmed
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard !words.isEmpty, words.allSatisfy(allowedWords.contains) else { return false }

        let hasTaskFact = trimmed.range(
            of: #"\b(?:answers?|responses?|tasks?)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasNeutralOutcome = trimmed.range(
            of: #"\b(?:recorded|saved|complete|completed|finished)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return hasTaskFact && hasNeutralOutcome
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
        guard structurallyFinished else { return "Tasks incomplete" }
        switch reliability {
        case .reliable: return "Tasks complete"
        case .repeatRequired, .reviewRequired: return "Repeat needed"
        }
    }

    private static func localMeaning(
        landolt: [EyeScreeningResult],
        reliability: ResultsReliability,
        numericApplicable: Bool
    ) -> String {
        guard reliability == .reliable else {
            return "One or more tasks need repeating."
        }
        guard numericApplicable else {
            return "Your answers were recorded for both eyes."
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
    var isQualitativeTaskCompletion: Bool {
        switch self {
        case .experimentalThresholdObserved, .experimentalFarthestTargetPassed,
             .experimentalAdverseBoundary, .experimentalTaskCompleted:
            return true
        default:
            return false
        }
    }

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
