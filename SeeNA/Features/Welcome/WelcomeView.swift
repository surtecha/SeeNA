import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            title: "Check how clearly you see and make your phone easier to use.",
            subtitle: "SEENA uses the iPhone camera and a visual target to provide an approximate myopia screening. It does not provide an eyeglass prescription or diagnose eye disease."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Label("One stationary iPhone", systemImage: "iphone")
                Label("Right and left eyes tested separately", systemImage: "eye")
                Label("A separate personalised readability profile", systemImage: "textformat.size")
            }
            .font(.title3.weight(.medium))
            .foregroundColor(SEENATheme.ink)
            .padding(20)
            .background(SEENATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("Start screening") { session.navigate(to: .eligibility) }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Begins eligibility and safety questions")

            Button("How SEENA works") { session.navigate(to: .howItWorks) }
                .buttonStyle(SecondaryActionStyle())

            Button("Local history") { session.navigate(to: .history) }
                .font(.headline)
                .foregroundColor(SEENATheme.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .navigationBarBackButtonHidden()
    }
}

struct HowItWorksView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
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
