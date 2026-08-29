import SwiftUI

struct GaborTestView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: GaborTestViewModel

    init(eye: Eye) {
        _model = StateObject(wrappedValue: GaborTestViewModel(eye: eye))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            Text("\(model.eye.displayName) eye · Gabor")
                .font(.headline)
                .foregroundStyle(SEENATheme.secondaryInk)
            Text(model.phase.title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VoiceStatusPill(isListening: model.phase == .recording)
            Text("Contrast screening · not a diagnosis")
                .font(.caption)
                .foregroundStyle(SEENATheme.secondaryInk)
        }
        .padding(20)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            dependencies.sensorCoordinator.start()
            model.begin(using: dependencies)
        }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, dependencies: dependencies, session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .retry(let message) = model.phase {
            VStack(spacing: 18) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 54))
                Text(message)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                Button("Repeat") {
                    Task { await model.repeatBlock(dependencies: dependencies, session: session) }
                }
                .buttonStyle(PrimaryActionStyle())
            }
        } else if !model.targets.isEmpty {
            VStack(spacing: 18) {
                GaborRowView(orientations: model.targets, contrast: model.contrast)
                Text("LEFT OR RIGHT")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 64, weight: .light))
                Text(model.guidanceCue.displayText)
                    .font(.title2.weight(.bold))
                Text(model.currentDistance.map { String(format: "%.2f m", $0) } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                if model.phase == .stabilising {
                    ProgressView(value: model.stabilityProgress)
                        .tint(.black)
                }
            }
        }
    }
}

struct VoiceStatusPill: View {
    let isListening: Bool

    var body: some View {
        Label(isListening ? "Listening" : "Voice guide on", systemImage: isListening ? "waveform" : "speaker.wave.2.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.black.opacity(0.06), in: Capsule())
            .accessibilityValue(isListening ? "Microphone is listening" : "Spoken guidance is enabled")
    }
}
