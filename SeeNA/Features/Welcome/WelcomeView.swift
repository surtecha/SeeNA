import SwiftUI

struct WelcomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize = 58.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: dynamicTypeSize.isAccessibilitySize) {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 28) {
                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 20 : 44)

                        Text("SeeNA")
                            .font(.system(size: min(brandSize, 88), weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityAddTraits(.isHeader)

                        Text("A simple eye check")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        TestBadgeGroup()

                        Text("Tap Start. Then listen and answer out loud.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SEENATheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        if dynamicTypeSize.isAccessibilitySize {
                            welcomeActions(horizontalPadding: 0)
                                .padding(.top, 8)
                        }

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
            if !dynamicTypeSize.isAccessibilitySize {
                welcomeActions(horizontalPadding: 24)
            }
        }
        .navigationBarBackButtonHidden()
    }

    private func welcomeActions(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 12) {
            Button("Start") { begin() }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Starts spoken setup")

            Text("Approximate screening · not a prescription")
                .font(.caption.weight(.medium))
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Previous sessions") { session.navigate(to: .history) }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint("Shows saved sessions and privacy controls")
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        .background {
            if dynamicTypeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.06))
            } else {
                Capsule()
                    .fill(Color.black.opacity(0.06))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
