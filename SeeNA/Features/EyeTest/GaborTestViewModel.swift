import Combine
import Foundation

enum GaborTestPhase: Equatable {
    case moving
    case stabilising
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
        case .presenting: return "LOOK AT THE STRIPES"
        case .recording: return "SAY LEFT OR RIGHT"
        case .checking: return "CHECKING"
        case .retry: return "SAY IT AGAIN"
        case .completed: return "ORIENTATION TASK COMPLETE"
        case .needsRepeat: return "REPEAT NEEDED"
        }
    }

    var isTerminal: Bool {
        self == .completed || self == .needsRepeat
    }
}

@MainActor
final class GaborTestViewModel: ObservableObject {
    private static let responseInstruction = "Say left, right, or I can’t see it."

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
    private var blockSamples: [DistanceSample] = []
    private var isCollectingMeasurementSamples = false
    private var sequentialSession: SequentialGaborSession?
    private var acceptedTranscripts: [String] = []
    private var activeTask: Task<Void, Never>?
    private var gazeTracker = GazeReadinessTracker()
    private var gazeState: GazeReadiness = .unavailable
    private var simulatorDistanceOwner: UUID?
    private var operatorSubmissionResolved = false
    private var operatorModeRequested = false
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
        dependencies.spokenPrompts.speak(
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
            blockSamples.append(sample)
            if blockSamples.count > 280 {
                blockSamples.removeFirst(blockSamples.count - 280)
            }
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
                && gazeState == .aligned
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
        restartPositioning(
            announcement: "I’ll guide you back to forty centimetres.",
            dependencies: dependencies
        )
    }

    func cancel(using dependencies: AppDependencies) {
        lifecycleGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        dependencies.sensorCoordinator.releaseSimulatorDistanceOwner(simulatorDistanceOwner)
        simulatorDistanceOwner = nil
        isCollectingMeasurementSamples = false
        isRunning = false
        blockLaunchPending = false
        isScoredTargetVisible = false
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
        guard generation == lifecycleGeneration, !Task.isCancelled, !isRunning else {
            blockLaunchPending = false
            return
        }
        guard case .test(let level) = engine.nextAction else {
            blockLaunchPending = false
            return
        }

        blockLaunchPending = false
        isRunning = true
        isCollectingMeasurementSamples = false
        blockSamples.removeAll(keepingCapacity: true)
        acceptedTranscripts.removeAll(keepingCapacity: true)
        completedTargetCount = 0
        contrast = level
        targets = Self.randomOrientations()
        sequentialSession = SequentialGaborSession(targets: targets)
        isScoredTargetVisible = start != .acceptedPosition
        phase = .presenting

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
            guard countdownCompleted else {
                isCollectingMeasurementSamples = false
                isRunning = false
                targets = []
                sequentialSession = nil
                restartPositioning(announcement: nil, dependencies: dependencies)
                return
            }
            isScoredTargetVisible = true
        } else {
            HapticFeedback.impact()
            guard await pause(milliseconds: 450) else {
                isRunning = false
                return
            }
        }

        if operatorModeRequested || !dependencies.network.isConnected {
            isRunning = false
            phase = .retry(operatorModeRequested
                ? "Microphone response is off. Use the visible operator response controls."
                : "Voice service is offline. Use operator input without waiting for the network.")
            return
        }

        guard await collectSevenAnswers(dependencies: dependencies) else {
            isCollectingMeasurementSamples = false
            isRunning = false
            return
        }
        await scoreBlock(dependencies: dependencies, session: session, generation: generation)
    }

    /// Repeats the same patch for as long as necessary. Transcription and all
    /// spoken retry prompts happen outside the sensor-measurement window.
    private func collectSevenAnswers(dependencies: AppDependencies) async -> Bool {
        while !Task.isCancelled {
            guard let activeSession = sequentialSession else { return false }
            if activeSession.isComplete { return true }

            phase = .presenting
            guard await pause(milliseconds: completedTargetCount == 0 ? 250 : 380) else {
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

                guard recording.adequateLevel else {
                    await retryCurrentTarget(
                        "I didn’t catch that. Say left, right, or I can’t see it.",
                        prompts: dependencies.spokenPrompts
                    )
                    continue
                }

                phase = .checking
                let transcription = try await dependencies.backend.transcribe(
                    audioURL: recording.fileURL,
                    mode: .singleDirection
                )
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
                        prompts: dependencies.spokenPrompts
                    )
                    continue
                }

                var updatedSession = activeSession
                guard updatedSession.submit(answer) != .rejected else {
                    await retryCurrentTarget(
                        "Say left, right, or I can’t see it.",
                        prompts: dependencies.spokenPrompts
                    )
                    continue
                }

                acceptedTranscripts.append(transcription.transcript)
                sequentialSession = updatedSession
                completedTargetCount = updatedSession.currentIndex
                HapticFeedback.selection()
            } catch is CancellationError {
                isCollectingMeasurementSamples = false
                if !showingOperatorInput, sequentialSession?.currentTarget != nil {
                    phase = .retry("The response was interrupted. Repeat this patch or use operator input.")
                    isRunning = false
                }
                return false
            } catch {
                isCollectingMeasurementSamples = false
                phase = .retry("Voice service paused. Use operator input, or repeat this patch.")
                isRunning = false
                return false
            }
        }
        return false
    }

    private func retryCurrentTarget(_ message: String, prompts: SpokenPromptService) async {
        isCollectingMeasurementSamples = false
        phase = .retry(message)
        HapticFeedback.warning()
        _ = await prompts.speakForTransition(message)
    }

    private func scoreBlock(
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard generation == lifecycleGeneration,
              !Task.isCancelled,
              let completedSession = sequentialSession,
              completedSession.isComplete else {
            isRunning = false
            return
        }

        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: blockSamples,
            targetDistanceMetres: targetDistance,
            targetToleranceMetres: DistanceGuidanceEngine.exitTolerance(for: targetDistance),
            thresholds: session.activeSession.deviceProfile?.qualityThresholds ?? .conservative
        )
        guard aggregate.isAccepted else {
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
            hasExactlySevenResponses: responses.count == totalTargetCount
        )
        let trial = GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses,
            correctCount: correct,
            outcome: outcome,
            responseSource: .voice,
            transcript: acceptedTranscripts.joined(separator: " | "),
            quality: blockQuality(from: aggregate)
        )
        if eye == .right {
            session.activeSession.rightGaborTrials?.append(trial)
        } else {
            session.activeSession.leftGaborTrials?.append(trial)
        }

        let action = engine.submit(trial)
        isRunning = false
        targets = []
        sequentialSession = nil
        isScoredTargetVisible = false
        switch action {
        case .test:
            await runBlock(
                start: .nextContrast,
                dependencies: dependencies,
                session: session,
                generation: generation
            )
        case .completed(let result):
            let evidence = eye == .right
                ? (session.activeSession.rightGaborTrials ?? [])
                : (session.activeSession.leftGaborTrials ?? [])
            let integrity = GaborResultIntegrityValidator.validate(result, against: evidence)
            let persistedResult = integrity.isValid
                ? result
                : GaborScreeningResult(
                    eye: eye,
                    status: .unreliableMeasurement,
                    responseConsistency: .poor
                )
            if eye == .right {
                session.activeSession.rightGaborResult = persistedResult
            } else {
                session.activeSession.leftGaborResult = persistedResult
            }
            let disposition = GaborCompletionPolicy.disposition(
                for: persistedResult,
                integrityIsValid: integrity.isValid
            )
            completionDisposition = disposition
            phase = disposition == .reliableCompletion ? .completed : .needsRepeat
            let outcome = await dependencies.spokenPrompts.speakForTransition(
                disposition.spokenMessage(for: eye)
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
        completionDisposition = nil
        phase = .moving
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
        if gazeState != .aligned { return .lookAtCentre }
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
              gazeState == .aligned,
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
        activeTask?.cancel()
        activeTask = nil
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
        guard sequentialSession?.currentTarget != nil else {
            restartPositioning(announcement: nil, dependencies: dependencies)
            return
        }
        let generation = lifecycleGeneration
        activeTask = Task { [weak self] in
            guard let self else { return }
            isRunning = true
            guard await collectSevenAnswers(dependencies: dependencies) else {
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
        dependencies: AppDependencies,
        session: AppSession
    ) async {
        showingOperatorInput = false
        operatorSubmissionResolved = true
        isCollectingMeasurementSamples = false
        guard responses.count == totalTargetCount,
              targets.count == totalTargetCount else {
            phase = .retry("Operator input requires seven answers.")
            return
        }
        guard let aggregate = acceptedMeasurementQuality(session: session) else {
            restartPositioning(
                announcement: "Position quality was not retained. I’ll guide you back.",
                dependencies: dependencies
            )
            return
        }
        let correct = GaborScorer.correctCount(targets: targets, responses: responses)
        let outcome = GaborScorer.outcome(
            correctCount: correct,
            hasExactlySevenResponses: true
        )
        let trial = GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses,
            correctCount: correct,
            outcome: outcome,
            responseSource: .operatorInput,
            transcript: nil,
            quality: blockQuality(from: aggregate)
        )
        if eye == .right {
            session.activeSession.rightGaborTrials?.append(trial)
        } else {
            session.activeSession.leftGaborTrials?.append(trial)
        }
        let action = engine.submit(trial)
        isRunning = false
        targets = []
        sequentialSession = nil
        isScoredTargetVisible = false
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
        lifecycleGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        blockSamples.removeAll(keepingCapacity: false)
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
        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: blockSamples,
            targetDistanceMetres: targetDistance,
            targetToleranceMetres: DistanceGuidanceEngine.exitTolerance(for: targetDistance),
            thresholds: session.activeSession.deviceProfile?.qualityThresholds ?? .conservative
        )
        return aggregate.isAccepted ? aggregate : nil
    }

    private func blockQuality(from aggregate: BlockMeasurementQuality) -> BlockQuality {
        BlockQuality(
            trackingCoverage: aggregate.trackingCoverage,
            phoneStable: !aggregate.issues.contains(.phoneMoved),
            headPoseValid: !aggregate.issues.contains(.headPose),
            distanceStable: !aggregate.issues.contains(where: {
                [.insufficientSamples, .distanceUnavailable, .distanceOffTarget, .distanceUnstable].contains($0)
            }),
            audioLevelAdequate: true,
            targetGeometryValid: true,
            gazeCoverage: aggregate.gazeAlignedCoverage,
            discardReasons: aggregate.blockDiscardReasons
        )
    }

    private func complete(
        result: GaborScreeningResult,
        dependencies: AppDependencies,
        session: AppSession,
        generation: UUID
    ) async {
        guard generation == lifecycleGeneration, !Task.isCancelled else { return }
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
        let outcome = await dependencies.spokenPrompts.speakForTransition(
            disposition.spokenMessage(for: eye)
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

    private static func randomOrientations() -> [GaborOrientation] {
        (0..<SequentialGaborSession.requiredTargetCount).map { _ in
            GaborOrientation.allCases.randomElement() ?? .left
        }
    }
}
