import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var sessions: [ScreeningSession] = []
    @State private var isLoading = true

    var body: some View {
        ScreenScaffold(
            title: "Local session history",
            subtitle: "Stored only on this iPhone with complete file protection. No account or cloud database is used."
        ) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            } else if sessions.isEmpty {
                StatusRow(title: "No saved sessions", detail: "Completed sessions will appear here.", state: .warning)
            } else {
                ForEach(sessions) { saved in
                    Button {
                        session.activeSession = saved
                        session.accessibilityProfile = saved.accessibilityProfile
                        session.cachedExplanation = nil
                        session.navigate(to: .processing)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(saved.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text(summary(saved)).font(.subheadline).foregroundColor(SEENATheme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(18)
                        .background(SEENATheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                Button("Delete all local history", role: .destructive) {
                    Task {
                        try? await dependencies.sessionStore.deleteAll()
                        sessions = []
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .task { await load() }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        sessions = (try? await dependencies.sessionStore.loadSessions()) ?? []
        isLoading = false
    }

    private func summary(_ value: ScreeningSession) -> String {
        let eyeCount = [value.rightEyeResult, value.leftEyeResult].compactMap { $0 }.count
        return eyeCount > 0 ? "\(eyeCount) eye result(s) and accessibility profile" : "Accessibility profile only"
    }
}

struct DeletionView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var deleted = false

    var body: some View {
        ScreenScaffold(
            title: deleted ? "Session deleted" : "Delete this session?",
            subtitle: deleted ? "The local trial history and result are no longer stored." : "This removes the current session from local storage. It cannot be undone."
        ) {
            if deleted {
                StatusRow(title: "Local data removed", detail: "No raw face video or images were ever stored.", state: .ready)
                Button("Return home") { session.startNewSession() }.buttonStyle(PrimaryActionStyle())
            } else {
                Button("Delete local session", role: .destructive) {
                    Task {
                        do {
                            try await dependencies.sessionStore.delete(sessionID: session.activeSession.id)
                            session.cachedExplanation = nil
                            session.cachedAdaptedContent = nil
                            deleted = true
                        } catch {
                            session.appError = .persistenceFailed
                        }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                Button("Keep session") { session.goBack() }.buttonStyle(SecondaryActionStyle())
            }
        }
        .navigationTitle("Delete")
        .navigationBarTitleDisplayMode(.inline)
    }
}
