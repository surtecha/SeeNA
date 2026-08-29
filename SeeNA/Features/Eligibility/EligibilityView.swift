import SwiftUI

struct EligibilityView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            title: "Check that screening is suitable",
            subtitle: "These rules are handled entirely on your iPhone. AI never makes eligibility or safety decisions."
        ) {
            VStack(spacing: 0) {
                EligibilityToggle(title: "I am wearing distance glasses", isOn: $session.eligibilityAnswers.wearingDistanceGlasses)
                Divider()
                EligibilityToggle(title: "I am wearing contact lenses", isOn: $session.eligibilityAnswers.wearingContactLenses)
                Divider()
                EligibilityToggle(title: "My vision changed suddenly", isOn: $session.eligibilityAnswers.suddenVisionChange, isCritical: true)
                Divider()
                EligibilityToggle(title: "I have severe eye pain or a recent eye injury", isOn: $session.eligibilityAnswers.severePainOrRecentInjury, isCritical: true)
                Divider()
                EligibilityToggle(title: "I can move safely between 40 cm and two metres", isOn: $session.eligibilityAnswers.canMoveSafely)
                Divider()
                EligibilityToggle(title: "I am aged 18 or over", isOn: $session.eligibilityAnswers.isAdult)
            }
            .background(SEENATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if session.eligibilityAnswers.wearingDistanceGlasses {
                Text("Remove distance glasses before screening. If you prefer to keep them on, use accessibility setup only.")
                    .font(.body.weight(.semibold))
                    .foregroundColor(SEENATheme.warning)
            }

            Button("Continue") { session.applyEligibility() }
                .buttonStyle(PrimaryActionStyle())
        }
        .navigationTitle("Eligibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EligibilityToggle: View {
    let title: String
    @Binding var isOn: Bool
    var isCritical = false

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(isCritical && isOn ? SEENATheme.danger : SEENATheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(isCritical ? SEENATheme.danger : SEENATheme.teal)
        .padding(18)
    }
}

struct SafetyStopView: View {
    var body: some View {
        ScreenScaffold(
            title: "Do not continue this screening",
            subtitle: "Sudden vision change, severe eye pain or a recent injury needs professional assessment. SEENA cannot determine the cause."
        ) {
            StatusRow(
                title: "Seek professional advice",
                detail: "Contact an optometrist, doctor or urgent-care service appropriate to your symptoms and location.",
                state: .unavailable
            )
            Text("If symptoms are severe or rapidly worsening, seek urgent medical care.")
                .font(.title3.weight(.bold))
                .foregroundColor(SEENATheme.danger)
        }
        .navigationTitle("Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}
