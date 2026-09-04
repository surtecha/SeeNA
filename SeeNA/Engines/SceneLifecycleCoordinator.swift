import Foundation

struct SceneResumePlan: Equatable, Sendable {
    let resumesLiveSensors: Bool
    let restoresScreeningBrightness: Bool
}

/// Pure lifecycle reducer used to make SwiftUI scene transitions idempotent.
/// Resource requirements are supplied only when the suspension is consumed,
/// so the app never resumes capture for a route that is no longer visible.
struct SceneLifecycleCoordinator: Equatable, Sendable {
    private(set) var isSuspended = false

    mutating func beginSuspension() -> Bool {
        guard !isSuspended else { return false }
        isSuspended = true
        return true
    }

    mutating func consumeResumePlan(
        requiresLiveSensors: Bool,
        requiresScreeningBrightness: Bool
    ) -> SceneResumePlan? {
        guard isSuspended else { return nil }
        isSuspended = false
        return SceneResumePlan(
            resumesLiveSensors: requiresLiveSensors,
            restoresScreeningBrightness: requiresScreeningBrightness
        )
    }
}
