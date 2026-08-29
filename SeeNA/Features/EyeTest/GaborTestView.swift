import SwiftUI

struct GaborTestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: GaborTestViewModel

    init(eye: Eye) {
        _model = StateObject(wrappedValue: GaborTestViewModel(eye: eye))
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VoiceStatusPill(isListening: model.phase == .recording)
            Text("CONTRAST SCREENING · NOT A DIAGNOSIS")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(SEENATheme.secondaryInk)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            dependencies.sensorCoordinator.start()
            model.begin(using: dependencies)
        }
        .onDisappear {
            model.cancel(using: dependencies)
        }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, dependencies: dependencies, session: session)
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(model.eye.displayName.uppercased()) EYE")
                Spacer()
                Text("CONTRAST")
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(SEENATheme.secondaryInk)

            Text(model.phase.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScoredTargetVisible, let target = model.currentTarget {
            activeTarget(target)
        } else if case .retry(let message) = model.phase {
            retryCard(message)
        } else if model.phase == .checking || model.phase == .completed || model.isRunning {
            transitionStatus
        } else {
            positioning
        }
    }

    private func activeTarget(_ target: GaborOrientation) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("\(model.currentTargetNumber) OF \(model.totalTargetCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: model.trialProgress)
                    .tint(.black)
            }
            .foregroundStyle(SEENATheme.secondaryInk)

            GeometryReader { proxy in
                let available = min(proxy.size.width * 0.72, proxy.size.height * 0.72)
                let targetSize = min(220, max(160, available))

                ZStack {
                    GaborSingleTargetView(
                        orientation: target,
                        contrast: model.contrast,
                        size: targetSize
                    )
                    .id("\(model.contrast)-\(model.completedTargetCount)")
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.94).combined(with: .opacity)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.36, dampingFraction: 0.84),
                    value: model.completedTargetCount
                )
            }

            if case .retry(let message) = model.phase {
                Text(message)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else {
                Text("LEFT  OR  RIGHT")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contrast target \(model.currentTargetNumber) of \(model.totalTargetCount)")
        .accessibilityValue(model.phase == .recording ? "Listening for your answer" : "Presented")
        .accessibilityHint("Say left, right, or I can’t see it")
    }

    private var positioning: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "viewfinder")
                .font(.system(size: 50, weight: .light))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text(model.guidanceCue.displayText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(model.currentDistance.map { String(format: "%.2f m", $0) } ?? "—")
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
            if model.phase == .stabilising {
                ProgressView(value: model.stabilityProgress)
                    .tint(.black)
                    .frame(maxWidth: 220)
                    .transition(.opacity)
            }
            Spacer()
        }
    }

    private var transitionStatus: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: model.phase == .completed ? "checkmark" : "ellipsis")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(.black, in: Circle())
                .transition(.scale.combined(with: .opacity))
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: model.phase != .completed && !reduceMotion
                )
            Text(model.phase == .completed ? "Complete" : "Preparing the next contrast")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38),
            value: model.phase
        )
    }

    private func retryCard(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 46, weight: .medium))
            Text(message)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Button("Recheck position") {
                Task { await model.repeatBlock(dependencies: dependencies, session: session) }
            }
            .buttonStyle(PrimaryActionStyle())
            Spacer()
        }
    }
}

struct VoiceStatusPill: View {
    let isListening: Bool

    var body: some View {
        Label(
            isListening ? "Listening" : "Voice guide on",
            systemImage: isListening ? "waveform" : "speaker.wave.2.fill"
        )
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Color.black.opacity(0.06), in: Capsule())
        .accessibilityValue(
            isListening ? "Microphone is listening" : "Spoken guidance is enabled"
        )
    }
}
