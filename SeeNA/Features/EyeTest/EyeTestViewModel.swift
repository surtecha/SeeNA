import Combine
import Foundation

enum EyeTestPhase: Equatable {
    case preparing
    case guiding
    case stabilising
    case presenting
    case recording
    case transcribing
    case scoring
    case retry(String)
    case completed

    var title: String {
        switch self {
        case .preparing: return "Preparing"
        case .guiding: return "MOVE TO TARGET"
        case .stabilising: return "HOLD STILL"
        case .presenting: return "READ LEFT TO RIGHT"
        case .recording: return "SPEAK THE SEVEN DIRECTIONS"
        case .transcribing: return "Checking your response"
        case .scoring: return "Scoring locally"
        case .retry: return "Repeat this row"
        case .completed: return "Eye complete"
        }
    }
}

@MainActor
final class EyeTestViewModel: ObservableObject {
    let eye: Eye
    @Published private(set) var phase: EyeTestPhase = .preparing
    @Published private(set) var action: SearchAction
    @Published private(set) var targets: [OptotypeDirection] = []
    @Published private(set) var lastTranscript: String?
    @Published private(set) var isRunningBlock = false
    @Published private(set) var readyProgress = 0.0
    @Published private(set) var currentDistance: Double?
    @Published private(set) var guidanceCue: DistanceGuidanceCue = .findFace
    @Published private(set) var isInTargetZone = false
    @Published var showingOperatorInput = false

    private var engine: ThresholdSearchEngine
    private var mostRecentSample: DistanceSample?
    private var hasExplainedResizing = false
    private var distanceFilter = RobustDistanceFilter()
    private var targetTracker = DistanceTargetTracker()
    private var voiceScheduler = VoiceGuidanceScheduler()
    private var blockLaunchPending = false
    private var blockSamples: [DistanceSample] = []
    private var hasBegun = false
    private var positioningAccepted = false
    private var needsPositionRecheck = false
    private var lockedPresentationDistance: Double?
    private var isCollectingMeasurementSamples = false

    init(eye: Eye) {
        self.eye = eye
        let engine = ThresholdSearchEngine(eye: eye)
        self.engine = engine
        action = engine.nextAction
    }

    var candidate: ScreeningCandidate? {
        guard case .test(let candidate, _) = action else { return nil }
        return candidate
    }

    var stage: SearchStage? {
        guard case .test(_, let stage) = action else { return nil }
        return stage
    }

    var targetDistance: Double { candidate?.distanceMetres ?? 0 }

    /// Freeze the rendered optotype size once position is accepted. Live sensor
    /// jitter is still recorded for quality checks, but can no longer resize the
    /// row while the participant is trying to answer it.
    var presentationDistance: Double {
        lockedPresentationDistance ?? currentDistance ?? targetDistance
    }

    var retryButtonTitle: String {
        needsPositionRecheck ? "Recheck position" : "Repeat voice response"
    }

    func begin(using dependencies: AppDependencies) {
        guard !hasBegun, candidate != nil else { return }
        hasBegun = true
        phase = .guiding
        dependencies.spokenPrompts.preloadNavigationGuidance()
        announceGuidance(using: dependencies)
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        mostRecentSample = sample
        if isCollectingMeasurementSamples, let sample {
            blockSamples.append(sample)
            if blockSamples.count > 900 { blockSamples.removeFirst(blockSamples.count - 900) }
        }

        let measured = sample.flatMap {
            $0.correctedDistanceMetres ?? $0.fusedDistanceMetres ?? $0.rawARDistanceMetres
        }
        currentDistance = distanceFilter.update(measured)
        guard !isRunningBlock,
              !blockLaunchPending,
              !positioningAccepted,
              candidate != nil else { return }

        let validPose = sample.map {
            $0.faceCount == 1
            && $0.phoneStable
            && abs($0.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && abs($0.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && $0.luminance >= 0.12
        } == true
        let timestamp = sample?.timestamp.timeIntervalSinceReferenceDate
            ?? Date().timeIntervalSinceReferenceDate
        let targetState = targetTracker.update(
            distance: currentDistance,
            target: targetDistance,
            conditionsReady: validPose,
            timestamp: timestamp
        )
        let cue = conditionCue(for: sample)
            ?? (targetState.isInTargetZone ? .stop : currentDistance.map {
                DistanceGuidanceEngine.cue(currentDistance: $0, targetDistance: targetDistance)
            })
            ?? .findFace
        guidanceCue = cue
        // The guaranteed final "Stop" belongs to the countdown sequence. Do
        // not queue a second stop prompt while the short stability hold runs.
        if cue != .stop {
            announce(cue, at: timestamp, using: dependencies)
        }
        isInTargetZone = targetState.isInTargetZone
        readyProgress = targetState.progress

        if targetState.isInTargetZone {
            phase = .stabilising
            if targetState.isReady {
                positioningAccepted = true
                needsPositionRecheck = false
                lockedPresentationDistance = currentDistance ?? targetDistance
                guidanceCue = .stop
                voiceScheduler.acceptTarget()
                targetTracker.reset()
                readyProgress = 0
                blockLaunchPending = true
                HapticFeedback.success()
                Task { await runVoiceBlock(dependencies: dependencies, session: session) }
            }
        } else {
            phase = .guiding
        }
    }

    func runVoiceBlock(dependencies: AppDependencies, session: AppSession) async {
        guard !isRunningBlock, candidate != nil else {
            blockLaunchPending = false
            return
        }
        blockLaunchPending = false
        isRunningBlock = true
        blockSamples.removeAll(keepingCapacity: true)
        isCollectingMeasurementSamples = true
        if targets.count != 7 { targets = Self.randomDirections() }
        phase = .presenting
        let countdownCompleted = await SpokenTestCountdown.fromAcceptedPosition(
            prompts: dependencies.spokenPrompts,
            responseInstruction: "Say the seven ring openings from left to right.",
            positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
        )
        guard countdownCompleted else {
            isCollectingMeasurementSamples = false
            isRunningBlock = false
            positioningAccepted = false
            lockedPresentationDistance = nil
            phase = .guiding
            announceGuidance(using: dependencies)
            return
        }

        do {
            phase = .recording
            let recording = try await dependencies.audioRecorder.record()
            isCollectingMeasurementSamples = false
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            guard recording.adequateLevel else {
                phase = .retry("The recording was too quiet. Speak the seven directions clearly.")
                needsPositionRecheck = false
                isRunningBlock = false
                return
            }
            phase = .transcribing
            let response = try await dependencies.backend.transcribe(audioURL: recording.fileURL, mode: .directionBlock)
            lastTranscript = response.transcript
            guard response.valid, let directions = response.directions, directions.count == 7 else {
                phase = .retry(response.failureReason ?? "I could not recover exactly seven directions.")
                needsPositionRecheck = false
                isRunningBlock = false
                return
            }
            await submit(
                responses: directions,
                source: .voice,
                transcript: response.transcript,
                audioLevelAdequate: true,
                dependencies: dependencies,
                session: session
            )
        } catch is CancellationError {
            isCollectingMeasurementSamples = false
            isRunningBlock = false
        } catch {
            isCollectingMeasurementSamples = false
            phase = .retry("Voice transcription is unavailable. Repeat or use operator input.")
            needsPositionRecheck = false
            isRunningBlock = false
        }
    }

    func submitOperatorResponses(
        _ responses: [OptotypeDirection],
        dependencies: AppDependencies,
        session: AppSession
    ) async {
        showingOperatorInput = false
        guard responses.count == 7 else {
            phase = .retry("Operator input must contain exactly seven directions.")
            return
        }
        isRunningBlock = true
        await submit(
            responses: responses,
            source: .operatorInput,
            transcript: nil,
            audioLevelAdequate: true,
            dependencies: dependencies,
            session: session
        )
    }

    func repeatVoice(dependencies: AppDependencies, session: AppSession) async {
        if needsPositionRecheck {
            needsPositionRecheck = false
            positioningAccepted = false
            lockedPresentationDistance = nil
            phase = .guiding
            announceGuidance(using: dependencies)
            return
        }
        await runVoiceBlock(dependencies: dependencies, session: session)
    }

    private func submit(
        responses: [OptotypeDirection],
        source: ResponseSource,
        transcript: String?,
        audioLevelAdequate: Bool,
        dependencies: AppDependencies,
        session: AppSession
    ) async {
        guard let candidate,
              let profile = session.activeSession.deviceProfile,
              !blockSamples.isEmpty else {
            phase = .retry("Distance tracking was lost. Return to the target distance.")
            needsPositionRecheck = true
            isRunningBlock = false
            return
        }
        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: blockSamples,
            targetDistanceMetres: candidate.distanceMetres,
            targetToleranceMetres: DistanceGuidanceEngine.exitTolerance(for: candidate.distanceMetres),
            thresholds: profile.qualityThresholds
        )
        guard let actualDistance = aggregate.medianDistanceMetres else {
            phase = .retry("Distance tracking was lost. Return to the target distance.")
            needsPositionRecheck = true
            isRunningBlock = false
            return
        }
        phase = .scoring
        let geometry = OptotypeGeometry.calculate(
            distanceMetres: actualDistance,
            pixelsPerInch: profile.pixelsPerInch,
            displayScale: profile.displayScale
        )
        let quality = blockQuality(
            aggregate: aggregate,
            responseCount: responses.count,
            audioLevelAdequate: audioLevelAdequate,
            targetGeometryValid: geometry != nil
        )
        let correct = TrialScorer.correctCount(targets: targets, responses: responses)
        let outcome = quality.isValid
            ? TrialScorer.outcome(correctCount: correct, hasExactlySevenResponses: responses.count == 7)
            : .invalid
        let block = TrialBlock(
            eye: eye,
            candidateDiopter: candidate.diopter,
            targetDistanceMetres: candidate.distanceMetres,
            actualMedianDistanceMetres: actualDistance,
            distanceStandardDeviation: aggregate.distanceStandardDeviationMetres ?? .infinity,
            targets: targets,
            responses: responses,
            correctCount: correct,
            outcome: outcome,
            quality: quality,
            responseSource: source,
            transcript: transcript
        )

        if eye == .right {
            session.activeSession.rightEyeTrials.append(block)
        } else {
            session.activeSession.leftEyeTrials.append(block)
        }
        action = engine.submit(block: block)
        targets = []
        isRunningBlock = false

        switch action {
        case .test:
            phase = quality.isValid ? .guiding : .retry(qualityMessage(quality))
            if quality.isValid {
                positioningAccepted = false
                lockedPresentationDistance = nil
                announceGuidance(using: dependencies)
            } else {
                // Do not restart movement speech behind the retry screen. The
                // participant explicitly chooses when to recheck position.
                needsPositionRecheck = true
            }
        case .completed(let result):
            if eye == .right { session.activeSession.rightEyeResult = result }
            else { session.activeSession.leftEyeResult = result }
            phase = .completed
            await dependencies.spokenPrompts.speakAndWait("\(eye.displayName) eye complete.")
            session.navigate(to: eye == .right ? .rightGaborTest : .leftGaborTest)
        }
    }

    private func announceGuidance(using dependencies: AppDependencies) {
        positioningAccepted = false
        needsPositionRecheck = false
        lockedPresentationDistance = nil
        targetTracker.reset()
        readyProgress = 0
        isInTargetZone = false
        let now = Date().timeIntervalSinceReferenceDate
        voiceScheduler.begin(at: now)
        dependencies.spokenPrompts.beginNavigationGuidance()

        let movement: String
        if let currentDistance,
           abs(currentDistance - targetDistance) <= DistanceGuidanceEngine.entryTolerance(for: targetDistance) {
            movement = "Stay where you are."
        } else if let currentDistance, currentDistance > targetDistance {
            movement = "Walk towards the phone. I will tell you when to stop."
        } else {
            movement = "Walk backwards slowly. I will tell you when to stop."
        }
        let prompt = hasExplainedResizing ? movement : "The rings resize as you move. \(movement)"
        hasExplainedResizing = true
        dependencies.spokenPrompts.speak(prompt)
    }

    private func conditionCue(for sample: DistanceSample?) -> DistanceGuidanceCue? {
        guard let sample, sample.faceCount == 1 else { return .findFace }
        if !sample.phoneStable { return .waitForPhone }
        if sample.luminance < 0.12 { return .addLight }
        if abs(sample.headYawDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            || abs(sample.headPitchDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees {
            return .facePhone
        }
        return nil
    }

    private func positionIsAcceptable() -> Bool {
        guard let sample = mostRecentSample,
              let currentDistance,
              sample.faceCount == 1,
              sample.phoneStable,
              sample.luminance >= 0.12,
              abs(sample.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees,
              abs(sample.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees else {
            return false
        }
        return abs(currentDistance - targetDistance)
            <= DistanceGuidanceEngine.exitTolerance(for: targetDistance)
    }

    private func announce(
        _ cue: DistanceGuidanceCue,
        at timestamp: TimeInterval,
        using dependencies: AppDependencies
    ) {
        guard voiceScheduler.shouldAnnounce(cue, at: timestamp) else { return }
        dependencies.spokenPrompts.queueNavigationCue(cue.spokenText)
    }

    private func qualityMessage(_ quality: BlockQuality) -> String {
        guard let first = quality.discardReasons.first else { return "This row could not be scored. Please repeat it." }
        switch first {
        case .trackingCoverage, .multipleFaces: return "Face tracking was incomplete. Centre one face and repeat."
        case .phoneMoved, .orientationChanged: return "The phone moved. Re-lock its position and repeat."
        case .headPose: return "Face the phone directly and repeat."
        case .distanceUnstable: return "Hold still for one second and repeat."
        case .targetGeometry: return "The target could not be rendered safely at this distance."
        case .audioLevel: return "Speak louder and repeat the row."
        case .responseCount: return "Exactly seven directions are required."
        case .poorLighting: return "Turn on another light and repeat."
        case .serviceUnavailable: return "The voice service is unavailable."
        }
    }

    private func blockQuality(
        aggregate: BlockMeasurementQuality,
        responseCount: Int,
        audioLevelAdequate: Bool,
        targetGeometryValid: Bool
    ) -> BlockQuality {
        var reasons = aggregate.blockDiscardReasons
        if responseCount != 7 { reasons.append(.responseCount) }
        if !audioLevelAdequate { reasons.append(.audioLevel) }
        if !targetGeometryValid { reasons.append(.targetGeometry) }
        reasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }

        return BlockQuality(
            trackingCoverage: aggregate.trackingCoverage,
            phoneStable: !aggregate.issues.contains(.phoneMoved),
            headPoseValid: !aggregate.issues.contains(.headPose),
            distanceStable: !aggregate.issues.contains(where: {
                [.insufficientSamples, .distanceUnavailable, .distanceOffTarget, .distanceUnstable].contains($0)
            }),
            audioLevelAdequate: audioLevelAdequate,
            targetGeometryValid: targetGeometryValid,
            discardReasons: reasons
        )
    }

    private static func randomDirections() -> [OptotypeDirection] {
        (0..<7).map { _ in OptotypeDirection.allCases.randomElement() ?? .up }
    }
}
