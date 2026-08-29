import Foundation

/// A single, predictable start sequence for every vision-test row.
/// Movement guidance is closed before this begins, so only these prompts can play.
@MainActor
enum SpokenTestCountdown {
    private static let countdownWords = ["Three.", "Two.", "One."]
    private static let secondsPerCount: TimeInterval = 1

    static func startPrompt(responseInstruction: String) -> String {
        "Stop. \(responseInstruction)"
    }

    static func fromAcceptedPosition(
        prompts: SpokenPromptService,
        responseInstruction: String,
        positionIsValid: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let positionState = PositionHoldState()
        let positionMonitor = Task { @MainActor in
            var consecutiveInvalidChecks = 0
            while !Task.isCancelled {
                guard await wait(nanoseconds: 500_000_000) else { return true }
                if positionIsValid() {
                    consecutiveInvalidChecks = 0
                } else {
                    consecutiveInvalidChecks += 1
                    // Ignore a brief head bob or one noisy depth frame, but
                    // stop the countdown after 1.5 seconds of invalid position.
                    if consecutiveInvalidChecks >= 3 {
                        positionState.isHeld = false
                        prompts.stop()
                        return false
                    }
                }
            }
            return true
        }

        await withTaskCancellationHandler {
            await prompts.speakAfterNavigation(
                startPrompt(responseInstruction: responseInstruction)
            )
        } onCancel: {
            Task { @MainActor in prompts.stop() }
        }

        guard countdownCanContinue(positionState: positionState) else {
            return await finishInterruptedCountdown(
                positionMonitor: positionMonitor,
                prompts: prompts
            )
        }

        // Each count uses the same serialized prompt channel. The deadlines
        // guarantee that Start cannot be spoken until three real seconds after
        // the Three request began, while still allowing a slower voice to finish
        // naturally without ever overlapping the next count.
        let countdownStartedAt = Date()
        for (index, word) in countdownWords.enumerated() {
            await prompts.speakAndWait(word)
            guard countdownCanContinue(positionState: positionState) else {
                return await finishInterruptedCountdown(
                    positionMonitor: positionMonitor,
                    prompts: prompts
                )
            }

            let deadline = countdownStartedAt.addingTimeInterval(
                Double(index + 1) * secondsPerCount
            )
            guard await wait(until: deadline),
                  countdownCanContinue(positionState: positionState) else {
                return await finishInterruptedCountdown(
                    positionMonitor: positionMonitor,
                    prompts: prompts
                )
            }
        }

        await prompts.speakAndWait("Start.")

        positionMonitor.cancel()
        let positionHeld = await positionMonitor.value
        guard !Task.isCancelled else { return false }
        guard positionHeld else {
            await prompts.speakAndWait(
                "Your position changed. I will guide you again."
            )
            return false
        }
        return true
    }

    static func nextRow(
        prompts: SpokenPromptService,
        responseInstruction: String,
        isRetry: Bool = false
    ) async -> Bool {
        await prompts.speakAndWait(
            isRetry
                ? "Let’s try that one again. \(responseInstruction)"
                : "Next. \(responseInstruction)"
        )
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

    private static func wait(until deadline: Date) async -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return !Task.isCancelled }
        return await wait(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    private static func countdownCanContinue(positionState: PositionHoldState) -> Bool {
        !Task.isCancelled && positionState.isHeld
    }

    private static func finishInterruptedCountdown(
        positionMonitor: Task<Bool, Never>,
        prompts: SpokenPromptService
    ) async -> Bool {
        positionMonitor.cancel()
        _ = await positionMonitor.value
        prompts.stop()
        guard !Task.isCancelled else { return false }
        await prompts.speakAndWait("Your position changed. I will guide you again.")
        return false
    }
}

@MainActor
private final class PositionHoldState {
    var isHeld = true
}
