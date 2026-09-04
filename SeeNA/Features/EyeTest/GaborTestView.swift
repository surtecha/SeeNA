import Combine
import SwiftUI

struct GaborTestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: GaborTestViewModel
    @State private var operatorResponses: [GaborResponse] = []
    @State private var operatorGeometry: GaborPresentationGeometry?

    init(eye: Eye) {
        _model = StateObject(wrappedValue: GaborTestViewModel(eye: eye))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: dynamicTypeSize.isAccessibilitySize) {
                VStack(spacing: 14) {
                    header
                    content
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(360, proxy.size.height - 220))

                    VoiceStatusPill(isListening: model.phase == .recording)
                    if model.operatorEntryEnabled {
                        Button("Use helper controls", action: showOperatorInput)
                            .buttonStyle(SecondaryActionStyle())
                            .frame(minHeight: 44)
                    }
                    Text("PATTERN TASK")
                        .font(.caption.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(SEENATheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            dependencies.sensorCoordinator.start()
            model.begin(using: dependencies, session: session)
        }
        .onDisappear {
            model.cancel(using: dependencies)
        }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, dependencies: dependencies, session: session)
        }
        .onReceive(dependencies.sensorCoordinator.$streamEpoch.dropFirst()) { _ in
            model.sensorStreamInvalidated(using: dependencies)
        }
        .sheet(
            isPresented: $model.showingOperatorInput,
            onDismiss: operatorInputDidDismiss
        ) {
            if let operatorGeometry {
                GaborOperatorInputView(
                    targets: model.targets,
                    contrast: model.contrast,
                    geometry: operatorGeometry,
                    responses: $operatorResponses,
                    submit: submitOperatorResponses
                )
            }
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(model.eye.displayName.uppercased()) EYE")
                Spacer()
                Text("PATTERN TASK")
            }
            .font(.caption.weight(.bold))
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
        if model.phase == .teaching {
            orientationTeaching
        } else if model.isScoredTargetVisible, let target = model.currentTarget {
            activeTarget(target)
        } else if case .retry(let message) = model.phase {
            retryCard(message)
        } else if model.phase == .checking || model.phase.isTerminal || model.isRunning {
            transitionStatus
        } else {
            positioning
        }
    }

    private var orientationTeaching: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "line.diagonal")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(Color.black)
                .accessibilityHidden(true)
            Text(GaborTestViewModel.orientationInstruction)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            Text("Listen, then answer after Start.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "How to answer. \(GaborTestViewModel.orientationInstruction) Listen, then answer after Start."
        )
    }

    private func activeTarget(_ target: GaborOrientation) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("\(model.currentTargetNumber) OF \(model.totalTargetCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                ProgressView(value: model.trialProgress)
                    .tint(.black)
            }
            .foregroundStyle(SEENATheme.secondaryInk)

            GeometryReader { proxy in
                let available = min(proxy.size.width - 4, proxy.size.height - 4)
                let proposedTargetSize = max(180, available)
                let proposedGeometry = GaborPresentationGeometry(
                    pointDiameter: Double(proposedTargetSize),
                    displayScale: Double(displayScale)
                )
                let displayedGeometry = model.presentationGeometry ?? proposedGeometry

                ZStack {
                    if let displayedGeometry {
                        GaborSingleTargetView(
                            orientation: target,
                            contrast: model.contrast,
                            geometry: displayedGeometry
                        )
                        .id("\(model.contrast)-\(model.completedTargetCount)")
                        // Fade between targets without scaling the scored patch.
                        // Its measured diameter stays constant for the full answer.
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.36, dampingFraction: 0.84),
                    value: model.completedTargetCount
                )
                .onAppear {
                    if let proposedGeometry {
                        model.registerDisplayedTarget(proposedGeometry)
                    }
                }
                .onChange(of: proposedTargetSize) { _, newValue in
                    if let geometry = GaborPresentationGeometry(
                        pointDiameter: Double(newValue),
                        displayScale: Double(displayScale)
                    ) {
                        model.registerDisplayedTarget(geometry)
                    }
                }
            }

            if case .retry(let message) = model.phase {
                VStack(spacing: 10) {
                    Text(message)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SEENATheme.secondaryInk)
                        .multilineTextAlignment(.center)
                    if model.operatorEntryEnabled {
                        Button("Use helper controls", action: showOperatorInput)
                            .buttonStyle(SecondaryActionStyle())
                            .frame(minHeight: 44)
                    }
                }
                .transition(.opacity)
            } else {
                Text("LEFT  OR  RIGHT")
                    .font(.headline.weight(.bold))
                    .tracking(1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern target \(model.currentTargetNumber) of \(model.totalTargetCount)")
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
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(model.currentDistance.map { String(format: "%.2f m", $0) } ?? "—")
                .font(.system(.title, design: .monospaced, weight: .bold))
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
            Image(systemName: transitionSymbol)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(.black, in: Circle())
                .transition(.scale.combined(with: .opacity))
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: !model.phase.isTerminal && !reduceMotion
                )
            Text(transitionMessage)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            if model.phase == .needsRepeat {
                Button("Repeat pattern task") {
                    Task {
                        await model.repeatBlock(
                            dependencies: dependencies,
                            session: session
                        )
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Restarts positioning and repeats this eye's pattern task")
            }
            Spacer()
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38),
            value: model.phase
        )
    }

    private var transitionSymbol: String {
        switch model.completionDisposition {
        case .reliableCompletion: return "checkmark"
        case .repeatNeeded: return "arrow.counterclockwise"
        case nil: return "ellipsis"
        }
    }

    private var transitionMessage: String {
        if model.phase == .teaching {
            return GaborTestViewModel.orientationInstruction
        }
        if let message = model.completionDisposition?.screenMessage {
            return message
        }
        return model.phase == .checking
            ? "Finishing your pattern task"
            : "Getting the pattern ready"
    }

    private func retryCard(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 46, weight: .medium))
            Text(message)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            Button("Recheck position") {
                Task { await model.repeatBlock(dependencies: dependencies, session: session) }
            }
            .buttonStyle(PrimaryActionStyle())
            if model.operatorEntryEnabled {
                Button("Use helper controls", action: showOperatorInput)
                    .buttonStyle(SecondaryActionStyle())
                    .frame(minHeight: 44)
            }
            Spacer()
        }
    }

    private func showOperatorInput() {
        guard model.operatorEntryEnabled,
              let geometry = model.presentationGeometry else { return }
        operatorResponses = []
        operatorGeometry = geometry
        model.presentOperatorInput(using: dependencies)
    }

    private func submitOperatorResponses() {
        guard let operatorGeometry else { return }
        Task {
            await model.submitOperatorResponses(
                operatorResponses,
                displayedGeometry: operatorGeometry,
                dependencies: dependencies,
                session: session
            )
        }
    }

    private func operatorInputDidDismiss() {
        model.operatorInputDidDismiss(dependencies: dependencies, session: session)
        operatorGeometry = nil
    }
}

private struct GaborOperatorInputView: View {
    @Environment(\.dismiss) private var dismiss
    let targets: [GaborOrientation]
    let contrast: Double
    let geometry: GaborPresentationGeometry
    @Binding var responses: [GaborResponse]
    let submit: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                Text("Helper controls")
                    .font(.title2.bold())

                if targets.indices.contains(responses.count) {
                    GaborSingleTargetView(
                        orientation: targets[responses.count],
                        contrast: contrast,
                        geometry: geometry
                    )
                }

                Text(
                    "Target \(min(responses.count + 1, SequentialGaborSession.requiredTargetCount)) "
                        + "of \(SequentialGaborSession.requiredTargetCount)"
                )
                    .font(.headline)

                    responseButton("Left", response: .left)
                    responseButton("Right", response: .right)
                    responseButton("Not visible", response: .notVisible)

                Button("Undo") { _ = responses.popLast() }
                    .disabled(responses.isEmpty)

                    Button("Submit answers", action: submit)
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(responses.count != SequentialGaborSession.requiredTargetCount)
                }
                .padding(12)
            }
            .navigationTitle("Helper response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func responseButton(_ title: String, response: GaborResponse) -> some View {
        Button(title) {
            guard responses.count < SequentialGaborSession.requiredTargetCount else { return }
            responses.append(response)
        }
        .buttonStyle(SecondaryActionStyle())
        .frame(maxWidth: .infinity, minHeight: 44)
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
