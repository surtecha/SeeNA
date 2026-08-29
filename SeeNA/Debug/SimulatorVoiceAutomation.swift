import Foundation

// This file intentionally has no Release implementation. The launch argument
// is a simulator QA aid only; production builds never compile this code.
#if DEBUG
@MainActor
enum SimulatorVoiceAutomation {
    static let launchArgument = "-SEENA_AUTOMATE_VOICE_RESPONSES"

    /// Automation is deliberately double-gated: it can only run when the
    /// explicit argument is present *and* the existing mock sensor stream is
    /// in use. A normal Debug build remains a real, hands-free test.
    static func isEnabled(usingMockSensors: Bool) -> Bool {
        usingMockSensors
            && ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Stable, realistic-enough mock measurements which follow the screen's
    /// requested distance. The small deterministic variation exercises the
    /// same target-zone and quality gates as a live stream.
    static func distance(target: Double, tick: Int) -> Double {
        target + 0.002 * sin(Double(tick) * 0.37)
    }

    /// Preserve the three-step start gate while making simulator journeys
    /// short. This never speaks or bypasses the position validity checks.
    static func shortCountdown(positionIsValid: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<3 {
            guard !Task.isCancelled, positionIsValid() else { return false }
            guard await wait(milliseconds: 90) else { return false }
        }
        return !Task.isCancelled && positionIsValid()
    }

    /// Keeps a target visible and sensor sampling active long enough for the
    /// normal block-quality minimum while avoiding microphone/network I/O.
    static func waitForAutomatedAnswer() async -> Bool {
        await wait(milliseconds: 1_500)
    }

    private static func wait(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
#endif
