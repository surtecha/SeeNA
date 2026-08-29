import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            eyebrow: "Vision screening + accessibility",
            title: "See clearly. Use your phone comfortably.",
            subtitle: "SEENA uses your iPhone camera and a visual target for an approximate myopia screening, then creates a separate readability profile. It never provides an eyeglass prescription or diagnosis."
        ) {
            Button {
                session.navigate(to: .eligibility)
            } label: {
                Label("Start screening", systemImage: "arrow.right")
            }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Begins eligibility and safety questions")

            Button {
                session.navigate(to: .howItWorks)
            } label: {
                Label("How SEENA works", systemImage: "info.circle")
            }
                .buttonStyle(SecondaryActionStyle())

            WelcomeDial()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            PlainCard {
                VStack(spacing: 0) {
                    WelcomeFeatureRow(
                        icon: "iphone",
                        title: "Stationary iPhone",
                        detail: "You move while the phone stays secure"
                    )
                    Divider().overlay(SEENATheme.line)
                    WelcomeFeatureRow(
                        icon: "eye",
                        title: "Each eye measured separately",
                        detail: "Deterministic local scoring and quality gates"
                    )
                    Divider().overlay(SEENATheme.line)
                    WelcomeFeatureRow(
                        icon: "textformat.size",
                        title: "Personal readability profile",
                        detail: "Independent from the myopia estimate"
                    )
                }
            }

            Button("Local history") { session.navigate(to: .history) }
                .font(.headline)
                .foregroundColor(SEENATheme.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .navigationBarBackButtonHidden()
    }
}

private struct WelcomeDial: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SEENATheme.line, lineWidth: 1)
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(
                    SEENATheme.ink,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 7) {
                Text("SEENA")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("SEE NOW AND ALWAYS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.45)
                    .foregroundStyle(SEENATheme.secondaryInk)
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SEENA, See Now and Always")
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SEENATheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

struct HowItWorksView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            eyebrow: "Guided measurement",
            title: "How SEENA works",
            subtitle: "Your movement changes the real viewing distance. SEENA changes the target size so its visual angle remains almost constant."
        ) {
            StatusRow(title: "1. Keep the phone still", detail: "Place it upright at eye level with two metres of clear space.", state: .ready)
            StatusRow(title: "2. Move yourself", detail: "Follow spoken guidance toward or away from the phone.", state: .ready)
            StatusRow(title: "3. Identify the gaps", detail: "Read seven Landolt C directions aloud for each tested distance.", state: .ready)
            StatusRow(title: "4. Review the evidence", detail: "Distances, targets, responses and quality decisions stay auditable.", state: .ready)

            Text("SEENA returns no numeric estimate when tracking, movement, response or device-profile quality is insufficient.")
                .font(.body.weight(.semibold))
                .foregroundColor(SEENATheme.secondaryInk)

            Button("Continue") { session.navigate(to: .eligibility) }
                .buttonStyle(PrimaryActionStyle())
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
