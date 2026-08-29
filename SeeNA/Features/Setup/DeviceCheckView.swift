import AVFoundation
import SwiftUI

struct DeviceCheckView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model: DeviceCheckViewModel
    init(model: DeviceCheckViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScreenScaffold(
            title: model.heading,
            subtitle: "Checking what SeeNA needs for your screening."
        ) {
            StatusRow(
                title: "Camera",
                detail: faceTrackingReady ? "Ready" : "Unavailable",
                state: faceTrackingReady ? .ready : .unavailable
            )
            StatusRow(
                title: "Face tracking",
                detail: faceTrackingReady ? "Ready" : "Unavailable",
                state: faceTrackingReady ? .ready : .unavailable
            )
            StatusRow(
                title: "Motion sensors",
                detail: motionReady ? "Ready" : "Unavailable",
                state: motionReady ? .ready : .unavailable
            )
            StatusRow(
                title: "Voice responses",
                detail: model.microphoneDetail,
                state: model.microphoneGranted ? .ready : .warning
            )
            StatusRow(
                title: "Voice service",
                detail: model.networkDetail,
                state: model.networkConnected ? .ready : .warning
            )

            Text(model.outcomeText)
                .font(.body.weight(.semibold))
                .foregroundColor(SEENATheme.secondaryInk)
                .padding(18)
                .background(SEENATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if model.canContinue {
                Button(model.continueTitle) {
                    model.continueJourney(session: session)
                }
                .buttonStyle(PrimaryActionStyle())
            } else {
                Button(model.continueTitle) {
                    dependencies.resetForNewScreening()
                    session.startNewSession()
                }
                .buttonStyle(SecondaryActionStyle())
            }
        }
        .task {
            await model.begin(session: session)
        }
        .onDisappear { model.cancel() }
        .onReceive(dependencies.network.$isConnected) { _ in model.refreshRuntimeRows() }
        .onReceive(dependencies.network.$usesExpensiveInterface) { _ in model.refreshRuntimeRows() }
        .navigationTitle("Compatibility")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    private var faceTrackingReady: Bool {
        model.faceTrackingReady
    }

    private var motionReady: Bool {
        model.motionReady
    }

}
