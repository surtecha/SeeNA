import SwiftUI

/// A short, silent brand moment shown only while the app launches.
struct LaunchScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var hasStarted = false
    @State private var isNameVisible = false
    @State private var isMarkVisible = false
    @State private var markRotation = 0.0

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("SeeNA")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(Color.black)
                    .opacity(isNameVisible ? 1 : 0)
                    .scaleEffect(isNameVisible ? 1 : 0.97)

                RotatingSeeNAMark(rotation: markRotation)
                    .frame(width: 116, height: 116)
                    .opacity(isMarkVisible ? 1 : 0)
                    .scaleEffect(isMarkVisible ? 1 : 0.88)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("SeeNA")
            .accessibilityAddTraits(.isHeader)
        }
        .task {
            await playLaunchSequence()
        }
    }

    @MainActor
    private func playLaunchSequence() async {
        guard !hasStarted else { return }
        hasStarted = true

        withAnimation(.easeOut(duration: 0.28)) {
            isNameVisible = true
        }

        guard await wait(milliseconds: 340) else { return }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            isMarkVisible = true
        }

        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.0)) {
                markRotation = 360
            }
        }

        guard await wait(milliseconds: reduceMotion ? 560 : 1_120) else { return }
        onFinished()
    }

    private func wait(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// A SwiftUI recreation of the monochrome SeeNA mark. The opening rotates
/// through the same directions used by the Landolt-C test while the centre
/// point remains still.
private struct RotatingSeeNAMark: View {
    let rotation: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)

            Circle()
                .trim(from: 0.11, to: 0.89)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .frame(width: 78, height: 78)
                .rotationEffect(.degrees(rotation - 90))

            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

#Preview("Launch") {
    LaunchScreenView(onFinished: {})
}
