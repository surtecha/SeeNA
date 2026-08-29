import SwiftUI

struct AccessibleDemoView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var isLoading = false

    private let original = "Applicants seeking consideration under the regional transportation reimbursement framework are required to provide documentation substantiating their residence and appointment."

    var body: some View {
        ScreenScaffold(
            title: "Essential-service transformation",
            subtitle: "AI structures allow-listed sample content. SwiftUI applies your locally calculated typography, contrast, spacing and controls."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Before").font(.headline)
                Text(original)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Button("APPLY") {}.font(.caption).buttonStyle(.bordered)
            }
            .padding(14)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isLoading {
                ProgressView("Creating accessible structure…").frame(maxWidth: .infinity).padding(28)
            } else if let content = session.cachedAdaptedContent {
                transformed(content)
            } else {
                Button("Transform this page") { Task { await loadContent() } }
                    .buttonStyle(PrimaryActionStyle())
            }
        }
        .task {
            if session.cachedAdaptedContent == nil { await loadContent() }
        }
        .navigationTitle("Accessible demo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func transformed(_ content: AdaptedContentResponse) -> some View {
        let profile = session.accessibilityProfile ?? .accessibleDefault
        return VStack(alignment: .leading, spacing: profile.increasedLineSpacing ? 20 : 12) {
            Text(content.title)
                .font(.system(size: max(32, profile.comfortablePointSize), weight: .bold, design: .rounded))
            Text(content.summary)
                .font(.system(size: profile.comfortablePointSize))
            Text("You need").font(.title2.bold())
            ForEach(Array(content.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(.system(size: max(20, profile.minimumReadablePointSize), weight: profile.boldTextEnabled ? .semibold : .regular))
            }
            Text(content.deadline).font(.title2.bold()).foregroundColor(SEENATheme.danger)
            if profile.readAloudEnabled {
                Button("Read this page aloud") { dependencies.spokenPrompts.speak(content.readAloudText) }
                    .buttonStyle(SecondaryActionStyle())
            }
            Button(content.primaryAction) {}
                .buttonStyle(PrimaryActionStyle())
                .frame(minHeight: profile.largeControlsEnabled ? 64 : 56)
            if content.usedFallback == true {
                Text("Built-in verified content was used because adaptation was unavailable.")
                    .font(.caption)
            }
        }
        .foregroundColor(profile.highContrastEnabled ? .black : SEENATheme.ink)
        .padding(profile.largeControlsEnabled ? 24 : 18)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(profile.highContrastEnabled ? .black : Color.clear, lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func loadContent() async {
        guard let profile = session.accessibilityProfile else { return }
        isLoading = true
        defer { isLoading = false }
        let request = AdaptContentRequest(
            locale: profile.preferredLanguage,
            contentID: "medical-travel-support-v1",
            highContrast: profile.highContrastEnabled,
            readAloud: profile.readAloudEnabled,
            simplifiedContent: profile.simplifiedContentEnabled
        )
        do {
            session.cachedAdaptedContent = try await dependencies.backend.adapt(request)
        } catch {
            session.cachedAdaptedContent = AdaptedContentResponse(
                title: "Medical Travel Support",
                summary: "You may be able to get help travelling to a medical appointment.",
                steps: ["Prepare photo identification", "Add proof of address", "Add appointment confirmation"],
                deadline: "Submit before 14 September",
                primaryAction: "Start application",
                readAloudText: "Medical Travel Support. You may be able to get help travelling to a medical appointment. Prepare photo identification, proof of address and appointment confirmation. Submit before 14 September.",
                usedFallback: true
            )
        }
    }
}
