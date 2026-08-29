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
    @Published var showingOperatorInput = false

    private var engine: ThresholdSearchEngine
    private var readySince: Date?
    private var mostRecentSample: DistanceSample?
    private var hasExplainedResizing = false

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

    func begin(using dependencies: AppDependencies) {
        guard candidate != nil else { return }
        phase = .guiding
        announceGuidance(using: dependencies)
    }

    func observe(_ sample: DistanceSample?, dependencies: AppDependencies, session: AppSession) {
        mostRecentSample = sample
        guard !isRunningBlock, candidate != nil, let sample else { return }
        let current = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres
        let tolerance = targetDistance < 1 ? 0.04 : 0.05
        let withinDistance = current.map { abs($0 - targetDistance) <= tolerance } ?? false
        let validPose = sample.faceCount == 1
            && sample.phoneStable
            && abs(sample.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && abs(sample.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && sample.luminance >= 0.12

        if withinDistance && validPose {
            if readySince == nil { readySince = Date() }
            readyProgress = min(1, Date().timeIntervalSince(readySince ?? Date()) / 0.8)
            phase = .stabilising
            if readyProgress >= 1 {
                readySince = nil
                readyProgress = 0
                Task { await runVoiceBlock(dependencies: dependencies, session: session) }
            }
        } else {
            readySince = nil
            readyProgress = 0
            phase = .guiding
        }
    }

    func runVoiceBlock(dependencies: AppDependencies, session: AppSession) async {
        guard !isRunningBlock, candidate != nil else { return }
        isRunningBlock = true
        if targets.count != 7 { targets = Self.randomDirections() }
        phase = .presenting
        await dependencies.spokenPrompts.speakAndWait("Seven rings. Say each opening, left to right.")

        do {
            phase = .recording
            let recording = try await dependencies.audioRecorder.record()
            defer { dependencies.audioRecorder.cleanup(url: recording.fileURL) }
            guard recording.adequateLevel else {
                phase = .retry("The recording was too quiet. Speak the seven directions clearly.")
                isRunningBlock = false
                return
            }
            phase = .transcribing
            let response = try await dependencies.backend.transcribe(audioURL: recording.fileURL, mode: .directionBlock)
            lastTranscript = response.transcript
            guard response.valid, let directions = response.directions, directions.count == 7 else {
                phase = .retry(response.failureReason ?? "I could not recover exactly seven directions.")
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
            isRunningBlock = false
        } catch {
            phase = .retry("Voice transcription is unavailable. Repeat or use operator input.")
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
              let sample = mostRecentSample,
              let actualDistance = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres else {
            phase = .retry("Distance tracking was lost. Return to the target distance.")
            isRunningBlock = false
            return
        }
        phase = .scoring
        let geometry = OptotypeGeometry.calculate(
            distanceMetres: actualDistance,
            pixelsPerInch: profile.pixelsPerInch,
            displayScale: profile.displayScale
        )
        let quality = QualityGateEngine.evaluate(
            sample: sample,
            responseCount: responses.count,
            audioLevelAdequate: audioLevelAdequate,
            targetGeometryValid: geometry != nil,
            orientationChanged: false,
            thresholds: profile.qualityThresholds
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
            distanceStandardDeviation: sample.distanceStandardDeviation ?? .infinity,
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
            if quality.isValid { announceGuidance(using: dependencies) }
        case .completed(let result):
            if eye == .right { session.activeSession.rightEyeResult = result }
            else { session.activeSession.leftEyeResult = result }
            phase = .completed
            await dependencies.spokenPrompts.speakAndWait("\(eye.displayName) eye complete.")
            session.navigate(to: eye == .right ? .rightGaborTest : .leftGaborTest)
        }
    }

    private func announceGuidance(using dependencies: AppDependencies) {
        let distance = targetDistance
        let movement = String(format: "Move to %.2f metres.", distance)
        if hasExplainedResizing {
            dependencies.spokenPrompts.speak(movement)
        } else {
            hasExplainedResizing = true
            dependencies.spokenPrompts.speak(
                "The rings resize as you move. \(movement)"
            )
        }
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

    private static func randomDirections() -> [OptotypeDirection] {
        (0..<7).map { _ in OptotypeDirection.allCases.randomElement() ?? .up }
    }
}
