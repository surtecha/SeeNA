import SwiftUI

struct TargetStatus {
    let title: String
    let systemImage: String
    let isChecking: Bool
}

struct TargetStatusView: View {
    let status: TargetStatus

    var body: some View {
        HStack(spacing: 9) {
            if status.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.systemImage)
                    .font(.subheadline.weight(.bold))
            }

            Text(status.title)
                .font(.headline.weight(.bold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SEENATheme.card, in: Capsule())
        .overlay {
            Capsule().stroke(SEENATheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrialProgressDots: View {
    let completed: Int
    let total: Int
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Capsule()
                    .fill(index < completed ? SEENATheme.ink : SEENATheme.line)
                    .frame(width: index == completed ? 24 : 8, height: 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: completed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) circles answered")
    }
}

struct TargetSwapModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let rotation: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
    }
}

struct RetryStage: View {
    let message: String
    let geometry: OptotypeGeometry?
    let target: OptotypeDirection?
    let retryButtonTitle: String
    let retryAction: () -> Void
    let operatorAction: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SEENATheme.warning)

                Text("Let’s try that again")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)

                if let geometry, let target {
                    LandoltSingleTargetView(geometry: geometry, direction: target)
                        .frame(minHeight: 180)
                }

                Button(retryButtonTitle, action: retryAction)
                    .buttonStyle(PrimaryActionStyle())

                Button("Use operator input", action: operatorAction)
                    .buttonStyle(SecondaryActionStyle())
            }
            .padding(.vertical, 18)
        }
    }
}

struct CompletionStage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .medium))

            Text("Eye complete")
                .font(.system(.title, design: .rounded, weight: .bold))

            Text("Keep your position for the next test")
                .font(.headline.weight(.medium))
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
