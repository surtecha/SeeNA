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
        case .presenting: return "LOOK AT THE CIRCLE"
        case .recording: return "SAY THE OPENING"
        case .transcribing: return "Checking your answer"
        case .scoring: return "Scoring locally"
        case .retry: return "TRY THAT AGAIN"
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
    @Published private(set) var currentTrialIndex = 0
    @Published private(set) var completedTrialCount = 0
    @Published private(set) var isVoiceAttemptActive = false
    @Published var showingOperatorInput = false

    let totalTrialCount = SequentialOptotypeSession.requiredTargetCount

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
    private var sequentialSession: SequentialOptotypeSession?
    private var blockTranscripts: [String] = []
    private var activeVoiceTask: Task<Void, Never>?
    private var voiceFlowGeneration = UUID()
    private var operatorTakeoverAwaitingResolution = false

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

    /// The only optotype that should be rendered. It changes only after the
    /// current spoken answer has been recorded, transcribed, and accepted.
    var currentTarget: OptotypeDirection? {
        sequentialSession?.currentTarget
    }

    var trialProgress: Double {
        Double(completedTrialCount) / Double(totalTrialCount)
    }

    /// Freeze the rendered optotype size once position is accepted. Live sensor
    /// jitter is still recorded for quality checks, but can no longer resize the
    /// row while the participant is trying to answer it.
    var presentationDistance: Double {
        lockedPresentationDistance ?? currentDistance ?? targetDistance
    }

    var retryButtonTitle: String {
        needsPositionRecheck ? "Recheck position" : "Repeat voice response"
    }

    var operatorEntryEnabled: Bool {
        !showingOperatorInput
            && candidate != nil
            && targets.count == totalTrialCount
    }

    func begin(using dependencies: AppDependencies) {
        guard !hasBegun, candidate != nil else { return }
        hasBegun = true
        phase = .guiding
        dependencies.spokenPrompts.preloadNavigationGuidance(additionalTexts: [
            SpokenTestCountdown.startPrompt(
                responseInstruction: "Say the opening direction. If you cannot see it, say I can't see it."
            )
        ])
        announceGuidance(using: dependencies)
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        dependencies.sensorCoordinator.setSimulatorTargetDistance(targetDistance)
        mostRecentSample = sample
        if isCollectingMeasurementSamples, let sample {
            // Keep every one of the seven answer-recording windows. The
            // recorder bounds each attempt, so this stays small while the
            // quality gate still sees early movement and the final answer.
            blockSamples.append(sample)
        }

        let measured = sample.flatMap {
            $0.correctedDistanceMetres ?? $0.fusedDistanceMetres ?? $0.rawARDistanceMetres
        }
        currentDistance = distanceFilter.update(measured)
        guard !isRunningBlock,
              !blockLaunchPending,
              !positioningAccepted,
              !showingOperatorInput,
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
                launchVoiceFlow(
                    start: .newBlock,
                    dependencies: dependencies,
                    session: session
                )
            }
        } else {
            phase = .guiding
        }
    }

    private func runVoiceBlock(
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard voiceFlowIsCurrent(generation),
              !isRunningBlock,
              candidate != nil else {
            blockLaunchPending = false
            return
        }
        blockLaunchPending = false
        isRunningBlock = true
        blockSamples.removeAll(keepingCapacity: true)
        // Countdown and synthesized speech are setup, not measurement. Each
        // answer recording explicitly opens and closes its own sample window.
        isCollectingMeasurementSamples = false
        let directions = Self.randomDirections()
        guard let sequentialSession = SequentialOptotypeSession(targets: directions) else {
            isCollectingMeasurementSamples = false
            isRunningBlock = false
            return
        }
        self.sequentialSession = sequentialSession
        targets = sequentialSession.targets
        blockTranscripts = []
        currentTrialIndex = 0
        completedTrialCount = 0
        lastTranscript = nil
        phase = .presenting
        let countdownCompleted: Bool
#if DEBUG
        if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
            countdownCompleted = await SimulatorVoiceAutomation.shortCountdown(
                positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
            )
        } else {
            countdownCompleted = await SpokenTestCountdown.fromAcceptedPosition(
                prompts: dependencies.spokenPrompts,
                responseInstruction: "Say the opening direction. If you cannot see it, say I can't see it.",
                positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
            )
        }
#else
        countdownCompleted = await SpokenTestCountdown.fromAcceptedPosition(
            prompts: dependencies.spokenPrompts,
            responseInstruction: "Say the opening direction. If you cannot see it, say I can't see it.",
            positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
        )
#endif
        guard voiceFlowIsCurrent(generation) else { return }
        guard countdownCompleted else {
            isCollectingMeasurementSamples = false
            isRunningBlock = false
            positioningAccepted = false
            lockedPresentationDistance = nil
            phase = .guiding
            announceGuidance(using: dependencies)
            return
        }

        await collectSequentialAnswers(
            dependencies: dependencies,
            session: session,
            generation: generation
        )
    }

    private func collectSequentialAnswers(
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        while voiceFlowIsCurrent(generation),
              var activeSession = sequentialSession,
              activeSession.currentTarget != nil {
            do {
                phase = .recording
                let capture = try await captureSingleAnswer(dependencies: dependencies)
                guard voiceFlowIsCurrent(generation) else { return }

                switch capture {
                case .retry(let spokenPrompt, _):
                    // A failed or ambiguous answer never mutates the session,
                    // so the exact same circle stays on screen. Stay fully
                    // hands-free and keep listening until one answer is clear.
                    guard activeSession.retryCurrentTarget() != nil else { return }
                    isCollectingMeasurementSamples = false
                    phase = .presenting
                    await dependencies.spokenPrompts.speakAndWait(spokenPrompt)
                    guard voiceFlowIsCurrent(generation) else { return }
                    continue

                case .accepted(let response, let transcript):
                    let progression = activeSession.submit(response)
                    guard progression != .rejected else { continue }

                    sequentialSession = activeSession
                    blockTranscripts.append(transcript)
                    lastTranscript = transcript
                    completedTrialCount = activeSession.responses.count
                    currentTrialIndex = min(
                        activeSession.currentIndex,
                        totalTrialCount - 1
                    )

                    switch progression {
                    case .advanced:
                        // Publishing the new index is the only event that swaps
                        // the displayed circle. Recording starts immediately,
                        // so there is no timer that can advance without speech.
                        phase = .presenting
                        HapticFeedback.selection()
                        await Task.yield()

                    case .completed:
                        isCollectingMeasurementSamples = false
                        await submit(
                            responses: activeSession.responses,
                            source: .voice,
                            transcript: blockTranscripts.joined(separator: " | "),
                            audioLevelAdequate: true,
                            dependencies: dependencies,
                            session: session
                        )
                        guard voiceFlowIsCurrent(generation) else { return }
                        return

                    case .rejected:
                        break
                    }
                }
            } catch is CancellationError {
                isCollectingMeasurementSamples = false
                isRunningBlock = false
                return
            } catch {
                guard voiceFlowIsCurrent(generation) else { return }
                // A transient recorder/backend failure must not turn a spoken
                // test into a button-driven flow or consume the target.
                isCollectingMeasurementSamples = false
                phase = .presenting
                await dependencies.spokenPrompts.speakAndWait(
                    "Connection paused. Same circle. Say a direction, or say I can't see it."
                )
                guard voiceFlowIsCurrent(generation) else { return }
            }
        }
    }

    private enum SingleAnswerCapture {
        case accepted(response: OptotypeResponse, transcript: String)
        case retry(spokenPrompt: String, screenMessage: String)
    }

    private enum VoiceFlowStart {
        case newBlock
        case resumeCurrentTarget
    }

    private func captureSingleAnswer(dependencies: AppDependencies) async throws -> SingleAnswerCapture {
        // Only the actual visual-response interval contributes measurement
        // samples. Network transcription and spoken retry prompts are excluded.
        isCollectingMeasurementSamples = true
#if DEBUG
        if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
            guard await SimulatorVoiceAutomation.waitForAutomatedAnswer() else {
                isCollectingMeasurementSamples = false
                throw CancellationError()
            }
            isCollectingMeasurementSamples = false
            guard let target = sequentialSession?.currentTarget else {
                throw CancellationError()
            }
            return .accepted(
                response: OptotypeResponse(target),
                transcript: "[DEBUG simulated voice] \(target.rawValue)"
            )
        }
#endif
        let recording: AudioRecordingResult
        do {
            recording = try await dependencies.audioRecorder.record(maximumDuration: 20)
        } catch {
            isCollectingMeasurementSamples = false
            throw error
        }
        isCollectingMeasurementSamples = false
        defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }

        guard recording.adequateLevel else {
            return .retry(
                spokenPrompt: "I didn't hear that. Same circle. Say a direction, or say I can't see it.",
                screenMessage: "I couldn't hear your answer. The same circle will stay on screen."
            )
        }

        phase = .transcribing
        let response = try await dependencies.backend.transcribe(
            audioURL: recording.fileURL,
            mode: .singleDirection
        )
        if let direction = response.singleDirection {
            return .accepted(
                response: OptotypeResponse(direction),
                transcript: response.transcript
            )
        }
        if response.valid,
           response.mode == .singleDirection,
           response.choice == OptotypeResponse.notVisible.rawValue {
            return .accepted(response: .notVisible, transcript: response.transcript)
        }
        return .retry(
            spokenPrompt: "I didn't understand. Same circle. Say a direction, or say I can't see it.",
            screenMessage: response.failureReason
                ?? "Say up, down, left, right, or I can't see it."
        )
    }

    func presentOperatorInput(using dependencies: AppDependencies) {
        guard operatorEntryEnabled else { return }
        // Operator takeover is atomic: the sheet is not exposed until the live
        // recorder, speech, task, and generation have all been invalidated.
        invalidateActiveVoiceFlow(using: dependencies)
        operatorTakeoverAwaitingResolution = true
        showingOperatorInput = true
    }

    func operatorInputDidDismiss(
        dependencies: AppDependencies,
        session: AppSession
    ) {
        // Submission resolves the takeover before dismissing the sheet, so an
        // onDismiss callback from that path is deliberately a no-op. A genuine
        // cancellation resumes the same session, target, and accepted answers
        // under a fresh generation; stale voice continuations stay invalid.
        guard operatorTakeoverAwaitingResolution else { return }
        operatorTakeoverAwaitingResolution = false
        showingOperatorInput = false

        guard candidate != nil,
              targets.count == totalTrialCount,
              sequentialSession?.currentTarget != nil else {
            resetSequentialPresentation()
            phase = .guiding
            announceGuidance(using: dependencies)
            return
        }

        phase = .presenting
        launchVoiceFlow(
            start: .resumeCurrentTarget,
            dependencies: dependencies,
            session: session
        )
    }

    func submitOperatorResponses(
        _ responses: [OptotypeDirection],
        dependencies: AppDependencies,
        session: AppSession
    ) async {
        operatorTakeoverAwaitingResolution = false
        showingOperatorInput = false
        // Defensive even though the UI disables entry during a voice attempt:
        // stop the recorder/output and invalidate every suspended continuation
        // before operator data is allowed to mutate the threshold engine.
        invalidateActiveVoiceFlow(using: dependencies)
        guard responses.count == totalTrialCount else {
            phase = .retry("Operator input must contain exactly seven directions.")
            return
        }
        guard targets.count == totalTrialCount else {
            phase = .retry("The test row is no longer active. Recheck position and try again.")
            needsPositionRecheck = true
            return
        }
        isRunningBlock = true
        await submit(
            responses: responses.map(OptotypeResponse.init),
            source: .operatorInput,
            transcript: nil,
            audioLevelAdequate: true,
            dependencies: dependencies,
            session: session
        )
    }

    func repeatVoice(dependencies: AppDependencies, session: AppSession) async {
        guard !isVoiceAttemptActive else { return }
        if needsPositionRecheck {
            needsPositionRecheck = false
            positioningAccepted = false
            lockedPresentationDistance = nil
            resetSequentialPresentation()
            phase = .guiding
            announceGuidance(using: dependencies)
            return
        }

        guard sequentialSession?.currentTarget != nil else {
            launchVoiceFlow(
                start: .newBlock,
                dependencies: dependencies,
                session: session
            )
            return
        }

        launchVoiceFlow(
            start: .resumeCurrentTarget,
            dependencies: dependencies,
            session: session
        )
    }

    private func resumeVoiceBlock(
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard voiceFlowIsCurrent(generation),
              sequentialSession?.currentTarget != nil else { return }
        isRunningBlock = true
        // Keep the current session, answer list, frozen geometry, and target.
        // The eventual whole-block quality gate rejects real position drift.
        isCollectingMeasurementSamples = false
        phase = .presenting
        await dependencies.spokenPrompts.speakAndWait(
            "Same circle. Say a direction, or say I can't see it."
        )
        guard voiceFlowIsCurrent(generation) else { return }
        await collectSequentialAnswers(
            dependencies: dependencies,
            session: session,
            generation: generation
        )
    }

    private func submit(
        responses: [OptotypeResponse],
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
        let correct = zip(targets, responses).reduce(into: 0) { count, pair in
            if pair.1.matches(pair.0) { count += 1 }
        }
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
        resetSequentialPresentation()
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
        let prompt = hasExplainedResizing ? movement : "The circle resizes as you move. \(movement)"
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

    private func launchVoiceFlow(
        start: VoiceFlowStart,
        dependencies: AppDependencies,
        session: AppSession
    ) {
        guard activeVoiceTask == nil else { return }
        let generation = UUID()
        voiceFlowGeneration = generation
        isVoiceAttemptActive = true
        activeVoiceTask = Task { [weak self] in
            guard let self else { return }
            switch start {
            case .newBlock:
                await runVoiceBlock(
                    dependencies: dependencies,
                    session: session,
                    generation: generation
                )
            case .resumeCurrentTarget:
                await resumeVoiceBlock(
                    dependencies: dependencies,
                    session: session,
                    generation: generation
                )
            }
            finishVoiceFlow(generation: generation)
        }
    }

    private func voiceFlowIsCurrent(_ generation: UUID) -> Bool {
        !Task.isCancelled && generation == voiceFlowGeneration
    }

    private func finishVoiceFlow(generation: UUID) {
        guard generation == voiceFlowGeneration else { return }
        activeVoiceTask = nil
        isVoiceAttemptActive = false
        isCollectingMeasurementSamples = false
        isRunningBlock = false
    }

    private func invalidateActiveVoiceFlow(using dependencies: AppDependencies) {
        voiceFlowGeneration = UUID()
        activeVoiceTask?.cancel()
        activeVoiceTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        isVoiceAttemptActive = false
        isCollectingMeasurementSamples = false
        isRunningBlock = false
        blockLaunchPending = false
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

    private func resetSequentialPresentation() {
        sequentialSession = nil
        targets = []
        blockTranscripts = []
        currentTrialIndex = 0
        completedTrialCount = 0
        lastTranscript = nil
        isCollectingMeasurementSamples = false
    }

    private static func randomDirections() -> [OptotypeDirection] {
        (0..<SequentialOptotypeSession.requiredTargetCount).map { _ in
            OptotypeDirection.allCases.randomElement() ?? .up
        }
    }
}
