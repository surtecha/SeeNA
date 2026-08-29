import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = WelcomeViewModel()

    var body: some View {
        ActionScaffold(
            eyebrow: "SeeNA · See Now and Always",
            title: "The phone stays. You move.",
            subtitle: "Drag the eye. See how distance drives the test.",
            primaryTitle: "Begin",
            primarySystemImage: "arrow.right",
            primaryAction: { model.begin(session: session) },
            secondaryAction: FloatingAction(
                title: "How it works",
                systemImage: "info",
                action: { session.navigate(to: .howItWorks) }
            )
        ) {
            DistancePlayground(model: model, reduceMotion: reduceMotion)

            HStack(spacing: 10) {
                PrinciplePill(symbol: "iphone", title: "PHONE STILL")
                PrinciplePill(symbol: "figure.walk.motion", title: "YOU MOVE")
            }

            Button {
                HapticFeedback.selection()
                session.navigate(to: .history)
            } label: {
                Label("Local history", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            model.startMotion(reduceMotion: reduceMotion)
        }
        .navigationBarBackButtonHidden()
    }
}

private struct DistancePlayground: View {
    let model: WelcomeViewModel
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("TEST DISTANCE")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Text(model.distanceLabel)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    .frame(width: model.targetDiameter + 26, height: model.targetDiameter + 26)
                    .scaleEffect(model.pulse ? 1.07 : 0.96)
                    .opacity(model.pulse ? 0.25 : 0.8)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: model.pulse
                    )

                PreviewLandoltC(diameter: model.targetDiameter)
                    .animation(.spring(response: 0.36, dampingFraction: 0.82), value: model.targetDiameter)
            }
            .frame(height: 136)

            GeometryReader { proxy in
                let trackWidth = max(1, proxy.size.width - 44)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 2)
                        .padding(.horizontal, 22)

                    Image(systemName: "iphone.gen3")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)

                    ZStack {
                        Circle().fill(Color.white)
                        Image(systemName: "eye.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.black)
                    }
                    .frame(width: 44, height: 44)
                    .offset(x: trackWidth * model.progress)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.82), value: model.progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.setDistance(progress: value.location.x / trackWidth)
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text("40 CM")
                Spacer()
                Text("DRAG THE EYE")
                Spacer()
                Text("2 M")
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(22)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Interactive distance demonstration")
        .accessibilityValue(model.distanceLabel)
        .accessibilityHint("Drag horizontally to change the simulated viewing distance")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.setDistance(progress: model.progress + 0.10)
            case .decrement: model.setDistance(progress: model.progress - 0.10)
            @unknown default: break
            }
        }
    }
}

private struct PreviewLandoltC: View {
    let diameter: Double

    var body: some View {
        ZStack(alignment: .trailing) {
            Circle()
                .stroke(Color.white, lineWidth: max(5, diameter / 5))
                .frame(width: diameter, height: diameter)

            Rectangle()
                .fill(Color.black)
                .frame(width: diameter * 0.34, height: max(8, diameter / 5))
                .offset(x: 1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

private struct PrinciplePill: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(SEENATheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(SEENATheme.card, in: Capsule())
            .overlay {
                Capsule().stroke(SEENATheme.line, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

struct HowItWorksView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScreenScaffold(
            eyebrow: "Guided measurement",
            title: "How SeeNA works",
            subtitle: "Your movement changes the real viewing distance. SeeNA changes the target size so its visual angle remains almost constant."
        ) {
            StatusRow(title: "1. Keep the phone still", detail: "Place it upright at eye level with two metres of clear space.", state: .ready)
            StatusRow(title: "2. Move yourself", detail: "Follow spoken guidance toward or away from the phone.", state: .ready)
            StatusRow(title: "3. Identify the gaps", detail: "Read seven Landolt C directions aloud for each tested distance.", state: .ready)
            StatusRow(title: "4. Review the evidence", detail: "Distances, targets, responses and quality decisions stay auditable.", state: .ready)

            Text("SeeNA returns no numeric estimate when tracking, movement, response or device-profile quality is insufficient.")
                .font(.body.weight(.semibold))
                .foregroundColor(SEENATheme.secondaryInk)

            Button("Continue") { session.navigate(to: .eligibility) }
                .buttonStyle(PrimaryActionStyle())
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
