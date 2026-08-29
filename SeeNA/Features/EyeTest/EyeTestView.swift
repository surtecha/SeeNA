import SwiftUI

struct EyeTestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model: EyeTestViewModel
    @State private var operatorResponses: [OptotypeDirection] = []

    private var geometry: OptotypeGeometry? {
        guard let profile = session.activeSession.deviceProfile else { return nil }
        return OptotypeGeometry.calculate(
            distanceMetres: model.presentationDistance,
            pixelsPerInch: profile.pixelsPerInch,
            displayScale: profile.displayScale,
            // Only the standard angular target is scored. The large locator
            // rendered by the stage view is deliberately non-directional.
            presentationMode: .clinicalFiveArcMinute
        )
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(model.isRunningBlock)
        .onAppear(perform: beginTest)
        .onReceive(dependencies.sensorCoordinator.$latestSample, perform: observe)
        .overlay(alignment: .topLeading) {
            operatorEntryGesture
        }
        .sheet(
            isPresented: $model.showingOperatorInput,
            onDismiss: operatorInputDidDismiss
        ) {
            OperatorInputView(responses: $operatorResponses, submit: submitOperatorResponses)
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
        model.begin(using: dependencies)
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
    @Binding var responses: [OptotypeDirection]
    let submit: () -> Void

    private var responseSummary: String {
        responses.map { $0.rawValue.prefix(1).uppercased() }.joined(separator: "  ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter seven directions")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(responseSummary)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(SEENATheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                LazyVGrid(columns: [.init(), .init()], spacing: 14) {
                    ForEach(OptotypeDirection.allCases, id: \.self) { direction in
                        Button(direction.rawValue.capitalized) {
                            add(direction)
                        }
                        .buttonStyle(SecondaryActionStyle())
                    }
                }

                Button("Undo", action: undo)
                    .disabled(responses.isEmpty)

                Spacer()

                Button("Submit operator responses", action: submit)
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(responses.count != 7)
            }
            .padding(24)
            .navigationTitle("Operator fallback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func add(_ direction: OptotypeDirection) {
        guard responses.count < 7 else { return }
        responses.append(direction)
    }

    private func undo() {
        _ = responses.popLast()
    }
}
