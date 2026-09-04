import Combine
import Foundation

enum GaborTestPhase: Equatable {
    case moving
    case stabilising
    case teaching
    case presenting
    case recording
    case checking
    case retry(String)
    case completed
    case needsRepeat

    var title: String {
        switch self {
        case .moving: return "MOVE CLOSE"
        case .stabilising: return "HOLD STILL"
        case .teaching: return "HOW TO ANSWER"
        case .presenting: return "LOOK AT THE STRIPES"
        case .recording: return "SAY LEFT OR RIGHT"
        case .checking: return "CHECKING"
        case .retry: return "SAY IT AGAIN"
        case .completed: return "TASK COMPLETE"
        case .needsRepeat: return "REPEAT NEEDED"
        }
    }

    var isTerminal: Bool {
        self == .completed || self == .needsRepeat
    }
}

@MainActor
final class GaborTestViewModel: ObservableObject {
    static let orientationInstruction = "Stripes from upper left to lower right mean left. The other way means right."
    private static let responseInstruction = "Say left, right, or I can’t see it."
    private static let orientationInstructionTimeoutNanoseconds: UInt64 = 10_000_000_000

    let eye: Eye

    @Published private(set) var phase: GaborTestPhase = .moving
    @Published private(set) var targets: [GaborOrientation] = []
    @Published private(set) var contrast = GaborContrastEngine.contrastLevels[0]
    @Published private(set) var isRunning = false
    @Published private(set) var stabilityProgress = 0.0
    @Published private(set) var currentDistance: Double?
    @Published private(set) var guidanceCue: DistanceGuidanceCue = .findFace
    @Published private(set) var completedTargetCount = 0
    @Published private(set) var isScoredTargetVisible = false
    @Published private(set) var completionDisposition: GaborCompletionDisposition?
    @Published private(set) var presentationGeometry: GaborPresentationGeometry?
    @Published var showingOperatorInput = false

    let targetDistance = 0.40
    let totalTargetCount = SequentialGaborSession.requiredTargetCount

    private var engine: GaborContrastEngine
    private var announcedMove = false
    private var distanceFilter = RobustDistanceFilter()
    private var targetTracker = DistanceTargetTracker()
    private var voiceScheduler = VoiceGuidanceScheduler()
    private var blockLaunchPending = false
    private var positioningAccepted = false
    private var mostRecentSample: DistanceSample?
    private var blockEvidence = AnswerWindowSensorEvidenceBuffer()
    private var isCollectingMeasurementSamples = false
    private var sequentialSession: SequentialGaborSession?
    private var acceptedTranscripts: [String] = []
    private var activeTask: Task<Void, Never>?
    private var gazeTracker = GazeReadinessTracker()
    private var gazeState: GazeReadiness = .unavailable
    private var simulatorDistanceOwner: UUID?
    private var operatorSubmissionResolved = false
    private var operatorModeRequested = false
    private var hasExplainedOrientation = false
    private var lifecycleGeneration = UUID()

    init(eye: Eye) {
        self.eye = eye
        engine = GaborContrastEngine(eye: eye)
    }

    /// The only patch the view should render. This value cannot change until a
    /// valid left/right transcription has been accepted for the current patch.
    var currentTarget: GaborOrientation? {
        sequentialSession?.currentTarget
    }

    var currentTargetNumber: Int {
        min(completedTargetCount + 1, totalTargetCount)
    }

    var trialProgress: Double {
        Double(completedTargetCount) / Double(totalTargetCount)
    }

    var operatorEntryEnabled: Bool {
        !showingOperatorInput
            && sequentialSession != nil
            && targets.count == totalTargetCount
            && presentationGeometry?.isValidCurrentEvidence == true
    }

    func begin(using dependencies: AppDependencies, session: AppSession) {
        guard !announcedMove else { return }
        announcedMove = true
        operatorModeRequested = session.responseMode == .operatorOnly
        simulatorDistanceOwner = dependencies.sensorCoordinator.claimSimulatorDistanceOwner()
        dependencies.sensorCoordinator.setSimulatorTargetDistance(
            targetDistance,
            owner: simulatorDistanceOwner
        )
        dependencies.spokenPrompts.preloadNavigationGuidance(additionalTexts: [
            SpokenTestCountdown.startPrompt(responseInstruction: Self.responseInstruction)
        ])
        dependencies.spokenPrompts.beginNavigationGuidance()
        voiceScheduler.begin(at: Date().timeIntervalSinceReferenceDate)
        dependencies.spokenPrompts.speakGuidanceIntro(
            "Keep your \(eye.eyeToCover) eye covered. Move close to the phone. I’ll tell you when to stop."
        )
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        mostRecentSample = sample
        gazeState = gazeTracker.update(
            yawErrorDegrees: sample?.gazeYawErrorDegrees,
            pitchErrorDegrees: sample?.gazePitchErrorDegrees
        )
        if isCollectingMeasurementSamples, let sample {
            blockEvidence.record(sample)
        }

        let measured = sample.flatMap {
            $0.correctedDistanceMetres ?? $0.fusedDistanceMetres ?? $0.rawARDistanceMetres
        }
        currentDistance = distanceFilter.update(measured)
        guard !isRunning, !blockLaunchPending, !positioningAccepted else { return }

        let conditionsReady = sample.map {
            $0.faceCount == 1
                && $0.phoneStable
                && abs($0.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
                && abs($0.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
                && $0.luminance >= 0.12
        } == true
        let timestamp = sample?.timestamp.timeIntervalSinceReferenceDate
            ?? Date().timeIntervalSinceReferenceDate
        let state = targetTracker.update(
            distance: currentDistance,
            target: targetDistance,
            conditionsReady: conditionsReady,
            timestamp: timestamp
        )
        let cue = conditionCue(for: sample)
            ?? (state.isInTargetZone ? .stop : currentDistance.map {
                DistanceGuidanceEngine.cue(currentDistance: $0, targetDistance: targetDistance)
            })
            ?? .findFace
        guidanceCue = cue
        if cue != .stop, voiceScheduler.shouldAnnounce(cue, at: timestamp) {
            dependencies.spokenPrompts.queueNavigationCue(cue.spokenText)
        }

        stabilityProgress = state.progress
        if state.isInTargetZone {
            phase = .stabilising
            if state.isReady {
                positioningAccepted = true
                guidanceCue = .stop
                voiceScheduler.acceptTarget()
                targetTracker.reset()
                stabilityProgress = 0
                blockLaunchPending = true
                HapticFeedback.success()
                let generation = lifecycleGeneration
                activeTask = Task { [weak self] in
                    await self?.runBlock(
                        start: .acceptedPosition,
                        dependencies: dependencies,
                        session: session,
                        generation: generation
                    )
                }
            }
        } else {
            stabilityProgress = 0
            phase = .moving
        }
    }

    func repeatBlock(dependencies: AppDependencies, session: AppSession) async {
        invalidateLifecycle()
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        if completionDisposition == .repeatNeeded {
            engine = GaborContrastEngine(eye: eye)
            if eye == .right {
                session.activeSession.rightGaborTrials = []
                session.activeSession.rightGaborResult = nil
            } else {
                session.activeSession.leftGaborTrials = []
                session.activeSession.leftGaborResult = nil
            }
            hasExplainedOrientation = false
        }
        restartPositioning(
            announcement: "I’ll guide you back to forty centimetres.",
            dependencies: dependencies
        )
    }

    func cancel(using dependencies: AppDependencies) {
        invalidateLifecycle()
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        dependencies.sensorCoordinator.releaseSimulatorDistanceOwner(simulatorDistanceOwner)
        simulatorDistanceOwner = nil
        isCollectingMeasurementSamples = false
        isRunning = false
        blockLaunchPending = false
        blockEvidence.reset(releasingCapacity: true)
        isScoredTargetVisible = false
        presentationGeometry = nil
    }

    /// Freezes a pixel-aligned patch diameter for the active block. Subsequent
    /// layout passes and retries reuse this geometry instead of subtly resizing
    /// the stimulus while the participant is answering.
    func registerDisplayedTarget(_ geometry: GaborPresentationGeometry) {
        guard isScoredTargetVisible,
              presentationGeometry == nil,
              geometry.isValidCurrentEvidence else { return }
        presentationGeometry = geometry
    }

    private enum BlockStart {
        case acceptedPosition
        case nextContrast
    }

    private func runBlock(
        start: BlockStart,
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard flowIsCurrent(generation), !isRunning else {
            blockLaunchPending = false
            return
        }
        guard case .test(let activeContrast) = engine.nextAction else {
            blockLaunchPending = false
            return
        }

        blockLaunchPending = false
        isRunning = true
        isCollectingMeasurementSamples = false
        blockEvidence.reset()
        acceptedTranscripts.removeAll(keepingCapacity: true)
        completedTargetCount = 0
        contrast = activeContrast
        targets = GaborTargetSequence.make()
        sequentialSession = SequentialGaborSession(targets: targets)
        presentationGeometry = nil
        // Never reveal a scored target beneath the positioning countdown.
        // Visibility is committed only after the transition has completed.
        isScoredTargetVisible = false
        phase = .presenting

        if start == .acceptedPosition, !hasExplainedOrientation {
            phase = .teaching
            let teachingOutcome = await dependencies.spokenPrompts.speakLocallyForTransition(
                Self.orientationInstruction,
                timeoutNanoseconds: Self.orientationInstructionTimeoutNanoseconds
            )
            guard flowIsCurrent(generation) else {
                isRunning = false
                return
            }
            guard SpeechProgressionPolicy.shouldAdvance(after: teachingOutcome) else {
                isRunning = false
                phase = .retry("The voice guide paused. Recheck position to hear how to answer.")
                return
            }
            hasExplainedOrientation = true
        }

        if start == .acceptedPosition {
            let countdownCompleted: Bool
#if DEBUG
            if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
                countdownCompleted = await SimulatorVoiceAutomation.shortCountdown(
                    positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
                )
            } else {
                countdownCompleted = await SpokenTestCountdown.fromAcceptedPosition(
                    prompts: dependencies.spokenPrompts,
                    responseInstruction: Self.responseInstruction,
                    positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
                )
            }
#else
            countdownCompleted = await SpokenTestCountdown.fromAcceptedPosition(
                prompts: dependencies.spokenPrompts,
                responseInstruction: Self.responseInstruction,
                positionIsValid: { [weak self] in self?.positionIsAcceptable() == true }
            )
#endif
            guard flowIsCurrent(generation), countdownCompleted else {
                isCollectingMeasurementSamples = false
                isRunning = false
                targets = []
                sequentialSession = nil
                restartPositioning(announcement: nil, dependencies: dependencies)
                return
            }
            phase = .presenting
        } else {
            HapticFeedback.impact()
            guard await pause(milliseconds: 450), flowIsCurrent(generation) else {
                isRunning = false
                return
            }
        }
        // The first scored patch stays hidden until the orientation convention
        // and the complete countdown have been spoken in full.
        isScoredTargetVisible = true

        guard await waitForPresentationGeometry(generation: generation) else {
            isRunning = false
            phase = .retry("The stripe pattern could not be prepared. Recheck your position.")
            return
        }

        if operatorModeRequested {
            isRunning = false
            phase = .retry("Microphone response is off. Ask a helper to tap your answers.")
            return
        }
        if !dependencies.network.isConnected {
            phase = .retry("Voice is reconnecting. Please wait.")
            _ = await dependencies.spokenPrompts.speakLocallyForTransition(
                "Voice is reconnecting. Please wait."
            )
            guard await waitForVoiceConnection(
                dependencies.network,
                generation: generation
            ) else {
                if flowIsCurrent(generation) {
                    operatorModeRequested = true
                    isRunning = false
                    phase = .retry("Voice is offline. Ask a helper to tap your answers.")
                }
                return
            }
        }

        guard await collectRequiredAnswers(
            dependencies: dependencies,
            generation: generation
        ) else {
            isCollectingMeasurementSamples = false
            isRunning = false
            return
        }
        await scoreBlock(dependencies: dependencies, session: session, generation: generation)
    }

    /// Repeats the same patch for as long as necessary. Transcription and all
    /// spoken retry prompts happen outside the sensor-measurement window.
    private func collectRequiredAnswers(
        dependencies: AppDependencies,
        generation: UUID
    ) async -> Bool {
        var transientFailureCount = 0
        while flowIsCurrent(generation) {
            guard let activeSession = sequentialSession else { return false }
            if activeSession.isComplete { return true }
            let expectedIndex = activeSession.currentIndex
            let expectedTarget = activeSession.currentTarget

            phase = .presenting
            guard await pause(milliseconds: completedTargetCount == 0 ? 250 : 380),
                  flowIsCurrent(generation),
                  currentPatchMatches(index: expectedIndex, target: expectedTarget) else {
                return false
            }

            do {
                isCollectingMeasurementSamples = true
                phase = .recording
#if DEBUG
                if dependencies.sensorCoordinator.isSimulatorVoiceAutomationEnabled {
                    guard await SimulatorVoiceAutomation.waitForAutomatedAnswer() else {
                        isCollectingMeasurementSamples = false
                        return false
                    }
                    isCollectingMeasurementSamples = false
                    guard flowIsCurrent(generation),
                          currentPatchMatches(index: expectedIndex, target: expectedTarget) else {
                        return false
                    }
                    guard let target = activeSession.currentTarget else { return false }
                    var updatedSession = activeSession
                    let answer: SequentialGaborAnswer = switch target {
                    case .left: .direction(.left)
                    case .right: .direction(.right)
                    }
                    guard updatedSession.submit(answer) != .rejected else { return false }
                    acceptedTranscripts.append("[DEBUG simulated voice] \(target.rawValue)")
                    sequentialSession = updatedSession
                    completedTargetCount = updatedSession.currentIndex
                    HapticFeedback.selection()
                    continue
                }
#endif
                let recording = try await dependencies.audioRecorder.record(maximumDuration: 20)
                isCollectingMeasurementSamples = false
                defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
                guard flowIsCurrent(generation),
                      currentPatchMatches(index: expectedIndex, target: expectedTarget) else {
                    return false
                }

                guard recording.adequateLevel else {
                    await retryCurrentTarget(
                        "I didn’t catch that. Say left, right, or I can’t see it.",
                        prompts: dependencies.spokenPrompts,
                        generation: generation
                    )
                    continue
                }

                phase = .checking
                let transcription = try await dependencies.backend.transcribe(
                    audioURL: recording.fileURL,
                    mode: .singleDirection,
                    phraseID: "gabor-single"
                )
                guard flowIsCurrent(generation),
                      currentPatchMatches(index: expectedIndex, target: expectedTarget) else {
                    return false
                }
                let answer: SequentialGaborAnswer?
                if transcription.valid,
                   transcription.mode == .singleDirection,
                   transcription.choice == "notVisible" {
                    answer = .notVisible
                } else if let direction = transcription.singleDirection,
                          direction == .left || direction == .right {
                    answer = .direction(direction)
                } else {
                    answer = nil
                }
                guard let answer else {
                    await retryCurrentTarget(
                        "Say left, right, or I can’t see it.",
                        prompts: dependencies.spokenPrompts,
                        generation: generation
                    )
                    continue
                }

                guard let currentSession = sequentialSession,
                      currentSession.currentIndex == expectedIndex,
                      currentSession.currentTarget == expectedTarget else {
                    return false
                }
                var updatedSession = currentSession
                guard updatedSession.submit(answer) != .rejected else {
                    await retryCurrentTarget(
                        "Say left, right, or I can’t see it.",
                        prompts: dependencies.spokenPrompts,
                        generation: generation
                    )
                    continue
                }

                transientFailureCount = 0
                acceptedTranscripts.append(transcription.transcript)
                sequentialSession = updatedSession
                completedTargetCount = updatedSession.currentIndex
                HapticFeedback.selection()
            } catch is CancellationError {
                isCollectingMeasurementSamples = false
                return false
            } catch AudioBlockRecorder.RecordingError.permissionDenied {
                isCollectingMeasurementSamples = false
                operatorModeRequested = true
                phase = .retry("Microphone access is off. Ask a helper to tap your answers.")
                isRunning = false
                return false
            } catch {
                isCollectingMeasurementSamples = false
                guard flowIsCurrent(generation),
                      currentPatchMatches(index: expectedIndex, target: expectedTarget) else {
                    return false
                }
                transientFailureCount += 1
                let recovery = transientFailureCount >= 3
                    ? "Voice is having trouble. Keep trying, or ask a helper to tap your answer."
                    : "Please say that answer again."
                await retryCurrentTarget(
                    recovery,
                    prompts: dependencies.spokenPrompts,
                    generation: generation
                )
                // The same target remains frozen on screen. Once the concise
                // on-device prompt finishes, listening resumes automatically.
                continue
            }
        }
        return false
    }

    private func retryCurrentTarget(
        _ message: String,
        prompts: SpokenPromptService,
        generation: UUID
    ) async {
        guard flowIsCurrent(generation) else { return }
        isCollectingMeasurementSamples = false
        phase = .retry(message)
        HapticFeedback.warning()
        _ = await prompts.speakLocallyForTransition(message)
        guard flowIsCurrent(generation) else { return }
    }

    private func scoreBlock(
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard flowIsCurrent(generation),
              let completedSession = sequentialSession,
              completedSession.isComplete else {
            isRunning = false
            return
        }

        guard !blockEvidence.didExceedCapacity else {
            isRunning = false
            restartPositioning(
                announcement: "This attempt took too long to measure reliably. I’ll guide you back.",
                dependencies: dependencies
            )
            return
        }
        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: blockEvidence.samples,
            targetDistanceMetres: targetDistance,
            targetToleranceMetres: DistanceGuidanceEngine.exitTolerance(for: targetDistance),
            thresholds: session.activeSession.deviceProfile?.qualityThresholds ?? .conservative
        )
        guard measurementIsAcceptedForGabor(aggregate) else {
            isRunning = false
            targets = []
            sequentialSession = nil
            restartPositioning(
                announcement: "Your position changed. I’ll guide you back.",
                dependencies: dependencies
            )
            return
        }

        let responses = completedSession.responses
        let correct = GaborScorer.correctCount(targets: targets, responses: responses)
        let outcome = GaborScorer.outcome(
            correctCount: correct,
            responseCount: responses.count
        )
        let trial = GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses,
            correctCount: correct,
            outcome: outcome,
            responseSource: .voice,
            transcript: persistedTranscript(from: acceptedTranscripts),
            presentationGeometry: presentationGeometry,
            quality: blockQuality(from: aggregate)
        )
        if eye == .right {
            session.activeSession.rightGaborTrials?.append(trial)
        } else {
            session.activeSession.leftGaborTrials?.append(trial)
        }
        blockEvidence.reset()

        let action = engine.submit(trial)
        isRunning = false
        targets = []
        sequentialSession = nil
        isScoredTargetVisible = false
        presentationGeometry = nil
        switch action {
        case .test:
            await runBlock(
                start: .nextContrast,
                dependencies: dependencies,
                session: session,
                generation: generation
            )
        case .completed(let result):
            await complete(
                result: result,
                dependencies: dependencies,
                session: session,
                generation: generation
            )
        }
    }

    private func restartPositioning(
        announcement: String?,
        dependencies: AppDependencies
    ) {
        isCollectingMeasurementSamples = false
        isRunning = false
        blockLaunchPending = false
        positioningAccepted = false
        completedTargetCount = 0
        targets = []
        sequentialSession = nil
        isScoredTargetVisible = false
        presentationGeometry = nil
        completionDisposition = nil
        phase = .moving
        blockEvidence.reset()
        acceptedTranscripts.removeAll(keepingCapacity: true)
        distanceFilter.reset()
        currentDistance = nil
        targetTracker.reset()
        stabilityProgress = 0
        voiceScheduler.begin(at: Date().timeIntervalSinceReferenceDate)
        dependencies.spokenPrompts.beginNavigationGuidance()
        if let announcement {
            dependencies.spokenPrompts.speak(announcement)
        }
    }

    private func conditionCue(for sample: DistanceSample?) -> DistanceGuidanceCue? {
        guard let sample, sample.faceCount == 1 else { return .findFace }
        if !sample.phoneStable { return .waitForPhone }
        if sample.luminance < 0.12 { return .addLight }
        if abs(sample.headYawDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            || abs(sample.headPitchDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees {
            return .facePhone
        }
        // ARKit gaze is useful coaching, but it is too device- and eye-specific
        // to prevent the participant from entering or completing this task.
        if gazeState == .offCentre { return .lookAtCentre }
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

    private func pause(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    func presentOperatorInput(using dependencies: AppDependencies) {
        guard operatorEntryEnabled else { return }
        invalidateLifecycle()
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        isCollectingMeasurementSamples = false
        isRunning = false
        isCollectingMeasurementSamples = true
        operatorSubmissionResolved = false
        showingOperatorInput = true
    }

    func operatorInputDidDismiss(dependencies: AppDependencies, session: AppSession) {
        guard !operatorSubmissionResolved else { return }
        showingOperatorInput = false
        isCollectingMeasurementSamples = false

        // An operator-only session has no viable microphone path to resume.
        // Keep the current patch and answers intact so the helper sheet can be
        // reopened without triggering speech, recording, or permission loops.
        if operatorModeRequested {
            isRunning = false
            phase = .retry("Microphone response is off. Ask a helper to tap your answers.")
            return
        }

        guard sequentialSession?.currentTarget != nil else {
            restartPositioning(announcement: nil, dependencies: dependencies)
            return
        }
        let generation = lifecycleGeneration
        activeTask = Task { [weak self] in
            guard let self else { return }
            isRunning = true
            guard await collectRequiredAnswers(
                dependencies: dependencies,
                generation: generation
            ) else {
                isRunning = false
                return
            }
            await scoreBlock(
                dependencies: dependencies,
                session: session,
                generation: generation
            )
        }
    }

    func submitOperatorResponses(
        _ responses: [GaborResponse],
        displayedGeometry: GaborPresentationGeometry,
        dependencies: AppDependencies,
        session: AppSession
    ) async {
        showingOperatorInput = false
        operatorSubmissionResolved = true
        isCollectingMeasurementSamples = false
        guard responses.count == totalTargetCount,
              targets.count == totalTargetCount,
              displayedGeometry.isValidCurrentEvidence,
              displayedGeometry == presentationGeometry else {
            phase = .retry("Answer all \(totalTargetCount) stripe patterns.")
            return
        }
        guard let aggregate = acceptedMeasurementQuality(session: session) else {
            restartPositioning(
                announcement: "Your position changed. I’ll guide you back.",
                dependencies: dependencies
            )
            return
        }
        let correct = GaborScorer.correctCount(targets: targets, responses: responses)
        let outcome = GaborScorer.outcome(
            correctCount: correct,
            responseCount: responses.count
        )
        let trial = GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses,
            correctCount: correct,
            outcome: outcome,
            responseSource: .operatorInput,
            transcript: persistedTranscript(from: []),
            presentationGeometry: displayedGeometry,
            quality: blockQuality(from: aggregate)
        )
        if eye == .right {
            session.activeSession.rightGaborTrials?.append(trial)
        } else {
            session.activeSession.leftGaborTrials?.append(trial)
        }
        blockEvidence.reset()
        let action = engine.submit(trial)
        isRunning = false
        targets = []
        sequentialSession = nil
        isScoredTargetVisible = false
        presentationGeometry = nil
        let generation = lifecycleGeneration
        switch action {
        case .test:
            activeTask = Task { [weak self] in
                await self?.runBlock(
                    start: .nextContrast,
                    dependencies: dependencies,
                    session: session,
                    generation: generation
                )
            }
        case .completed(let result):
            await complete(
                result: result,
                dependencies: dependencies,
                session: session,
                generation: generation
            )
        }
    }

    func sensorStreamInvalidated(using dependencies: AppDependencies) {
        invalidateLifecycle()
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        blockEvidence.reset(releasingCapacity: true)
        distanceFilter.reset()
        targetTracker.reset()
        gazeTracker.reset()
        gazeState = .unavailable
        mostRecentSample = nil
        currentDistance = nil
        restartPositioning(
            announcement: "Tracking paused. I’ll guide you back to forty centimetres.",
            dependencies: dependencies
        )
    }

    private func acceptedMeasurementQuality(session: AppSession) -> BlockMeasurementQuality? {
        guard !blockEvidence.didExceedCapacity else { return nil }
        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: blockEvidence.samples,
            targetDistanceMetres: targetDistance,
            targetToleranceMetres: DistanceGuidanceEngine.exitTolerance(for: targetDistance),
            thresholds: session.activeSession.deviceProfile?.qualityThresholds ?? .conservative
        )
        return measurementIsAcceptedForGabor(aggregate) ? aggregate : nil
    }

    private func blockQuality(from aggregate: BlockMeasurementQuality) -> BlockQuality {
        let advisoryReasons: Set<BlockDiscardReason> = [.gazeUnavailable, .gazeOffCentre]
        let blockingReasons = aggregate.blockDiscardReasons.filter { !advisoryReasons.contains($0) }
        return BlockQuality(
            trackingCoverage: aggregate.trackingCoverage,
            phoneStable: !aggregate.issues.contains(.phoneMoved),
            headPoseValid: !aggregate.issues.contains(.headPose),
            distanceStable: !aggregate.issues.contains(where: {
                [.insufficientSamples, .distanceUnavailable, .distanceOffTarget, .distanceUnstable].contains($0)
            }),
            audioLevelAdequate: true,
            targetGeometryValid: presentationGeometry != nil,
            gazeCoverage: aggregate.gazeAvailableCoverage > 0
                ? aggregate.gazeAlignedCoverage
                : nil,
            discardReasons: presentationGeometry == nil
                ? Array(Set(blockingReasons + [.targetGeometry])).sorted { $0.rawValue < $1.rawValue }
                : blockingReasons
        )
    }

    private func complete(
        result: GaborScreeningResult,
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard flowIsCurrent(generation) else { return }
        let evidence = eye == .right
            ? (session.activeSession.rightGaborTrials ?? [])
            : (session.activeSession.leftGaborTrials ?? [])
        let integrity = GaborResultIntegrityValidator.validate(result, against: evidence)
        let persisted = integrity.isValid
            ? result
            : GaborScreeningResult(eye: eye, status: .unreliableMeasurement, responseConsistency: .poor)
        if eye == .right { session.activeSession.rightGaborResult = persisted }
        else { session.activeSession.leftGaborResult = persisted }
        let disposition = GaborCompletionPolicy.disposition(
            for: persisted,
            integrityIsValid: integrity.isValid
        )
        completionDisposition = disposition
        phase = disposition == .reliableCompletion ? .completed : .needsRepeat
        guard disposition == .reliableCompletion else {
            HapticFeedback.warning()
            _ = await dependencies.spokenPrompts.speakForTransition(
                "The \(eye.displayName.lowercased()) eye pattern task needs another try."
            )
            return
        }
        let outcome = await dependencies.spokenPrompts.speakForTransition(
            "\(eye.displayName) eye pattern test complete."
        )
        let expectedRoute: AppRoute = eye == .right ? .rightGaborTest : .leftGaborTest
        guard CompletionNavigationPolicy.shouldAdvance(
            after: outcome,
            expectedRoute: expectedRoute,
            currentRoute: session.path.last,
            expectedGeneration: generation,
            currentGeneration: lifecycleGeneration,
            taskIsCancelled: Task.isCancelled
        ) else { return }
        if eye == .left { dependencies.sensorCoordinator.stop() }
        session.navigate(to: eye == .right ? .leftEyeInstructions : .processing)
    }

    private func flowIsCurrent(_ generation: UUID) -> Bool {
        !Task.isCancelled && generation == lifecycleGeneration
    }

    private func currentPatchMatches(
        index: Int,
        target: GaborOrientation?
    ) -> Bool {
        guard let session = sequentialSession else { return false }
        return session.currentIndex == index && session.currentTarget == target
    }

    private func waitForPresentationGeometry(generation: UUID) async -> Bool {
        for _ in 0..<20 {
            guard flowIsCurrent(generation) else { return false }
            if presentationGeometry != nil { return true }
            guard await pause(milliseconds: 50) else { return false }
        }
        return presentationGeometry != nil && flowIsCurrent(generation)
    }

    private func waitForVoiceConnection(
        _ network: NetworkReachabilityService,
        generation: UUID
    ) async -> Bool {
        for _ in 0..<12 {
            guard flowIsCurrent(generation) else { return false }
            if network.isConnected { return true }
            guard await pause(milliseconds: 500) else { return false }
        }
        return network.isConnected && flowIsCurrent(generation)
    }

    private func measurementIsAcceptedForGabor(_ aggregate: BlockMeasurementQuality) -> Bool {
        aggregate.issues.allSatisfy { issue in
            issue == .gazeUnavailable || issue == .gazeOffCentre
        } && presentationGeometry != nil
    }

    private func persistedTranscript(from transcripts: [String]) -> String? {
        let evidence = transcripts.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return evidence.isEmpty ? nil : evidence.joined(separator: " | ")
    }

    private func invalidateLifecycle() {
        lifecycleGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
    }
}
