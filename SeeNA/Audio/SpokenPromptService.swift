import AVFoundation

@MainActor
final class SpokenPromptService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate, @preconcurrency AVAudioPlayerDelegate {
    nonisolated static let transitionTimeoutNanoseconds: UInt64 = 8_000_000_000

    private enum RequestKind {
        case prompt
        case navigation
    }

    private enum Delivery {
        case backendWithLocalFallback
        case localOnly
    }

    private struct SpeechRequest {
        let id: UUID
        let text: String
        let language: String
        let kind: RequestKind
        let delivery: Delivery

        var navigationKey: String { "\(language)|\(text)" }
    }

    private enum ActiveOutput {
        case audio(
            token: UUID,
            requestID: UUID,
            player: AVAudioPlayer,
            continuation: CheckedContinuation<SpeechOutcome, Never>
        )
        case systemVoice(
            token: UUID,
            requestID: UUID,
            utterance: AVSpeechUtterance,
            continuation: CheckedContinuation<SpeechOutcome, Never>
        )
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let backend: BackendClient
    private let cache = NSCache<NSString, NSData>()

    private var channelGeneration = UUID()
    private var channelWorker: Task<Void, Never>?
    private var activeRequest: SpeechRequest?
    private var activeOutput: ActiveOutput?
    private var promptQueue: [SpeechRequest] = []
    private var queuedNavigation: SpeechRequest?
    private var navigationEnabled = false
    private var lastNavigationKey: String?
    private var lastNavigationFinishedAt: Date?
    private var requestWaiters: [UUID: CheckedContinuation<SpeechOutcome, Never>] = [:]

    private var preloadTasks: [String: Task<Data?, Never>] = [:]
    private var preloadBatchTask: Task<Void, Never>?

    init(backend: BackendClient) {
        self.backend = backend
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks a new primary prompt immediately. Any earlier primary prompt is
    /// cancelled, while navigation remains available if its current screen has
    /// explicitly enabled it.
    func speak(_ text: String, language: String = "en-AU") {
        replaceChannel(with: SpeechRequest(
            id: UUID(),
            text: text,
            language: language,
            kind: .prompt,
            delivery: .backendWithLocalFallback
        ))
    }

    func speakAndWait(_ text: String, language: String = "en-AU") async -> SpeechOutcome {
        let request = SpeechRequest(
            id: UUID(),
            text: text,
            language: language,
            kind: .prompt,
            delivery: .backendWithLocalFallback
        )
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                requestWaiters[request.id] = continuation
                replaceChannel(with: request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRequest(request.id)
            }
        }
    }

    /// A bounded prompt for UI transitions. A normal backend or local voice is
    /// allowed to finish naturally; a stuck renderer/network request is stopped
    /// after the deadline so committed UI state cannot remain disabled forever.
    func speakForTransition(
        _ text: String,
        language: String = "en-AU",
        timeoutNanoseconds: UInt64 = transitionTimeoutNanoseconds
    ) async -> SpeechOutcome {
        await boundedSpeech(timeoutNanoseconds: timeoutNanoseconds) { [weak self] in
            guard let self else { return .cancelled }
            return await self.speakAndWait(text, language: language)
        }
    }

    /// Uses only the on-device speech synthesizer. Result summaries use this
    /// path so locally computed measurements are never sent to the backend.
    func speakLocallyAndWait(_ text: String, language: String = "en-AU") async -> SpeechOutcome {
        let request = SpeechRequest(
            id: UUID(),
            text: text,
            language: language,
            kind: .prompt,
            delivery: .localOnly
        )
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                requestWaiters[request.id] = continuation
                replaceChannel(with: request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRequest(request.id)
            }
        }
    }

    func speakLocallyForTransition(
        _ text: String,
        language: String = "en-AU",
        timeoutNanoseconds: UInt64 = transitionTimeoutNanoseconds
    ) async -> SpeechOutcome {
        await boundedSpeech(timeoutNanoseconds: timeoutNanoseconds) { [weak self] in
            guard let self else { return .cancelled }
            return await self.speakLocallyAndWait(text, language: language)
        }
    }

    /// Starts a fresh movement-guidance epoch. Old directions never leak from
    /// the previous setup or test phase.
    func beginNavigationGuidance() {
        navigationEnabled = true
        queuedNavigation = nil
        lastNavigationKey = nil
        lastNavigationFinishedAt = nil
    }

    /// Navigation updates are latest-wins and never interrupt the active voice.
    /// Identical frame-by-frame updates are suppressed while active, queued, or
    /// immediately after completion.
    func queueNavigationCue(_ text: String, language: String = "en-AU") {
        guard navigationEnabled else { return }
        let request = SpeechRequest(
            id: UUID(),
            text: text,
            language: language,
            kind: .navigation,
            delivery: .backendWithLocalFallback
        )
        let key = request.navigationKey
        if activeRequest?.kind == .navigation, activeRequest?.navigationKey == key { return }
        if queuedNavigation?.navigationKey == key { return }
        if lastNavigationKey == key,
           let lastNavigationFinishedAt,
           Date().timeIntervalSince(lastNavigationFinishedAt) < 2 {
            return
        }
        queuedNavigation = request
        ensureChannelWorker()
    }

    /// Atomically closes movement guidance and discards any direction that has
    /// not started. An already-spoken direction is allowed to finish, then this
    /// prompt is the next and only voice on the audio channel.
    func speakAfterNavigation(_ text: String, language: String = "en-AU") async -> SpeechOutcome {
        let request = SpeechRequest(
            id: UUID(),
            text: text,
            language: language,
            kind: .prompt,
            delivery: .backendWithLocalFallback
        )
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                navigationEnabled = false
                queuedNavigation = nil

            // A cue that is already audible may finish naturally. A cue still
            // waiting on network/rendering must never begin after the app has
            // declared the position accepted.
            if activeRequest?.kind == .navigation, activeOutput == nil {
                cancelChannel(clearQueuedPrompts: false)
            }

                requestWaiters[request.id] = continuation
                promptQueue.append(request)
                ensureChannelWorker()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRequest(request.id)
            }
        }
    }

    func speakAfterNavigationForTransition(
        _ text: String,
        language: String = "en-AU",
        timeoutNanoseconds: UInt64 = transitionTimeoutNanoseconds
    ) async -> SpeechOutcome {
        await boundedSpeech(timeoutNanoseconds: timeoutNanoseconds) { [weak self] in
            guard let self else { return .cancelled }
            return await self.speakAfterNavigation(text, language: language)
        }
    }

    /// Warms the finite navigation vocabulary while the user completes setup,
    /// so live movement cues keep the natural backend voice without network lag.
    func preloadNavigationGuidance(
        additionalTexts: [String] = [],
        language: String = "en-AU"
    ) {
        preload(DistanceGuidanceCue.preloadTexts + additionalTexts, language: language)
    }

    func stop() {
        navigationEnabled = false
        queuedNavigation = nil
        cancelChannel(clearQueuedPrompts: true)
    }

    private func boundedSpeech(
        timeoutNanoseconds: UInt64,
        operation: @escaping @MainActor @Sendable () async -> SpeechOutcome
    ) async -> SpeechOutcome {
        let result = await BoundedSpeechPolicy.wait(
            timeoutNanoseconds: timeoutNanoseconds,
            operation: operation
        )
        switch result {
        case .completed(let outcome):
            return outcome
        case .timedOut:
            stop()
            return .failed
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard case let .systemVoice(token, _, expected, _) = activeOutput,
              expected === utterance else { return }
        finishOutput(token: token, outcome: .finished)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard case let .systemVoice(token, _, expected, _) = activeOutput,
              expected === utterance else { return }
        finishOutput(token: token, outcome: .cancelled)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard case let .audio(token, _, expected, _) = activeOutput,
              expected === player else { return }
        finishOutput(token: token, outcome: flag ? .finished : .failed)
    }

    private func replaceChannel(with request: SpeechRequest) {
        queuedNavigation = nil
        cancelChannel(clearQueuedPrompts: true)
        promptQueue = [request]
        ensureChannelWorker()
    }

    private func cancelChannel(clearQueuedPrompts: Bool) {
        channelGeneration = UUID()
        channelWorker?.cancel()
        channelWorker = nil

        if let activeRequest {
            finishRequest(activeRequest.id, outcome: .cancelled)
        }
        activeRequest = nil
        cancelActiveOutput()

        if clearQueuedPrompts {
            let discarded = promptQueue
            promptQueue.removeAll()
            for request in discarded {
                finishRequest(request.id, outcome: .cancelled)
            }
        }
    }

    private func ensureChannelWorker() {
        guard channelWorker == nil else { return }
        guard !promptQueue.isEmpty || (navigationEnabled && queuedNavigation != nil) else { return }
        let generation = channelGeneration
        channelWorker = Task { [weak self] in
            guard let self else { return }
            await runChannel(generation: generation)
            workerDidFinish(generation: generation)
        }
    }

    private func runChannel(generation: UUID) async {
        while !Task.isCancelled, generation == channelGeneration {
            guard let request = takeNextRequest() else { return }
            activeRequest = request
            let outcome = await renderAndPlay(request, generation: generation)

            guard !Task.isCancelled, generation == channelGeneration else { return }
            if activeRequest?.id == request.id {
                activeRequest = nil
            }
            finishRequest(request.id, outcome: outcome)

            if request.kind == .navigation {
                lastNavigationKey = request.navigationKey
                lastNavigationFinishedAt = Date()
                do {
                    try await Task.sleep(nanoseconds: 450_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func takeNextRequest() -> SpeechRequest? {
        if !promptQueue.isEmpty {
            return promptQueue.removeFirst()
        }
        guard navigationEnabled, let request = queuedNavigation else { return nil }
        queuedNavigation = nil
        return request
    }

    private func workerDidFinish(generation: UUID) {
        guard generation == channelGeneration else { return }
        channelWorker = nil
        ensureChannelWorker()
    }

    private func finishRequest(_ id: UUID, outcome: SpeechOutcome) {
        requestWaiters.removeValue(forKey: id)?.resume(returning: outcome)
    }

    private func renderAndPlay(_ request: SpeechRequest, generation: UUID) async -> SpeechOutcome {
        if request.delivery == .localOnly {
            guard canPlay(request, generation: generation) else { return .cancelled }
            return await speakWithSystemVoice(request.text, language: request.language, request: request)
        }

        let data = await audioData(for: request.text, language: request.language)
        guard canPlay(request, generation: generation) else { return .cancelled }

        if let data {
            let outcome = await play(data: data, request: request, generation: generation)
            switch outcome {
            case .finished, .cancelled:
                return outcome
            case .failed:
                break
            }
        }

        guard canPlay(request, generation: generation) else { return .cancelled }
        return await speakWithSystemVoice(request.text, language: request.language, request: request)
    }

    private func canPlay(_ request: SpeechRequest, generation: UUID) -> Bool {
        !Task.isCancelled
            && generation == channelGeneration
            && activeRequest?.id == request.id
            && activeOutput == nil
    }

    private func preload(_ texts: [String], language: String) {
        guard preloadBatchTask == nil else { return }
        var seen: Set<String> = []
        let pending = texts.filter { text in
            let key = cacheKey(text: text, language: language)
            return seen.insert(key).inserted
                && cache.object(forKey: key as NSString) == nil
                && preloadTasks[key] == nil
        }
        guard !pending.isEmpty else { return }
        preloadBatchTask = Task { [weak self] in
            guard let self else { return }
            await runPreloadQueue(pending, language: language)
            preloadBatchTask = nil
        }
    }

    private func runPreloadQueue(_ texts: [String], language: String) async {
        let batchSize = 4
        for start in stride(from: 0, to: texts.count, by: batchSize) {
            guard !Task.isCancelled else { return }
            let batch = Array(texts[start..<min(texts.count, start + batchSize)])
            var tasks: [(key: String, task: Task<Data?, Never>)] = []
            for text in batch {
                let key = cacheKey(text: text, language: language)
                guard cache.object(forKey: key as NSString) == nil else { continue }
                let task = Task { [backend] in
                    try? await backend.speech(text: text, locale: language)
                }
                preloadTasks[key] = task
                tasks.append((key, task))
            }
            for (key, task) in tasks {
                if let data = await task.value {
                    cache.setObject(data as NSData, forKey: key as NSString)
                }
                preloadTasks[key] = nil
            }
        }
    }

    private func audioData(for text: String, language: String) async -> Data? {
        let key = cacheKey(text: text, language: language)
        if let cached = cache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let preloadTask = preloadTasks[key] {
            let data = await preloadTask.value
            if let data { cache.setObject(data as NSData, forKey: key as NSString) }
            preloadTasks[key] = nil
            return data
        }
        let data = try? await backend.speech(text: text, locale: language)
        if let data { cache.setObject(data as NSData, forKey: key as NSString) }
        return data
    }

    private func cacheKey(text: String, language: String) -> String {
        "\(language)|\(text)"
    }

    private func play(
        data: Data,
        request: SpeechRequest,
        generation: UUID
    ) async -> SpeechOutcome {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            guard canPlay(request, generation: generation) else { return .cancelled }

            let player = try AVAudioPlayer(data: data)
            let token = UUID()
            player.delegate = self
            player.prepareToPlay()
            let outcome = await withCheckedContinuation { continuation in
                activeOutput = .audio(
                    token: token,
                    requestID: request.id,
                    player: player,
                    continuation: continuation
                )
                if !player.play() {
                    finishOutput(token: token, outcome: .failed)
                }
            }

            if generation == channelGeneration, activeOutput == nil {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            return outcome
        } catch {
            return .failed
        }
    }

    private func speakWithSystemVoice(
        _ text: String,
        language: String,
        request: SpeechRequest
    ) async -> SpeechOutcome {
        let utterance = Self.utterance(text: text, language: language)
        let token = UUID()
        return await withCheckedContinuation { continuation in
            activeOutput = .systemVoice(
                token: token,
                requestID: request.id,
                utterance: utterance,
                continuation: continuation
            )
            synthesizer.speak(utterance)
        }
    }

    private func finishOutput(token: UUID, outcome: SpeechOutcome) {
        guard let output = activeOutput else { return }
        switch output {
        case let .audio(activeToken, _, player, continuation):
            guard activeToken == token else { return }
            activeOutput = nil
            player.delegate = nil
            continuation.resume(returning: outcome)
        case let .systemVoice(activeToken, _, _, continuation):
            guard activeToken == token else { return }
            activeOutput = nil
            continuation.resume(returning: outcome)
        }
    }

    private func cancelActiveOutput() {
        guard let output = activeOutput else { return }
        activeOutput = nil
        switch output {
        case let .audio(_, _, player, continuation):
            player.delegate = nil
            player.stop()
            continuation.resume(returning: .cancelled)
        case let .systemVoice(_, _, _, continuation):
            synthesizer.stopSpeaking(at: .immediate)
            continuation.resume(returning: .cancelled)
        }
    }

    private func cancelRequest(_ id: UUID) {
        if activeRequest?.id == id || promptQueue.contains(where: { $0.id == id }) {
            cancelChannel(clearQueuedPrompts: true)
        } else {
            finishRequest(id, outcome: .cancelled)
        }
    }

    private static func utterance(text: String, language: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestFemaleVoice(language: language)
        utterance.rate = 0.56
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.03
        return utterance
    }

    private static func bestFemaleVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let languageCode = Locale(identifier: language).language.languageCode?.identifier ?? "en"
        let exact = voices.filter { $0.language == language && $0.gender == .female }
        let related = voices.filter {
            $0.gender == .female
                && Locale(identifier: $0.language).language.languageCode?.identifier == languageCode
        }
        let candidates = exact.isEmpty ? related : exact
        let preferredNames = ["Karen", "Samantha", "Ava", "Zoe"]
        return candidates.max { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality.rawValue < rhs.quality.rawValue }
            return (preferredNames.firstIndex(of: lhs.name) ?? .max)
                > (preferredNames.firstIndex(of: rhs.name) ?? .max)
        } ?? AVSpeechSynthesisVoice(language: language)
    }
}
