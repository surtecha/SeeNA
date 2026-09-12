/// One mutually exclusive state for speech playback, capture and transcription.
enum RefractionVoiceState: Equatable, Sendable {
    case idle, speaking, listening, processing

    var label: String {
        switch self {
        case .idle: return "Your answer"
        case .speaking: return "Get ready"
        case .listening: return "Listening"
        case .processing: return "Checking answer"
        }
    }

    var canStartListening: Bool { self == .idle }
    // Helper input may replace a pending transcription. The view model cancels
    // and invalidates that request before accepting the helper's answer.
    var canAcceptHelperAnswer: Bool { self != .speaking }
}
