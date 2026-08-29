import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var model: PermissionsViewModel

    init(model: PermissionsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ActionScaffold(
            title: "Camera. Voice. Nothing else.",
            subtitle: "Camera stays on-device. Audio is deleted after transcription.",
            primaryTitle: model.primaryTitle,
            primarySystemImage: model.primarySystemImage,
            primaryEnabled: !model.isRequesting,
            primaryAction: {
                Task { await model.primaryAction(session: session) }
            }
        ) {
            PermissionStage(
                cameraGranted: model.cameraGranted,
                microphoneGranted: model.microphoneGranted,
                isRequesting: model.isRequesting
            )

            VStack(spacing: 10) {
                PermissionRow(
                    symbol: "camera.fill",
                    title: "Camera",
                    detail: model.cameraGranted ? "Ready" : "Distance + gaze",
                    granted: model.cameraGranted
                )
                PermissionRow(
                    symbol: "waveform",
                    title: "Voice",
                    detail: model.microphoneGranted ? "Ready" : "Seven directions",
                    granted: model.microphoneGranted
                )
            }
            .animation(.snappy(duration: 0.34), value: model.cameraGranted)
            .animation(.snappy(duration: 0.34), value: model.microphoneGranted)

            if model.requestCompleted && !model.cameraGranted {
                Label("Visual estimate unavailable. Readability mode remains available.", systemImage: "eye.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PermissionStage: View {
    let cameraGranted: Bool
    let microphoneGranted: Bool
    let isRequesting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black)

            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .frame(width: 178, height: 178)
                .scaleEffect(isRequesting ? 1.08 : 0.96)
                .opacity(isRequesting ? 0.25 : 0.8)
                .animation(
                    isRequesting ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                    value: isRequesting
                )

            HStack(spacing: 18) {
                PermissionGlyph(symbol: "camera.fill", granted: cameraGranted)
                PermissionGlyph(symbol: "waveform", granted: microphoneGranted)
            }
        }
        .frame(height: 238)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera \(cameraGranted ? "granted" : "not granted"), microphone \(microphoneGranted ? "granted" : "not granted")")
    }
}

private struct PermissionGlyph: View {
    let symbol: String
    let granted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(granted ? 1 : 0.14))
                .frame(width: 72, height: 72)

            Image(systemName: granted ? "checkmark" : symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(granted ? Color.black : Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(granted ? 1.05 : 1)
        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: granted)
        .accessibilityHidden(true)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .frame(width: 28)
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SEENATheme.secondaryInk)
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.headline)
                .foregroundStyle(granted ? SEENATheme.ink : SEENATheme.tertiaryInk)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(16)
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Granted" : "Not granted")
    }
}
