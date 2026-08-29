import Foundation
import XCTest
@testable import SEENACore

final class SessionStoreFailureTests: XCTestCase {
    func testOnlyProvenCorruptOrUnsupportedHistoryAllowsDestructiveRecovery() {
        XCTAssertTrue(SessionStore.allowsDestructiveRecovery(after: SessionStore.StoreError.corruptHistory))
        XCTAssertTrue(SessionStore.allowsDestructiveRecovery(after: SessionStore.StoreError.unsupportedSchema))
        XCTAssertFalse(SessionStore.allowsDestructiveRecovery(after: SessionStore.StoreError.readFailed))
        XCTAssertFalse(SessionStore.allowsDestructiveRecovery(after: SessionStore.StoreError.writeFailed))
        XCTAssertFalse(SessionStore.allowsDestructiveRecovery(after: SessionStore.StoreError.storageUnavailable))
    }

    func testWriteFailurePreservesValidHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sessions.json")

        let validStore = SessionStore(fileURL: fileURL) { data, url in
            try data.write(to: url, options: .atomic)
        }
        let original = ScreeningSession()
        try await validStore.save(original)

        let failingStore = SessionStore(fileURL: fileURL) { _, _ in
            throw SessionStore.StoreError.writeFailed
        }
        do {
            try await failingStore.save(ScreeningSession())
            XCTFail("Expected a write failure")
        } catch {
            XCTAssertEqual(error as? SessionStore.StoreError, .writeFailed)
        }

        let retained = try await validStore.loadSessions()
        XCTAssertEqual(retained.map(\.id), [original.id])
    }
}
