import Foundation

actor RefractionStore {
    private struct Envelope: Codable { let version: Int; let records: [RefractionRecord] }
    private let fileURL: URL
    private var memoryRecords: [RefractionRecord]?
    init(fileURL: URL? = nil, inMemory: Bool = false) {
        memoryRecords = inMemory ? [] : nil
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SEENA/refraction-v1.json")
    }
    func load() throws -> [RefractionRecord] {
        if let memoryRecords { return memoryRecords }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.version == 1 else { throw SessionStore.StoreError.unsupportedSchema }
        return envelope.records.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
    }
    func save(_ record: RefractionRecord) throws {
        var records = try load() // Never overwrite unreadable history.
        records.removeAll { $0.id == record.id }
        records.append(record)
        try write(records)
    }
    func delete(_ id: UUID) throws { try write(load().filter { $0.id != id }) }
    private func write(_ records: [RefractionRecord]) throws {
        let sorted = records.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        if memoryRecords != nil { memoryRecords = sorted; return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let data = try JSONEncoder().encode(Envelope(version: 1, records: sorted))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
