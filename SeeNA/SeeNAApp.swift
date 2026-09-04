//
//  SeeNAApp.swift
//  SeeNA
//
//  Created by Suryateja Challa on 29/8/2026.
//

import SwiftUI

@main
struct SeeNAApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSession()
    @StateObject private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(dependencies)
                .task {
                    dependencies.brightness.restoreIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    handleScenePhase(phase)
                }
        }
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard let resumePlan = session.consumeSceneResumePlan() else { return }
            if resumePlan.resumesLiveSensors {
                dependencies.sensorCoordinator.start()
            }
            if resumePlan.restoresScreeningBrightness {
                dependencies.brightness.applyScreeningBrightness()
            }
        case .inactive, .background:
            guard session.beginSceneSuspension() else { return }
            suspendLiveResources()
        @unknown default:
            guard session.beginSceneSuspension() else { return }
            suspendLiveResources()
        }
    }

    @MainActor
    private func suspendLiveResources() {
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        dependencies.sensorCoordinator.suspend()
        // Sensor invalidation is delivered synchronously to the active
        // screen. Some screens reset their state by asking for guidance,
        // so stop the audio channel again after that callback has run.
        dependencies.audioRecorder.stop()
        dependencies.spokenPrompts.stop()
        dependencies.brightness.restore()
    }
}
