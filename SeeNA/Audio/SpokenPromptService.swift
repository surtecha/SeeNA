import AVFoundation

@MainActor
final class SpokenPromptService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "en-AU") {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestFemaleVoice(language: language)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.02
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.12
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
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
