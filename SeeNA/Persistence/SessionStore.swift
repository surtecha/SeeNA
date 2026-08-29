import Foundation

private struct SessionEnvelope: Codable {
    let schemaVersion: Int
    var sessions: [ScreeningSession]
}

actor SessionStore {
    private let inMemory: Bool
    private var memorySessions: [ScreeningSession] = []
    private let fileURL: URL?
    private let writeData: @Sendable (Data, URL) throws -> Void

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        writeData = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
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

    init(
        fileURL: URL,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    ) {
        inMemory = false
        self.fileURL = fileURL
        self.writeData = writeData
    }

    func loadSessions() throws -> [ScreeningSession] {
        if inMemory { return memorySessions.sorted { $0.createdAt > $1.createdAt } }
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StoreError.readFailed
        }
        let envelope: SessionEnvelope
        do {
            envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
        } catch {
            throw StoreError.corruptHistory
        }
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
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                throw StoreError.deleteFailed
            }
        }
    }

    private func write(_ sessions: [ScreeningSession]) throws {
        if inMemory {
            memorySessions = sessions
            return
        }
        guard let fileURL else { throw StoreError.storageUnavailable }
        let envelope = SessionEnvelope(schemaVersion: 1, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw StoreError.writeFailed
        }
        do {
            try writeData(data, fileURL)
        } catch {
            throw StoreError.writeFailed
        }
    }

    nonisolated static func allowsDestructiveRecovery(after error: Error) -> Bool {
        guard let storeError = error as? StoreError else { return false }
        return storeError == .corruptHistory || storeError == .unsupportedSchema
    }

    enum StoreError: Error, Equatable {
        case storageUnavailable
        case unsupportedSchema
        case corruptHistory
        case readFailed
        case writeFailed
        case deleteFailed
    }
}
