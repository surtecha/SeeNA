import Combine
import SwiftUI

struct PhoneSetupView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: PhoneSetupViewModel

    init(model: PhoneSetupViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ActionScaffold(
            title: "Set down the phone",
            subtitle: "Keep it upright at eye level. SeeNA continues automatically when it is ready.",
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
            TrackingStage(model: model, reduceMotion: reduceMotion)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        trackingPills
                    }
                } else {
                    HStack(spacing: 8) {
                        trackingPills
                    }
                }
            }

            ProgressLine(title: model.instruction, value: model.readinessProgress)
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.3), value: model.readinessProgress)
        }
        .onAppear { model.start() }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, session: session)
        }
        .onReceive(dependencies.sensorCoordinator.$streamEpoch.dropFirst()) { _ in
            model.sensorStreamInvalidated()
        }
        .onDisappear {
            model.stopIfLeavingSetup(nextRoute: session.path.last)
        }
        .navigationTitle("Phone setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var trackingPills: some View {
        TrackingPill(title: "FACE", symbol: "person.crop.circle", ready: model.faceReady)
        TrackingPill(title: "STILL", symbol: "iphone", ready: model.phoneReady)
        TrackingPill(title: "LIGHT", symbol: "sun.max", ready: model.lightReady)
        TrackingPill(
            title: "CENTRE",
            symbol: "eye",
            ready: model.gazeReady,
            advisory: true
        )
    }
}

private struct TrackingStage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: PhoneSetupViewModel
    let reduceMotion: Bool
    @ScaledMetric(relativeTo: .title) private var distanceTextSize = 30.0

    var body: some View {
        VStack(spacing: 18) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        distanceTitle
                        distanceValue
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        distanceTitle
                        Spacer()
                        distanceValue
                    }
                }
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                    .frame(width: 172, height: 172)
                Circle()
                    .trim(from: 0, to: max(0.02, model.readinessProgress))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 172, height: 172)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.36), value: model.readinessProgress)

                GazeIndicator(offset: model.gazeOffset, ready: model.faceReady)
            }

            Text(model.instruction.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(model.isReady ? 1 : 0.78))
                .contentTransition(.opacity)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live phone setup")
        .accessibilityValue("\(model.distanceLabel). \(model.instruction)")
    }

    private var distanceTitle: some View {
        Text("LIVE DISTANCE")
            .font(.caption.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(Color.white.opacity(0.78))
    }

    private var distanceValue: some View {
        Text(model.distanceLabel)
            .font(.system(size: min(distanceTextSize, 48), weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

private struct GazeIndicator: View {
    let offset: CGSize
    let ready: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(Color.white.opacity(ready ? 0.9 : 0.35), lineWidth: 2)
                .frame(width: 104, height: 78)

            HStack(spacing: 25) {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                Circle().fill(Color.white).frame(width: 8, height: 8)
            }

            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .overlay(Circle().fill(Color.black).frame(width: 7, height: 7))
                .offset(offset)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: offset)
        }
        .accessibilityHidden(true)
    }
}

private struct TrackingPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let symbol: String
    let ready: Bool
    var advisory = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: ready ? "checkmark" : symbol)
                .font(.caption.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(ready ? Color.white : SEENATheme.secondaryInk)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .padding(.vertical, 5)
        .background {
            if dynamicTypeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
