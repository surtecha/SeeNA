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

    private var engine: GaborContrastEngine
    private var readySince: Date?
    private var announcedMove = false

    init(eye: Eye) {
        self.eye = eye
        engine = GaborContrastEngine(eye: eye)
    }

    func begin(using dependencies: AppDependencies) {
        guard !announcedMove else { return }
        announcedMove = true
        dependencies.spokenPrompts.speak(
            "Keep that eye covered. Move close."
        )
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        guard !isRunning, let sample else { return }
        let distance = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres ?? sample.rawARDistanceMetres
        let ready = distance.map { (0.37...0.43).contains($0) } == true
            && sample.faceCount == 1
            && sample.phoneStable
            && abs(sample.headYawDegrees) <= 10
            && abs(sample.headPitchDegrees) <= 10
            && sample.luminance >= 0.12

        if ready {
            readySince = readySince ?? Date()
            stabilityProgress = min(1, Date().timeIntervalSince(readySince ?? Date()) / 0.8)
            phase = .stabilising
            if stabilityProgress >= 1 {
                readySince = nil
                stabilityProgress = 0
                Task { await runBlock(dependencies: dependencies, session: session) }
            }
        } else {
            readySince = nil
            stabilityProgress = 0
            if case .retry = phase { return }
            phase = .moving
        }
    }

    func repeatBlock(dependencies: AppDependencies, session: AppSession) async {
        await runBlock(dependencies: dependencies, session: session)
    }

    private func runBlock(dependencies: AppDependencies, session: AppSession) async {
        guard !isRunning else { return }
        guard case .test(let level) = engine.nextAction else { return }
        isRunning = true
        contrast = level
        targets = (0..<7).map { _ in GaborOrientation.allCases.randomElement() ?? .left }
        phase = .presenting
        await dependencies.spokenPrompts.speakAndWait(
            "Seven stripes. Say left or right, in order."
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
}
