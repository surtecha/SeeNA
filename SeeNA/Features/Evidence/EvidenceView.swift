import SwiftUI

/// A calm fallback screen for routes restored from an older saved navigation state.
/// The normal result journey opens the answer sheet directly instead.
struct EvidenceView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            title: "Screening details",
            subtitle: "A simple record of the tasks completed during this screening."
        ) {
            DetailRow(
                title: "Right eye",
                landolt: session.activeSession.rightEyeResult,
                gabor: session.activeSession.rightGaborResult
            )
            DetailRow(
                title: "Left eye",
                landolt: session.activeSession.leftEyeResult,
                gabor: session.activeSession.leftGaborResult
            )

            Text("See answers on your results screen to review the targets and responses from this screening.")
                .font(.body)
                .foregroundStyle(SEENATheme.secondaryInk)

            Text("Vision screening · not a prescription or diagnosis.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SEENATheme.secondaryInk)
        }
        .navigationTitle("Screening details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRow: View {
    let title: String
    let landolt: EyeScreeningResult?
    let gabor: GaborScreeningResult?

    private var detail: String {
        guard landolt != nil, gabor?.status == .completed else { return "Needs another attempt" }
        return "Completed"
    }

    var body: some View {
        StatusRow(title: title, detail: detail, state: detail == "Completed" ? .ready : .warning)
            .accessibilityLabel("\(title): \(detail)")
    }
}
