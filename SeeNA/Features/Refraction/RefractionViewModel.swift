import Combine
import Foundation

@MainActor
final class RefractionViewModel: ObservableObject {
    enum Phase { case introduction, calibration, positioning, answering, nextEye, finished }
    @Published private(set) var phase: Phase = .introduction
    @Published var eligibilityConfirmed = false
    @Published var rulerMillimetres = ""
    @Published var distanceCentimetres = ""
    @Published private(set) var eye: Eye = .right
    @Published private(set) var search = FarPointSearch(eye: .right)
    @Published private(set) var targets: [OptotypeDirection] = []
    @Published private(set) var answers: [OptotypeResponse] = []
    @Published private(set) var targetPoints: Double = 0
    @Published private(set) var voiceState: RefractionVoiceState = .idle
    var listening: Bool { voiceState == .listening }
    var speaking: Bool { voiceState == .speaking }
    @Published private(set) var message: String?
    @Published private(set) var record: RefractionRecord?
    @Published private(set) var saved = false
    @Published private(set) var saving = false
    private var millimetresPerPoint = 0.0
    private var displayScale = 0.0
    private var measuredDistance = 0.0
    private var previousLevels: [FarPointLevel] = []
    private var voiceTask: Task<Void, Never>?
    private var generation = UUID()
    private var introducedTarget = false
    private let createdAt = Date()
    private let id = UUID()

    var currentTarget: OptotypeDirection? { targets.indices.contains(answers.count) ? targets[answers.count] : nil }
    var round: Int { search.repetition + 1 }
    var requestedCentimetres: String { String(format: "%.1f", search.requestedDistance * 100) }

    func begin() {
        guard eligibilityConfirmed else { return }
        phase = .calibration
    }

    func calibrate(displayScale: Double) {
        guard let measuredMM = Self.number(rulerMillimetres), (16...60).contains(measuredMM),
              displayScale.isFinite, (1...4).contains(displayScale) else {
            message = "Enter the measured line length in millimetres."; return
        }
        millimetresPerPoint = measuredMM / 200
        self.displayScale = displayScale
        guard FarPointProtocol.targetPoints(distance: 0.4, millimetresPerPoint: millimetresPerPoint,
                                            displayScale: displayScale) != nil else {
            message = "This display cannot resolve the smallest target. Check your ruler measurement. Do not enlarge the test."; return
        }
        preparePosition()
    }

    func preparePosition() {
        phase = .positioning
        distanceCentimetres = "" // A requested distance is never a measured reading.
        message = nil
        targets = []
        answers = []
    }

    func startLevel(using dependencies: AppDependencies) {
        guard phase == .positioning else { return }
        guard let cm = Self.number(distanceCentimetres),
              abs(cm / 100 - search.requestedDistance) <= FarPointProtocol.distanceReadingBound + 0.000_001,
              let points = FarPointProtocol.targetPoints(distance: cm / 100,
                 millimetresPerPoint: millimetresPerPoint, displayScale: displayScale) else {
            message = "Measure from the eye to the screen. Enter a reading within 0.5 cm of the requested position."; return
        }
        measuredDistance = cm / 100
        targetPoints = points
        // Independent random draws preserve a known 1/4 chance per answer.
        // Do not announce or expose the correct direction in accessibility.
        targets = (0..<FarPointProtocol.responsesPerLevel).map { _ in OptotypeDirection.allCases.randomElement()! }
        answers = []
        phase = .answering
        message = nil
        dependencies.brightness.applyScreeningBrightness()
        startVoice(using: dependencies, countdown: true)
    }

    func submit(_ response: OptotypeResponse, using dependencies: AppDependencies) {
        guard phase == .answering, currentTarget != nil, voiceState.canAcceptHelperAnswer else { return }
        stopVoice(using: dependencies)
        answers.append(response)
        HapticFeedback.selection()
        if answers.count == targets.count {
            let level = FarPointLevel(id: UUID(), eye: eye, repetition: search.repetition,
                requestedDiopter: search.requestedDiopter, measuredDistanceMetres: measuredDistance,
                targets: targets, responses: answers, recordedAt: Date())
            guard search.submit(level) else {
                preparePosition(); message = "Let’s repeat that measurement."; return
            }
            if search.isFinished {
                if eye == .right { phase = .nextEye }
                else {
                    record = RefractionRecord(id: id, createdAt: createdAt, protocolIdentifier: FarPointProtocol.identifier,
                        millimetresPerPoint: millimetresPerPoint, displayScale: displayScale,
                        levels: previousLevels + search.levels)
                    phase = .finished
                    dependencies.brightness.restore()
                }
            } else { preparePosition() }
        } else { startVoice(using: dependencies, countdown: false) }
    }

    func nextEye() {
        guard phase == .nextEye else { return }
        previousLevels = search.levels
        eye = .left
        search = FarPointSearch(eye: .left)
        preparePosition()
    }

    func repeatPosition(using dependencies: AppDependencies) {
        stopVoice(using: dependencies)
        guard phase == .answering else { return }
        preparePosition()
        message = "Position changed. Measure again before continuing."
    }

    func stopVoice(using dependencies: AppDependencies) {
        generation = UUID()
        voiceTask?.cancel()
        // Retain the task until its replacement can await recorder cleanup.
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        voiceState = .idle
    }

    func pauseForExit(using dependencies: AppDependencies) {
        stopVoice(using: dependencies)
        if phase == .answering {
            message = "Paused. Tap Listen to continue, or ask your helper to enter the answer."
        }
    }

    func startVoice(using dependencies: AppDependencies, countdown: Bool = false) {
        guard phase == .answering, voiceState.canStartListening else { return }
        let previousTask = voiceTask
        stopVoice(using: dependencies)
        let token = generation
        let index = answers.count
        message = nil
        voiceState = countdown ? .speaking : .listening
        voiceTask = Task { [weak self] in
            guard let self else { return }
            // Await cancellation cleanup before reusing the shared audio session.
            await previousTask?.value
            guard token == generation, !Task.isCancelled else { return }
            defer {
                // An obsolete task must never clear a newer capture's state.
                if token == generation { voiceState = .idle }
            }
#if DEBUG && targetEnvironment(simulator)
            if SimulatorRefractionAutomation.enabled {
                voiceState = .listening
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard token == generation, let response = SimulatorRefractionAutomation.response(model: self) else { return }
                submit(response, using: dependencies)
                return
            }
#endif
            if countdown {
                if !introducedTarget {
                    let outcome = await dependencies.spokenPrompts.speakAndWait(
                        "The letter is small by design. Say where its arms point: up, down, left or right. If it’s unclear, say I can’t see it."
                    )
                    guard token == generation, !Task.isCancelled else { return }
                    guard outcome == .finished else {
                        message = "Guide paused. Tap Listen, or use the helper controls."; return
                    }
                    introducedTarget = true
                }
                for word in ["Three", "Two", "One", "Start"] {
                    let spoken = await dependencies.spokenPrompts.speakLocallyAndWait(word)
                    guard token == generation, !Task.isCancelled else { return }
                    guard spoken == .finished else {
                        message = "Guide paused. Tap Listen to continue."; return
                    }
                    if word != "Start" { try? await Task.sleep(for: .milliseconds(350)) }
                }
                voiceState = .listening
            }
            do {
                voiceState = .listening
                let capture = try await dependencies.audioRecorder.record(maximumDuration: 20)
                defer { dependencies.audioRecorder.cleanup(url: capture.fileURL) }
                guard token == generation, !Task.isCancelled else { return }
                guard capture.adequateLevel else {
                    message = "I didn’t catch a complete answer. Tap Listen, or ask your helper to enter it."; return
                }
                voiceState = .processing
                let response = try await dependencies.backend.transcribe(audioURL: capture.fileURL,
                    mode: .singleDirection, phraseID: "landolt-single")
                guard token == generation, !Task.isCancelled, phase == .answering, answers.count == index else { return }
                let answer = response.singleDirection.map(OptotypeResponse.init)
                    ?? ((response.valid && response.mode == .singleDirection && response.choice == "notVisible") ? .notVisible : nil)
                guard let answer else { message = "Please give one direction, or say I can’t see it."; return }
                submit(answer, using: dependencies)
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                message = "Voice is unavailable. Your helper can tap the answer below."
            }
        }
    }

    func save(to store: RefractionStore) async {
        guard let record, !saved, !saving else { return }
        saving = true
        defer { saving = false }
        do { try await store.save(record); saved = true; message = nil; HapticFeedback.success() }
        catch { message = "Could not save. Your result is still here. Please try again." }
    }

    private static func number(_ text: String) -> Double? {
        let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        return value?.isFinite == true ? value : nil
    }
}
