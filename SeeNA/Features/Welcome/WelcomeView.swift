import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("SeeNA")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("A simple eye check")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 14) {
                    TestBadge(symbol: "circle.dotted", label: "Landolt C")
                    TestBadge(symbol: "circle.grid.cross", label: "Gabor")
                }
                Text("After Start, I’ll speak each step.\nYou can answer by voice.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Spacer()
                Button("Start") { begin() }
                    .buttonStyle(PrimaryActionStyle())
                    .accessibilityHint("Starts spoken setup")
                Text("Approximate screening · not a prescription")
                    .font(.caption)
                    .foregroundStyle(SEENATheme.secondaryInk)
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden()
    }

    private func begin() {
        guard session.path.isEmpty else { return }
        HapticFeedback.impact(.medium)
        session.beginJourney()
    }
}

private struct TestBadge: View {
    let symbol: String
    let label: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color.black.opacity(0.06), in: Capsule())
    }
}
