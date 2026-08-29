import SwiftUI

struct EyeInstructionsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    let eye: Eye

    var body: some View {
        ScreenScaffold(
            title: "Test your \(eye.displayName.lowercased()) eye",
            subtitle: "Cover your \(eye.eyeToCover) eye gently without pressing on it. Keep your \(eye.displayName.lowercased()) eye open and face the centre of the phone."
        ) {
            Image(systemName: eye == .right ? "eye.circle.fill" : "eye.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .foregroundColor(SEENATheme.teal)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            StatusRow(
                title: "Do not press on the covered eye",
                detail: "Use your palm or an opaque card. Keep the tested eye looking at the screen.",
                state: .ready
            )
            StatusRow(
                title: "Move only between rows",
                detail: "Move slowly, stop at the spoken distance, then hold completely still.",
                state: .ready
            )

            Button("I am ready") {
                session.navigate(to: eye == .right ? .rightEyeTest : .leftEyeTest)
            }
            .buttonStyle(PrimaryActionStyle())
        }
        .onAppear {
            dependencies.spokenPrompts.speak("Cover your \(eye.eyeToCover) eye without pressing it. Keep your \(eye.displayName.lowercased()) eye open. Select I am ready.")
        }
        .navigationTitle("\(eye.displayName) eye")
        .navigationBarTitleDisplayMode(.inline)
    }
}
