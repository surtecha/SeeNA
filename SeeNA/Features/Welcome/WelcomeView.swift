import SwiftUI

struct WelcomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 28) {
                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 20 : 44)

                        Text("SeeNA")
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .accessibilityAddTraits(.isHeader)

                        Text("A simple eye check")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        TestBadgeGroup()

                        Text("After Start, I’ll speak each step.\nYou can answer by voice.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SEENATheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 20 : 44)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button("Start") { begin() }
                    .buttonStyle(PrimaryActionStyle())
                    .accessibilityHint("Starts spoken setup")

                Text("Approximate screening · not a prescription")
                    .font(.caption)
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Previous sessions") { session.navigate(to: .history) }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("Shows saved sessions and privacy controls")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.white)
        }
        .navigationBarBackButtonHidden()
    }

    private func begin() {
        guard session.path.isEmpty else { return }
        dependencies.resetForNewScreening()
        HapticFeedback.impact(.medium)
        session.beginJourney()
    }
}

private struct TestBadgeGroup: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    badges
                }
            } else {
                HStack(spacing: 14) {
                    badges
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var badges: some View {
        TestBadge(symbol: "circle.dotted", label: "Landolt C")
        TestBadge(symbol: "circle.grid.cross", label: "Gabor pattern task")
    }
}

private struct TestBadge: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.black.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
