import Combine
import SwiftUI

struct EyeTestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: EyeTestViewModel
    @State private var operatorResponses: [OptotypeResponse] = []

    private var geometry: OptotypeGeometry? {
        model.presentedGeometry?.geometry
    }

    private var retryMessage: String? {
        guard case .retry(let message) = model.phase else { return nil }
        return message
    }

    init(eye: Eye) {
        _model = StateObject(wrappedValue: EyeTestViewModel(eye: eye))
    }

    var body: some View {
        VStack(spacing: 0) {
            EyeTestProgressHeader(
                eye: model.eye,
                currentTrial: visibleTrialNumber,
                totalTrials: model.totalTrialCount
            )

            EyeTestStageView(
                phase: model.phase,
                geometry: geometry,
                currentTarget: model.currentTarget,
                currentTrialIndex: model.currentTrialIndex,
                completedTrialCount: model.completedTrialCount,
                totalTrialCount: model.totalTrialCount,
                distanceInstruction: model.guidanceCue.displayText,
                currentDistance: model.currentDistance,
                targetDistance: model.targetDistance,
                isAtDistance: model.isInTargetZone,
                readyProgress: model.readyProgress,
                retryMessage: retryMessage,
                retryButtonTitle: model.retryButtonTitle,
                reduceMotion: reduceMotion,
                retryAction: repeatVoiceResponse,
                operatorAction: showOperatorInput
            )
            if model.operatorEntryEnabled {
                Button("Use operator response mode", action: showOperatorInput)
                    .buttonStyle(SecondaryActionStyle())
                    .frame(minHeight: 44)
                    .accessibilityHint(
                        "Stops voice recording and opens \(model.totalTrialCount) large response controls"
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(model.isRunningBlock)
        .onAppear(perform: beginTest)
        .onReceive(dependencies.sensorCoordinator.$latestSample, perform: observe)
        .onReceive(dependencies.sensorCoordinator.$streamEpoch.dropFirst()) { _ in
            model.sensorStreamInvalidated(using: dependencies)
        }
        .onDisappear {
            model.cancel(using: dependencies)
        }
        .overlay(alignment: .topLeading) {
            operatorEntryGesture
        }
        .sheet(
            isPresented: $model.showingOperatorInput,
            onDismiss: operatorInputDidDismiss
        ) {
            OperatorInputView(
                targets: model.targets,
                geometry: geometry,
                responses: $operatorResponses,
                submit: submitOperatorResponses
            )
        }
    }

    private var visibleTrialNumber: Int {
        min(max(model.currentTrialIndex + 1, 1), max(model.totalTrialCount, 1))
    }

    private var operatorEntryGesture: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: 56, height: 56)
            .onLongPressGesture(minimumDuration: 2, perform: showOperatorInput)
            .allowsHitTesting(model.operatorEntryEnabled)
            .accessibilityHidden(!model.operatorEntryEnabled)
            .accessibilityLabel("Open operator response entry")
            .accessibilityHint("Long press for two seconds")
    }

    private func beginTest() {
        dependencies.brightness.applyScreeningBrightness()
        dependencies.sensorCoordinator.start()
        model.begin(using: dependencies, session: session)
    }

    private func observe(_ sample: DistanceSample?) {
        model.observe(sample, dependencies: dependencies, session: session)
    }

    private func repeatVoiceResponse() {
        Task {
            await model.repeatVoice(dependencies: dependencies, session: session)
        }
    }

    private func showOperatorInput() {
        guard model.operatorEntryEnabled else { return }
        operatorResponses = []
        model.presentOperatorInput(using: dependencies)
    }

    private func submitOperatorResponses() {
        Task {
            await model.submitOperatorResponses(
                operatorResponses,
                dependencies: dependencies,
                session: session
            )
        }
    }

    private func operatorInputDidDismiss() {
        model.operatorInputDidDismiss(
            dependencies: dependencies,
            session: session
        )
    }
}

private struct EyeTestProgressHeader: View {
    let eye: Eye
    let currentTrial: Int
    let totalTrials: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(eye.displayName) eye")
                .font(.headline.weight(.bold))

            Spacer(minLength: 12)

            Text("Circle \(currentTrial) of \(totalTrials)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(SEENATheme.card, in: Capsule())
                .overlay {
                    Capsule().stroke(SEENATheme.line, lineWidth: 1)
                }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

private struct OperatorInputView: View {
    @Environment(\.dismiss) private var dismiss
    let targets: [OptotypeDirection]
    let geometry: OptotypeGeometry?
    @Binding var responses: [OptotypeResponse]
    let submit: () -> Void

    private var responseSummary: String {
        responses.map { $0.auditCode }.joined(separator: "  ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                Text("Operator response")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if targets.indices.contains(responses.count), let geometry {
                    LandoltSingleTargetView(
                        geometry: geometry,
                        direction: targets[responses.count]
                    )
                    .frame(minHeight: 180)
                }

                Text(
                    "Target \(min(responses.count + 1, SequentialOptotypeSession.requiredTargetCount)) "
                        + "of \(SequentialOptotypeSession.requiredTargetCount)"
                )
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(responseSummary)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(SEENATheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                LazyVGrid(columns: [.init(), .init()], spacing: 14) {
                    ForEach(OptotypeDirection.allCases, id: \.self) { direction in
                        Button(direction.rawValue.capitalized) {
                            add(OptotypeResponse(direction))
                        }
                        .buttonStyle(SecondaryActionStyle())
                        .frame(minHeight: 44)
                    }
                }

                Button("I can’t see it / Not visible") {
                    add(.notVisible)
                }
                .buttonStyle(PrimaryActionStyle())
                .frame(minHeight: 52)

                Button("Undo", action: undo)
                    .disabled(responses.isEmpty)

                    Button("Submit operator responses", action: submit)
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(responses.count != SequentialOptotypeSession.requiredTargetCount)
                }
                .padding(24)
            }
            .navigationTitle("Operator fallback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func add(_ response: OptotypeResponse) {
        guard responses.count < SequentialOptotypeSession.requiredTargetCount else { return }
        responses.append(response)
    }

    private func undo() {
        _ = responses.popLast()
    }
}
