import Combine
import SwiftUI

struct BaselineCalibrationView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: CalibrationViewModel

    init(model: CalibrationViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ActionScaffold(
            title: "Move close",
            subtitle: "SeeNA will stop you automatically at 40 centimetres.",
            primaryTitle: model.primaryTitle,
            primarySystemImage: model.primarySystemImage,
            primaryEnabled: model.primaryEnabled,
            primaryAction: { model.primaryAction(session: session) },
            secondaryAction: FloatingAction(
                title: "Hear guide",
                systemImage: "speaker.wave.2",
                action: model.replayGuide
            )
        ) {
            CalibrationStage(model: model, reduceMotion: reduceMotion)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                        calibrationPills
                    }
                } else {
                    HStack(spacing: 10) {
                        calibrationPills
                    }
                }
            }

            ProgressLine(title: model.instruction, value: model.proximityProgress)
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.3), value: model.proximityProgress)
        }
        .onAppear { model.start() }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, session: session)
        }
        .onReceive(dependencies.sensorCoordinator.$streamEpoch.dropFirst()) { _ in
            model.sensorStreamInvalidated()
        }
        .onDisappear(perform: model.cancel)
        .navigationTitle("Distance setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var calibrationPills: some View {
        CalibrationPill(
            title: model.sample?.phoneStable == true ? "PHONE STILL" : "KEEP PHONE STILL",
            symbol: "iphone",
            ready: model.sample?.phoneStable == true
        )
        CalibrationPill(
            title: model.headReady ? "FACE CENTRED" : "FACE THE PHONE",
            symbol: "person.crop.circle",
            ready: model.headReady
        )
        CalibrationPill(
            title: model.gazeState == .aligned ? "LOOKING CENTRE" : "LOOK AT CENTRE",
            symbol: "eye",
            ready: model.gazeState == .aligned,
            advisory: true
        )
    }
}

private struct CalibrationStage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: CalibrationViewModel
    let reduceMotion: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var distanceTextSize = 42.0

    var body: some View {
        VStack(spacing: 18) {
            Text(model.didCapture ? "BASELINE SAVED" : "YOUR DISTANCE")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.78))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                    .frame(width: 214, height: 214)

                Circle()
                    .trim(from: 0, to: max(0.015, model.didCapture ? 1 : model.proximityProgress))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 214, height: 214)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.proximityProgress)

                Circle()
                    .fill(Color.white.opacity(model.isReady ? 0.13 : 0.04))
                    .frame(width: model.isReady ? 174 : 144, height: model.isReady ? 174 : 144)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72), value: model.isReady)

                VStack(spacing: 6) {
                    if model.didCapture {
                        Image(systemName: "checkmark")
                            .font(.system(size: 50, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Text(model.distanceLabel)
                            .font(.system(size: min(distanceTextSize, 62), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        calibrationInstruction
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                calibrationInstruction
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forty centimetre distance setup")
        .accessibilityValue("\(model.distanceLabel). \(model.instruction)")
    }

    private var calibrationInstruction: some View {
        Text(model.instruction.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CalibrationPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let symbol: String
    let ready: Bool
    var advisory = false

    var body: some View {
        Label(title, systemImage: ready ? "checkmark" : symbol)
            .font(.caption2.weight(.bold))
            .tracking(0.35)
            .foregroundStyle(ready ? Color.white : SEENATheme.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.vertical, 5)
            .background {
                if dynamicTypeSize.isAccessibilitySize {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ready ? Color.black : SEENATheme.card)
                } else {
                    Capsule()
                        .fill(ready ? Color.black : SEENATheme.card)
                }
            }
        .animation(.snappy(duration: 0.3), value: ready)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            advisory
                ? (ready ? "Centred" : "Try looking at the centre")
                : (ready ? "Ready" : "Not ready")
        )
    }
}
