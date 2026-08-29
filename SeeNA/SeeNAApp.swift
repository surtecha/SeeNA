//
//  SeeNAApp.swift
//  SeeNA
//
//  Created by Suryateja Challa on 29/8/2026.
//

import SwiftUI

@main
struct SeeNAApp: App {
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
