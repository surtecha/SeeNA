import AVFoundation

@MainActor
final class SpokenPromptService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-AU") {
        cancelPendingSpeech()
        synthesizer.speak(Self.utterance(text: text, language: language))
    }

    func speakAndWait(_ text: String, language: String = "en-AU") async {
        cancelPendingSpeech()
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            synthesizer.speak(Self.utterance(text: text, language: language))
        }
    }

    func stop() {
        cancelPendingSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resumePendingSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resumePendingSpeech()
    }

    private func cancelPendingSpeech() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        resumePendingSpeech()
    }

    private func resumePendingSpeech() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }

    private static func utterance(text: String, language: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestFemaleVoice(language: language)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.02
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.12
        return utterance
    }

    private static func bestFemaleVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exactFemale = voices.filter { $0.language == language && $0.gender == .female }
        if let best = exactFemale.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return best
        }

        let languageCode = Locale(identifier: language).language.languageCode?.identifier ?? "en"
        let relatedFemale = voices.filter {
            $0.gender == .female
                && Locale(identifier: $0.language).language.languageCode?.identifier == languageCode
        }
        return relatedFemale.max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: language)
    }
}
