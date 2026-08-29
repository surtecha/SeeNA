import AVFoundation

@MainActor
final class SpokenPromptService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate, @preconcurrency AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let backend: BackendClient
    private let cache = NSCache<NSString, NSData>()

    private var audioPlayer: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var requestID = UUID()
    private var preloadTasks: [String: Task<Data?, Never>] = [:]
    private var preloadBatchTask: Task<Void, Never>?
    private var queuedNavigation: (text: String, language: String)?
    private var navigationWorker: Task<Void, Never>?

    init(backend: BackendClient) {
        self.backend = backend
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-AU") {
        stop()
        let id = requestID
        playbackTask = Task { [weak self] in
            await self?.renderAndPlay(text, language: language, requestID: id)
        }
    }

    func speakAndWait(_ text: String, language: String = "en-AU") async {
        stop()
        let id = requestID
        await renderAndPlay(text, language: language, requestID: id)
    }

    /// Navigation updates are coalesced instead of interrupting speech. While
    /// one cue plays, only the newest pending cue is retained.
    func queueNavigationCue(_ text: String, language: String = "en-AU") {
        queuedNavigation = (text, language)
        guard navigationWorker == nil else { return }
        navigationWorker = Task { [weak self] in
            guard let self else { return }
            await runNavigationQueue()
            navigationWorker = nil
        }
    }

    /// Test instructions must follow the final movement cue, never cut it off.
    func speakAfterNavigation(_ text: String, language: String = "en-AU") async {
        if let navigationWorker {
            await navigationWorker.value
        }
        await speakAndWait(text, language: language)
    }

    /// Warms the finite navigation vocabulary while the user completes setup,
    /// so live movement cues keep the natural backend voice without network lag.
    func preloadNavigationGuidance(language: String = "en-AU") {
        preload(DistanceGuidanceCue.preloadTexts, language: language)
    }

    func stop() {
        requestID = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        navigationWorker?.cancel()
        navigationWorker = nil
        queuedNavigation = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        resumePendingSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resumePendingSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resumePendingSpeech()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        resumePendingSpeech()
    }

    private func renderAndPlay(_ text: String, language: String, requestID: UUID) async {
        let data = await audioData(for: text, language: language)

        guard !Task.isCancelled, requestID == self.requestID else { return }
        if let data, await play(data: data) { return }
        await speakWithSystemVoice(text, language: language)
    }

    private func runNavigationQueue() async {
        while !Task.isCancelled {
            if let playbackTask {
                await playbackTask.value
            }
            guard !Task.isCancelled else { return }
            guard let next = queuedNavigation else { return }
            queuedNavigation = nil
            requestID = UUID()
            let id = requestID
            await renderAndPlay(next.text, language: next.language, requestID: id)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
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

    private func play(data: Data) async -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            guard player.play() else { return false }
            await withCheckedContinuation { continuation in
                pendingContinuation = continuation
            }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            audioPlayer = nil
            return false
        }
    }

    private func speakWithSystemVoice(_ text: String, language: String) async {
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            synthesizer.speak(Self.utterance(text: text, language: language))
        }
    }

    private func resumePendingSpeech() {
        pendingContinuation?.resume()
        pendingContinuation = nil
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
