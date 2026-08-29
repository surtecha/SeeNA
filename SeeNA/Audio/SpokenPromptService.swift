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

    func stop() {
        requestID = UUID()
        playbackTask?.cancel()
        playbackTask = nil
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
        let key = "\(language)|\(text)" as NSString
        let data: Data?
        if let cached = cache.object(forKey: key) {
            data = cached as Data
        } else {
            data = try? await backend.speech(text: text, locale: language)
            if let data { cache.setObject(data as NSData, forKey: key) }
        }

        guard !Task.isCancelled, requestID == self.requestID else { return }
        if let data, await play(data: data) { return }
        await speakWithSystemVoice(text, language: language)
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
