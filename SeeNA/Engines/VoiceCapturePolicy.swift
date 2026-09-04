import Foundation

/// Tunable, device-independent settings for the short spoken answers used by
/// the screening flow. The detector intentionally favours sensitivity: the
/// backend still performs the semantic validation, while this policy prevents
/// quiet but plausible answers from being discarded before transcription.
struct VoiceActivityConfiguration: Equatable, Sendable {
    var sampleIntervalHint: TimeInterval = 0.10
    var minimumSignalDB: Float = -62
    var signalToNoiseMarginDB: Float = 5
    var peakHeadroomDB: Float = 10
    var strongSignalDB: Float = -45
    var minimumQuietSignalRangeDB: Float = 2
    var minimumSpeechDuration: TimeInterval = 0.14
    var minimumSpeechSamples = 2
    var maximumCandidateGap: TimeInterval = 0.24
    var trailingSilenceDuration: TimeInterval = 0.72
    var initialSilenceTimeout: TimeInterval = 3.8
    var minimumRecordingDuration: TimeInterval = 0.85
    var maximumUtteranceDuration: TimeInterval = 3.2
    var noiseFloorSmoothing: Float = 0.12

    static let screeningAnswer = VoiceActivityConfiguration()
}

enum VoiceActivityStopReason: Equatable, Sendable {
    case answerFinished
    case noSpeech
}

enum VoiceActivityDecision: Equatable, Sendable {
    case keepRecording
    case stop(VoiceActivityStopReason)
}

/// An adaptive envelope detector for one short answer. It combines average and
/// peak power into a single signal estimate, learns the ambient floor, and
/// requires time-based evidence instead of two unrelated absolute dB gates.
struct VoiceActivityDetector: Sendable {
    let configuration: VoiceActivityConfiguration

    private(set) var capturedPlausibleSpeech = false
    private(set) var noiseFloorDB: Float = -68

    private var previousObservationTime: TimeInterval?
    private var lastActiveTime: TimeInterval?
    private var speechCapturedAt: TimeInterval?
    private var candidateDuration: TimeInterval = 0
    private var candidateSampleCount = 0
    private var candidateMinimumDB: Float = 0
    private var candidateMaximumDB: Float = -100

    init(configuration: VoiceActivityConfiguration = .screeningAnswer) {
        self.configuration = configuration
    }

    mutating func observe(
        averagePowerDB: Float,
        peakPowerDB: Float,
        elapsed: TimeInterval
    ) -> VoiceActivityDecision {
        let timestamp = max(0, elapsed.isFinite ? elapsed : 0)
        let average = Self.sanitizedPower(averagePowerDB)
        let peak = Self.sanitizedPower(peakPowerDB)
        let signal = max(average, peak - configuration.peakHeadroomDB)
        let adaptiveThreshold = max(
            configuration.minimumSignalDB,
            noiseFloorDB + configuration.signalToNoiseMarginDB
        )
        let isActive = signal >= adaptiveThreshold

        let rawDelta = previousObservationTime.map { max(0, timestamp - $0) }
            ?? configuration.sampleIntervalHint
        let delta = min(max(rawDelta, 0), 0.25)
        previousObservationTime = timestamp

        if isActive {
            if let lastActiveTime,
               timestamp - lastActiveTime > configuration.maximumCandidateGap,
               !capturedPlausibleSpeech {
                resetCandidate()
            }
            lastActiveTime = timestamp
            candidateDuration += max(delta, configuration.sampleIntervalHint / 2)
            candidateSampleCount += 1
            if candidateSampleCount == 1 {
                candidateMinimumDB = signal
                candidateMaximumDB = signal
            } else {
                candidateMinimumDB = min(candidateMinimumDB, signal)
                candidateMaximumDB = max(candidateMaximumDB, signal)
            }

            let hasEnoughEnvelope = candidateMaximumDB >= configuration.strongSignalDB
                || candidateMaximumDB - candidateMinimumDB >= configuration.minimumQuietSignalRangeDB
            if candidateSampleCount >= configuration.minimumSpeechSamples,
               candidateDuration >= configuration.minimumSpeechDuration,
               hasEnoughEnvelope {
                capturedPlausibleSpeech = true
                if speechCapturedAt == nil {
                    speechCapturedAt = timestamp
                }
            } else if candidateDuration >= 0.5 {
                // A steady envelope is more likely to be room noise than the
                // beginning of a short answer. Let the adaptive floor converge
                // instead of treating that background as speech forever.
                updateNoiseFloor(with: signal)
            }
        } else {
            updateNoiseFloor(with: signal)
            if !capturedPlausibleSpeech,
               let lastActiveTime,
               timestamp - lastActiveTime > configuration.maximumCandidateGap {
                resetCandidate()
            }
        }

        if capturedPlausibleSpeech,
           let lastActiveTime,
           timestamp >= configuration.minimumRecordingDuration,
           timestamp - lastActiveTime >= configuration.trailingSilenceDuration {
            return .stop(.answerFinished)
        }
        if capturedPlausibleSpeech,
           let speechCapturedAt,
           timestamp - speechCapturedAt >= configuration.maximumUtteranceDuration {
            return .stop(.answerFinished)
        }
        if !capturedPlausibleSpeech,
           timestamp >= configuration.initialSilenceTimeout {
            return .stop(.noSpeech)
        }
        return .keepRecording
    }

    private mutating func resetCandidate() {
        candidateDuration = 0
        candidateSampleCount = 0
        candidateMinimumDB = 0
        candidateMaximumDB = -100
        lastActiveTime = nil
    }

    private mutating func updateNoiseFloor(with signal: Float) {
        let alpha = min(max(configuration.noiseFloorSmoothing, 0), 1)
        noiseFloorDB += alpha * (signal - noiseFloorDB)
        noiseFloorDB = min(max(noiseFloorDB, -90), -25)
    }

    private static func sanitizedPower(_ value: Float) -> Float {
        guard value.isFinite else { return -100 }
        return min(max(value, -100), 0)
    }
}

/// A small, explicit latency budget for one transcription. There is at most
/// one retry, and only failures that are plausibly transient qualify.
struct TranscriptionTransportPolicy: Equatable, Sendable {
    var firstAttemptTimeoutNanoseconds: UInt64 = 7_000_000_000
    var retryAttemptTimeoutNanoseconds: UInt64 = 2_400_000_000
    var retryDelayNanoseconds: UInt64 = 200_000_000
    var totalBudgetNanoseconds: UInt64 = 9_750_000_000

    static let interactiveAnswer = TranscriptionTransportPolicy()

    func timeoutNanoseconds(forAttempt attempt: Int, elapsedNanoseconds: UInt64) -> UInt64? {
        guard attempt == 0 || attempt == 1,
              elapsedNanoseconds < totalBudgetNanoseconds else {
            return nil
        }
        let requested = attempt == 0
            ? firstAttemptTimeoutNanoseconds
            : retryAttemptTimeoutNanoseconds
        return min(requested, totalBudgetNanoseconds - elapsedNanoseconds)
    }

    func shouldRetry(statusCode: Int, completedAttempt: Int) -> Bool {
        guard completedAttempt == 0 else { return false }
        return statusCode == 429 || [502, 503, 504].contains(statusCode)
    }

    func shouldRetry(urlErrorCode: URLError.Code, completedAttempt: Int) -> Bool {
        guard completedAttempt == 0 else { return false }
        switch urlErrorCode {
        case .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

/// The remote voice is an enhancement, never a prerequisite for guidance.
/// Keeping its network deadline well inside the UI transition deadline leaves
/// enough time for AVSpeechSynthesizer to deliver the same prompt locally.
struct SpeechTransportPolicy: Equatable, Sendable {
    var remoteAttemptTimeout: TimeInterval = 2.75
    var transitionDeadline: TimeInterval = 8

    static let handsFreePrompt = SpeechTransportPolicy()

    var localFallbackBudget: TimeInterval {
        max(0, transitionDeadline - remoteAttemptTimeout)
    }

    var preservesLocalFallback: Bool {
        remoteAttemptTimeout > 0 && localFallbackBudget >= 4
    }
}
