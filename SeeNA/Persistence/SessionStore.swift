import Foundation

private struct SessionEnvelope: Codable {
    let schemaVersion: Int
    var sessions: [ScreeningSession]
}

actor SessionStore {
    private let inMemory: Bool
    private var memorySessions: [ScreeningSession] = []
    private let fileURL: URL?

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        if inMemory {
            fileURL = nil
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let directory = base?.appendingPathComponent("SEENA", isDirectory: true)
            if let directory {
                try? FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            }
            fileURL = directory?.appendingPathComponent("sessions-v1.json")
        }
    }

    func loadSessions() throws -> [ScreeningSession] {
        if inMemory { return memorySessions.sorted { $0.createdAt > $1.createdAt } }
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        return envelope.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ session: ScreeningSession) throws {
        var sessions = try loadSessions()
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        try write(sessions)
    }

    func delete(sessionID: UUID) throws {
        var sessions = try loadSessions()
        sessions.removeAll { $0.id == sessionID }
        try write(sessions)
    }

    func deleteAll() throws {
        if inMemory {
            memorySessions.removeAll()
            return
        }
        guard let fileURL else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func write(_ sessions: [ScreeningSession]) throws {
        if inMemory {
            memorySessions = sessions
            return
        }
        guard let fileURL else { throw StoreError.unavailable }
        let envelope = SessionEnvelope(schemaVersion: 1, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    enum StoreError: Error {
        case unavailable
        case unsupportedSchema
    }
}
