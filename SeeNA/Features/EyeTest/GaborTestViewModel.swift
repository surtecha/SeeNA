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

    var title: String {
        switch self {
        case .moving: return "Move to 40 cm"
        case .stabilising: return "Hold still"
        case .presenting: return "Look at the stripes"
        case .recording: return "Say left or right"
        case .checking: return "Checking"
        case .retry: return "Let’s repeat that"
        case .completed: return "Contrast check complete"
        }
    }
}

@MainActor
final class GaborTestViewModel: ObservableObject {
    let eye: Eye
    @Published private(set) var phase: GaborTestPhase = .moving
    @Published private(set) var targets: [GaborOrientation] = []
    @Published private(set) var contrast = GaborContrastEngine.contrastLevels[0]
    @Published private(set) var isRunning = false
    @Published private(set) var stabilityProgress = 0.0
    @Published private(set) var currentDistance: Double?
    @Published private(set) var guidanceCue: DistanceGuidanceCue = .findFace

    private var engine: GaborContrastEngine
    private var announcedMove = false
    private var distanceFilter = RobustDistanceFilter()
    private var targetTracker = DistanceTargetTracker()
    private var voiceScheduler = VoiceGuidanceScheduler()
    private var blockLaunchPending = false

    init(eye: Eye) {
        self.eye = eye
        engine = GaborContrastEngine(eye: eye)
    }

    func begin(using dependencies: AppDependencies) {
        guard !announcedMove else { return }
        announcedMove = true
        dependencies.spokenPrompts.preloadNavigationGuidance()
        voiceScheduler.begin(at: Date().timeIntervalSinceReferenceDate)
        dependencies.spokenPrompts.speak(
            "Keep that eye covered. Walk towards the phone. I will tell you when to stop."
        )
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        let measured = sample.flatMap {
            $0.correctedDistanceMetres ?? $0.fusedDistanceMetres ?? $0.rawARDistanceMetres
        }
        currentDistance = distanceFilter.update(measured)
        guard !isRunning, !blockLaunchPending else { return }
        let conditionsReady = sample.map {
            $0.faceCount == 1
                && $0.phoneStable
                && abs($0.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
                && abs($0.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
                && $0.luminance >= 0.12
        } == true
        let timestamp = sample?.timestamp.timeIntervalSinceReferenceDate
            ?? Date().timeIntervalSinceReferenceDate
        let cue = conditionCue(for: sample)
            ?? currentDistance.map { DistanceGuidanceEngine.cue(currentDistance: $0, targetDistance: 0.40) }
            ?? .findFace
        guidanceCue = cue
        if voiceScheduler.shouldAnnounce(cue, at: timestamp) {
            dependencies.spokenPrompts.speak(cue.spokenText)
        }

        let state = targetTracker.update(
            distance: currentDistance,
            target: 0.40,
            conditionsReady: conditionsReady,
            timestamp: timestamp
        )
        stabilityProgress = state.progress
        if state.isInTargetZone {
            phase = .stabilising
            if state.isReady {
                targetTracker.reset()
                stabilityProgress = 0
                blockLaunchPending = true
                HapticFeedback.success()
                Task { await runBlock(dependencies: dependencies, session: session) }
            }
        } else {
            stabilityProgress = 0
            if case .retry = phase { return }
            phase = .moving
        }
    }

    func repeatBlock(dependencies: AppDependencies, session: AppSession) async {
        await runBlock(dependencies: dependencies, session: session)
    }

    private func runBlock(dependencies: AppDependencies, session: AppSession) async {
        guard !isRunning else {
            blockLaunchPending = false
            return
        }
        guard case .test(let level) = engine.nextAction else {
            blockLaunchPending = false
            return
        }
        blockLaunchPending = false
        isRunning = true
        contrast = level
        targets = (0..<7).map { _ in GaborOrientation.allCases.randomElement() ?? .left }
        phase = .presenting
        await dependencies.spokenPrompts.speakAndWait(
            "You are in position. Starting now. Seven stripes. Say left or right, in order."
        )

        do {
            phase = .recording
            let recording = try await dependencies.audioRecorder.record()
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            guard recording.adequateLevel else {
                retry("I could not hear you clearly. Say seven answers, left or right.")
                return
            }

            phase = .checking
            let transcription = try await dependencies.backend.transcribe(
                audioURL: recording.fileURL,
                mode: .directionBlock
            )
            guard transcription.valid,
                  let directions = transcription.directions,
                  directions.count == 7,
                  directions.allSatisfy({ $0 == .left || $0 == .right }) else {
                retry("Please say exactly seven answers using only left or right.")
                return
            }

            let responses = directions.map { $0 == .left ? GaborOrientation.left : .right }
            let correct = GaborScorer.correctCount(targets: targets, responses: responses)
            let outcome = GaborScorer.outcome(
                correctCount: correct,
                hasExactlySevenResponses: responses.count == 7
            )
            let trial = GaborTrial(
                eye: eye,
                contrast: contrast,
                targets: targets,
                responses: responses,
                correctCount: correct,
                outcome: outcome,
                responseSource: .voice,
                transcript: transcription.transcript
            )
            if eye == .right { session.activeSession.rightGaborTrials?.append(trial) }
            else { session.activeSession.leftGaborTrials?.append(trial) }

            let action = engine.submit(trial)
            isRunning = false
            targets = []
            switch action {
            case .test:
                await runBlock(dependencies: dependencies, session: session)
            case .completed(let result):
                if eye == .right { session.activeSession.rightGaborResult = result }
                else { session.activeSession.leftGaborResult = result }
                phase = .completed
                await dependencies.spokenPrompts.speakAndWait("\(eye.displayName) eye contrast check complete.")
                session.navigate(to: eye == .right ? .leftEyeInstructions : .processing)
            }
        } catch is CancellationError {
            isRunning = false
        } catch {
            retry("The voice service was interrupted. Let’s try that row again.")
        }
    }

    private func retry(_ message: String) {
        isRunning = false
        phase = .retry(message)
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
}
