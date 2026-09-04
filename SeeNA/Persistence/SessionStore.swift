import Foundation

private struct SessionEnvelope: Codable {
    let schemaVersion: Int
    var sessions: [ScreeningSession]
}

actor SessionStore {
    nonisolated static let maximumRetainedSessions = 50

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
        if inMemory { return Self.normalized(memorySessions) }
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
        let normalizedSessions = Self.normalized(envelope.sessions)
        if normalizedSessions != envelope.sessions {
            // Enforce retention for histories created by older builds too,
            // rather than waiting indefinitely for another completed session.
            // The injected writer and `.atomic` production write preserve the
            // original file if compaction cannot complete.
            try write(normalizedSessions)
        }
        return normalizedSessions
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
        let normalizedSessions = Self.normalized(sessions)
        if inMemory {
            memorySessions = normalizedSessions
            return
        }
        guard let fileURL else { throw StoreError.storageUnavailable }
        let envelope = SessionEnvelope(schemaVersion: 1, sessions: normalizedSessions)
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

    /// Newest-first order is stable even when two sessions have the same
    /// timestamp. A deterministic UUID tie-breaker keeps history presentation,
    /// retention and encoded output reproducible across launches.
    private nonisolated static func normalized(
        _ sessions: [ScreeningSession]
    ) -> [ScreeningSession] {
        let sanitized = sessions.map(sanitizedForStorage)
        return Array(
            sanitized.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(maximumRetainedSessions)
        )
    }

    /// Persistence is a trust boundary. A stale or tampered session-level flag
    /// cannot keep result-level numeric measurements alive when the active
    /// protocol release is not source-approved. Per-trial candidate and sensor
    /// distances remain intact as auditable task evidence.
    private nonisolated static func sanitizedForStorage(
        _ session: ScreeningSession
    ) -> ScreeningSession {
        var sanitized = session
        let numericReleaseAuthorized = session.numericResultsAllowed == true &&
            NumericResultEligibility.protocolReleaseIsApproved(.activePhoneLocator)
        sanitized.numericResultsAllowed = numericReleaseAuthorized
        if let right = sanitized.rightEyeResult {
            sanitized.rightEyeResult = NumericResultEligibility.sanitize(
                right,
                numericResultsAllowed: numericReleaseAuthorized,
                protocolDescriptor: .activePhoneLocator
            )
        }
        if let left = sanitized.leftEyeResult {
            sanitized.leftEyeResult = NumericResultEligibility.sanitize(
                left,
                numericResultsAllowed: numericReleaseAuthorized,
                protocolDescriptor: .activePhoneLocator
            )
        }
        return sanitized
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
