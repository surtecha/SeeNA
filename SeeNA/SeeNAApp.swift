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
            if session.requiresLiveSensors { dependencies.sensorCoordinator.start() }
            if session.requiresScreeningBrightness { dependencies.brightness.applyScreeningBrightness() }
        case .inactive:
            dependencies.audioRecorder.stop()
            dependencies.sensorCoordinator.stop()
            dependencies.brightness.restore()
        case .background:
            dependencies.audioRecorder.stop()
            dependencies.spokenPrompts.stop()
            dependencies.sensorCoordinator.stop()
            dependencies.brightness.restore()
        @unknown default:
            dependencies.brightness.restore()
        }
    }
}
