import SwiftUI

struct EyeTestStageView: View {
    let phase: EyeTestPhase
    let geometry: OptotypeGeometry?
    let currentTarget: OptotypeDirection?
    let currentTrialIndex: Int
    let completedTrialCount: Int
    let totalTrialCount: Int
    let distanceInstruction: String
    let currentDistance: Double?
    let targetDistance: Double
    let isAtDistance: Bool
    let readyProgress: Double
    let retryMessage: String?
    let retryButtonTitle: String
    let reduceMotion: Bool
    let retryAction: () -> Void
    let operatorAction: () -> Void

    private var mode: Mode {
        switch phase {
        case .presenting, .recording, .transcribing, .scoring:
            return .target
        case .retry:
            return .retry
        case .completed:
            return .completed
        default:
            return .positioning
        }
    }

    var body: some View {
        ZStack {
            PositioningStage(
                instruction: distanceInstruction,
                currentDistance: currentDistance,
                targetDistance: targetDistance,
                isAtDistance: isAtDistance,
                readyProgress: readyProgress,
                isStabilising: phase == .stabilising
            )
            .opacity(mode == .positioning ? 1 : 0)
            .accessibilityHidden(mode != .positioning)

            SingleTargetStage(
                phase: phase,
                geometry: geometry,
                target: currentTarget,
                trialIndex: currentTrialIndex,
                completedTrialCount: completedTrialCount,
                totalTrialCount: totalTrialCount,
                reduceMotion: reduceMotion
            )
            .opacity(mode == .target ? 1 : 0)
            .accessibilityHidden(mode != .target)

            RetryStage(
                message: retryMessage ?? "Let’s try that circle again.",
                geometry: geometry,
                target: currentTarget,
                retryButtonTitle: retryButtonTitle,
                retryAction: retryAction,
                operatorAction: operatorAction
            )
            .opacity(mode == .retry ? 1 : 0)
            .allowsHitTesting(mode == .retry)
            .accessibilityHidden(mode != .retry)

            CompletionStage()
                .opacity(mode == .completed ? 1 : 0)
                .accessibilityHidden(mode != .completed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: mode)
    }

    private enum Mode: Equatable {
        case positioning
        case target
        case retry
        case completed
    }
}

private struct PositioningStage: View {
    let instruction: String
    let currentDistance: Double?
    let targetDistance: Double
    let isAtDistance: Bool
    let readyProgress: Double
    let isStabilising: Bool

    private var currentDistanceText: String {
        currentDistance.map { String(format: "%.2f m", $0) } ?? "—"
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            Image(systemName: isAtDistance ? "checkmark.circle.fill" : "figure.walk")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.monochrome)

            Text(instruction)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            Text(currentDistanceText)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(isAtDistance ? SEENATheme.ink : SEENATheme.secondaryInk)
                .monospacedDigit()

            Text(String(format: "Target %.2f m", targetDistance))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SEENATheme.secondaryInk)

            ProgressView(value: isStabilising ? readyProgress : 0)
                .tint(SEENATheme.ink)
                .opacity(isStabilising ? 1 : 0)
                .frame(maxWidth: 240)
                .scaleEffect(x: 1, y: 1.6)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SingleTargetStage: View {
    let phase: EyeTestPhase
    let geometry: OptotypeGeometry?
    let target: OptotypeDirection?
    let trialIndex: Int
    let completedTrialCount: Int
    let totalTrialCount: Int
    let reduceMotion: Bool

    private var status: TargetStatus {
        switch phase {
        case .presenting:
            let title = completedTrialCount == 0 ? "Get ready" : "Next circle"
            return TargetStatus(title: title, systemImage: "timer", isChecking: false)
        case .recording:
            return TargetStatus(title: "Listening…", systemImage: "waveform", isChecking: false)
        case .transcribing:
            return TargetStatus(title: "Checking…", systemImage: "ellipsis", isChecking: true)
        case .scoring:
            return TargetStatus(title: "Finishing…", systemImage: "checkmark", isChecking: true)
        default:
            return TargetStatus(title: "Ready", systemImage: "circle", isChecking: false)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            TargetStatusView(status: status)
                .padding(.top, 12)

            Spacer(minLength: 8)

            ZStack {
                if phase == .presenting {
                    NonScoredTargetLocator(reduceMotion: reduceMotion)
                        .transition(.opacity)
                } else if let geometry, let target {
                    ScoredTargetWithLocator(
                        geometry: geometry,
                        target: target,
                        showsLocator: phase == .recording
                    )
                        .id(trialIndex)
                        .transition(targetTransition)
                        .accessibilityLabel("Circle \(trialIndex + 1) of \(totalTrialCount)")
                        .accessibilityHint(
                            "Only the small centre C is scored. The large complete ring is a non-scored guide. Say up, down, left, right, or I can't see it."
                        )
                } else {
                    ProgressView()
                        .scaleEffect(1.25)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88),
                value: trialIndex
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.2),
                value: phase
            )

            Spacer(minLength: 8)

            Text(bottomInstruction)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)

            TrialProgressDots(
                completed: completedTrialCount,
                total: totalTrialCount,
                reduceMotion: reduceMotion
            )
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomInstruction: String {
        switch phase {
        case .presenting:
            return completedTrialCount == 0
                ? "Look at the centre. The test symbol appears after Start."
                : "Same centre. Next symbol."
        case .recording:
            return "Say a direction — or “I can’t see it”"
        default:
            return "Hold still"
        }
    }

    private var targetTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: TargetSwapModifier(opacity: 0, scale: 0.94, rotation: -10),
                identity: TargetSwapModifier(opacity: 1, scale: 1, rotation: 0)
            ),
            removal: .modifier(
                active: TargetSwapModifier(opacity: 0, scale: 0.97, rotation: 8),
                identity: TargetSwapModifier(opacity: 1, scale: 1, rotation: 0)
            )
        )
    }
}

/// Keeps the clinical C unchanged while a symmetric, complete guide ring makes
/// the centre of a phone screen easy to find from the screening position.
private struct ScoredTargetWithLocator: View {
    let geometry: OptotypeGeometry
    let target: OptotypeDirection
    let showsLocator: Bool

    var body: some View {
        ZStack {
            LandoltSingleTargetView(geometry: geometry, direction: target)

            if showsLocator {
                RecordingTargetLocator()
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct RecordingTargetLocator: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SEENATheme.ink.opacity(0.22), lineWidth: 3)
                .frame(width: 210, height: 210)

            Text("GUIDE RING · NOT SCORED")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(SEENATheme.secondaryInk)
                .offset(y: 124)
        }
        .frame(width: 260, height: 260)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A large, directionless locator shown before the scored Landolt C. It makes
/// the phone centre easy to find without leaking an answer or contaminating the
/// standard five-arcminute target used by the measurement engine.
private struct NonScoredTargetLocator: View {
    let reduceMotion: Bool
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    SEENATheme.ink,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round, dash: [20, 13])
                )
                .frame(width: 210, height: 210)

            Circle()
                .fill(SEENATheme.ink)
                .frame(width: 14, height: 14)
        }
        .scaleEffect(reduceMotion || !isBreathing ? 1 : 1.035)
        .opacity(reduceMotion || !isBreathing ? 0.82 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Centre locator. This ring is not scored.")
    }
}
