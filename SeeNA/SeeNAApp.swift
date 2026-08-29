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
                    await restoreHistory()
                }
                .onChange(of: scenePhase) { phase in
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
        case .inactive, .background:
            dependencies.audioRecorder.stop()
            dependencies.spokenPrompts.stop()
            dependencies.sensorCoordinator.stop()
            dependencies.brightness.restore()
        @unknown default:
            dependencies.brightness.restore()
        }
    }

    @MainActor
    private func restoreHistory() async {
        session.isRestoringHistory = true
        defer { session.isRestoringHistory = false }
        do {
            _ = try await dependencies.sessionStore.loadSessions()
        } catch {
            session.appError = .persistenceFailed
        }
    }
}
