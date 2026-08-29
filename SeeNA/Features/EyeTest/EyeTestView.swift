import SwiftUI

struct EyeTestView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: EyeTestViewModel
    @State private var operatorResponses: [OptotypeDirection] = []

    init(eye: Eye) {
        _model = StateObject(wrappedValue: EyeTestViewModel(eye: eye))
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Spacer(minLength: 12)
            testContent
            Spacer(minLength: 12)
            VoiceStatusPill(isListening: model.phase == .recording)
        }
        .padding(20)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(model.isRunningBlock)
        .onAppear {
            dependencies.brightness.applyScreeningBrightness()
            dependencies.sensorCoordinator.start()
            model.begin(using: dependencies)
        }
        .onReceive(dependencies.sensorCoordinator.$latestSample) { sample in
            model.observe(sample, dependencies: dependencies, session: session)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 56, height: 56)
                .onLongPressGesture(minimumDuration: 2) {
                    operatorResponses = []
                    model.showingOperatorInput = true
                }
                .accessibilityLabel("Open operator response entry")
                .accessibilityHint("Long press for two seconds")
        }
        .sheet(isPresented: $model.showingOperatorInput) {
            OperatorInputView(responses: $operatorResponses) {
                Task {
                    await model.submitOperatorResponses(
                        operatorResponses,
                        dependencies: dependencies,
                        session: session
                    )
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text("\(model.eye.displayName.uppercased()) EYE")
                .font(.caption.weight(.bold))
                .foregroundColor(SEENATheme.teal)
            Text(model.phase.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            if let stage = model.stage {
                Text(stageLabel(stage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(SEENATheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var testContent: some View {
        if case .retry(let message) = model.phase {
            VStack(spacing: 22) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 74))
                    .foregroundColor(SEENATheme.warning)
                Text(message)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if !model.targets.isEmpty, let geometry {
                    LandoltRowView(geometry: geometry, directions: model.targets)
                }
                Button("Repeat voice recording") {
                    Task { await model.repeatVoice(dependencies: dependencies, session: session) }
                }
                .buttonStyle(PrimaryActionStyle())
                Button("Use operator input") {
                    operatorResponses = []
                    model.showingOperatorInput = true
                }
                .buttonStyle(SecondaryActionStyle())
            }
        } else if [.presenting, .recording, .transcribing, .scoring].contains(model.phase),
                  let geometry,
                  model.targets.count == 7 {
            VStack(spacing: 24) {
                LandoltRowView(geometry: geometry, directions: model.targets)
                if model.phase == .recording {
                    Label("Listening…", systemImage: "waveform.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundColor(SEENATheme.danger)
                } else if model.phase == .transcribing || model.phase == .scoring {
                    ProgressView()
                        .scaleEffect(1.4)
                }
            }
        } else {
            VStack(spacing: 20) {
                Text(distanceInstruction)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(currentDistanceText)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundColor(isAtDistance ? SEENATheme.teal : SEENATheme.ink)
                Text(String(format: "Target %.2f m", model.targetDistance))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(SEENATheme.secondaryInk)
                if model.phase == .stabilising {
                    ProgressView(value: model.readyProgress)
                        .tint(SEENATheme.teal)
                        .scaleEffect(x: 1, y: 2)
                }
                Text("The test starts automatically when you are in place.")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(SEENATheme.secondaryInk)
            }
        }
    }

    private var sample: DistanceSample? { session.sensorState }
    private var currentDistance: Double? { sample?.correctedDistanceMetres ?? sample?.fusedDistanceMetres }
    private var currentDistanceText: String { currentDistance.map { String(format: "%.2f m", $0) } ?? "—" }
    private var isAtDistance: Bool {
        guard let currentDistance else { return false }
        return abs(currentDistance - model.targetDistance) <= (model.targetDistance < 1 ? 0.04 : 0.05)
    }
    private var distanceInstruction: String {
        guard let currentDistance else { return "MOVE INTO VIEW" }
        if currentDistance < model.targetDistance - 0.04 { return "MOVE BACK" }
        if currentDistance > model.targetDistance + 0.05 { return "MOVE CLOSER" }
        return sample?.phoneStable == true ? "HOLD STILL" : "STOP MOVING"
    }
    private var geometry: OptotypeGeometry? {
        guard let profile = session.activeSession.deviceProfile else { return nil }
        return OptotypeGeometry.calculate(
            distanceMetres: currentDistance ?? model.targetDistance,
            pixelsPerInch: profile.pixelsPerInch,
            displayScale: profile.displayScale
        )
    }
    private func stageLabel(_ stage: SearchStage) -> String {
        switch stage {
        case .coarse: return "Finding the first clear distance"
        case .fine: return "Refining the threshold"
        case .confirmation: return "Confirming the result"
        case .boundaryConfirmation: return "Confirming the supported boundary"
        }
    }
}

private struct EvidenceValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1)
            Text(label).font(.caption).foregroundColor(SEENATheme.secondaryInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct OperatorInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var responses: [OptotypeDirection]
    let submit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter seven spoken directions")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(responses.map { $0.rawValue.prefix(1).uppercased() }.joined(separator: "  "))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(SEENATheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                LazyVGrid(columns: [.init(), .init()], spacing: 14) {
                    ForEach(OptotypeDirection.allCases, id: \.self) { direction in
                        Button(direction.rawValue.capitalized) {
                            if responses.count < 7 { responses.append(direction) }
                        }
                        .buttonStyle(SecondaryActionStyle())
                    }
                }
                Button("Undo") { _ = responses.popLast() }
                    .disabled(responses.isEmpty)
                Spacer()
                Button("Submit operator responses") { submit() }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(responses.count != 7)
            }
            .padding(24)
            .navigationTitle("Operator fallback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
