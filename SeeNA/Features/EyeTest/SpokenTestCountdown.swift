import Foundation

/// A single, predictable start sequence for every vision-test row.
/// Movement guidance is closed before this begins, so only these prompts can play.
@MainActor
enum SpokenTestCountdown {
    static func fromAcceptedPosition(
        prompts: SpokenPromptService,
        responseInstruction: String,
        positionIsValid: @MainActor () -> Bool
    ) async -> Bool {
        await prompts.speakAfterNavigation(
            "Stop. You are in position. The test starts in five seconds."
        )
        // Check twice per second, but require three consecutive bad checks.
        // A natural head bob or one noisy depth frame must not restart guidance.
        var consecutiveInvalidChecks = 0
        for _ in 0..<10 {
            guard await wait(nanoseconds: 500_000_000) else { return false }
            if positionIsValid() {
                consecutiveInvalidChecks = 0
            } else {
                consecutiveInvalidChecks += 1
                if consecutiveInvalidChecks >= 3 {
                    await prompts.speakAndWait(
                        "Your position changed. I will guide you again."
                    )
                    return false
                }
            }
        }
        await prompts.speakAndWait("Start now. \(responseInstruction)")
        return !Task.isCancelled
    }

    static func nextRow(
        prompts: SpokenPromptService,
        responseInstruction: String,
        isRetry: Bool = false
    ) async -> Bool {
        await prompts.speakAndWait(
            isRetry ? "Let’s try that row again in three seconds." : "Next row starts in three seconds."
        )
        guard await wait(nanoseconds: 3_000_000_000) else { return false }
        await prompts.speakAndWait("Start now. \(responseInstruction)")
        return !Task.isCancelled
    }

    private static func wait(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
