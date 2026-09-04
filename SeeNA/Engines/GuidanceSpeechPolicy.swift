import Foundation

/// The one speech channel has two kinds of movement guidance: the introductory
/// instruction for a positioning phase and live navigation cues. When the
/// participant reaches position, either may be safely interrupted. Primary
/// narration, such as a result summary, must remain independent.
enum SpeechChannelRequestKind: Equatable, Sendable {
    case prompt
    case guidanceIntro
    case navigation

    var isMovementGuidance: Bool {
        self == .guidanceIntro || self == .navigation
    }
}

/// Keeps accepted-position transitions precise without broad cancellation of
/// unrelated narration on the serialized speech channel.
enum GuidanceSpeechTransitionPolicy {
    static func shouldInterruptForAcceptedPosition(
        activeRequestKind: SpeechChannelRequestKind?,
        navigationFinishedVeryRecently: Bool
    ) -> Bool {
        activeRequestKind?.isMovementGuidance == true
            || (activeRequestKind == nil && navigationFinishedVeryRecently)
    }
}
