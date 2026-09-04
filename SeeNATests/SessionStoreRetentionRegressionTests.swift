import Foundation
import XCTest
@testable import SEENACore

final class SessionStoreRetentionRegressionTests: XCTestCase {
    private struct StoredEnvelope: Codable {
        let schemaVersion: Int
        let sessions: [ScreeningSession]
    }

    func testSaveRetainsOnlyNewestSessions() async throws {
        let store = SessionStore(inMemory: true)
        let origin = Date(timeIntervalSince1970: 2_000_000_000)

        for offset in 0..<(SessionStore.maximumRetainedSessions + 7) {
            try await store.save(
                ScreeningSession(
                    id: UUID(),
                    createdAt: origin.addingTimeInterval(Double(offset))
                )
            )
        }

        let sessions = try await store.loadSessions()
        XCTAssertEqual(sessions.count, SessionStore.maximumRetainedSessions)
        XCTAssertEqual(sessions.first?.createdAt, origin.addingTimeInterval(56))
        XCTAssertEqual(sessions.last?.createdAt, origin.addingTimeInterval(7))
    }

    func testEqualTimestampsUseStableIdentifierOrdering() async throws {
        let store = SessionStore(inMemory: true)
        let timestamp = Date(timeIntervalSince1970: 2_000_000_000)
        let ids = [
            UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        ]

        for id in ids {
            try await store.save(ScreeningSession(id: id, createdAt: timestamp))
        }

        let firstLoad = try await store.loadSessions().map(\.id)
        let secondLoad = try await store.loadSessions().map(\.id)
        XCTAssertEqual(firstLoad, ids.sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(secondLoad, firstLoad)
    }

    func testLoadingLegacyOversizedHistoryCompactsTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-compaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sessions.json")
        let origin = Date(timeIntervalSince1970: 2_000_000_000)
        let oversized = (0..<(SessionStore.maximumRetainedSessions + 5)).map { offset in
            ScreeningSession(
                id: UUID(),
                createdAt: origin.addingTimeInterval(Double(offset))
            )
        }
        try JSONEncoder().encode(
            StoredEnvelope(schemaVersion: 1, sessions: oversized.reversed())
        ).write(to: fileURL)

        let store = SessionStore(fileURL: fileURL) { data, url in
            try data.write(to: url, options: .atomic)
        }
        let loaded = try await store.loadSessions()
        let persisted = try JSONDecoder().decode(
            StoredEnvelope.self,
            from: Data(contentsOf: fileURL)
        ).sessions

        XCTAssertEqual(loaded.count, SessionStore.maximumRetainedSessions)
        XCTAssertEqual(persisted, loaded)
        XCTAssertEqual(loaded.first?.createdAt, origin.addingTimeInterval(54))
        XCTAssertEqual(loaded.last?.createdAt, origin.addingTimeInterval(5))
    }

    func testCorruptHistoryIsNeverOverwrittenBySave() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sessions.json")
        let originalBytes = Data("not valid session history".utf8)
        try originalBytes.write(to: fileURL)

        let store = SessionStore(fileURL: fileURL)
        do {
            try await store.save(ScreeningSession())
            XCTFail("Expected corrupt history to block the save")
        } catch {
            XCTAssertEqual(error as? SessionStore.StoreError, .corruptHistory)
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), originalBytes)
    }

    func testSaveLoadRoundTripRedactsUnauthorizedResultsButPreservesTrialAuditEvidence() async throws {
        let store = SessionStore(inMemory: true)
        var session = ScreeningSession()
        session.numericResultsAllowed = true
        session.rightEyeResult = injectedNumericResult(
            eye: .right,
            status: .experimentalThresholdObserved
        )
        session.leftEyeResult = injectedNumericResult(
            eye: .left,
            status: .validEstimate
        )
        let auditTrial = trialAuditEvidence()
        session.rightEyeTrials = [auditTrial]

        try await store.save(session)
        let sessions = try await store.loadSessions()
        let loaded = try XCTUnwrap(sessions.first)

        XCTAssertEqual(loaded.numericResultsAllowed, false)
        XCTAssertEqual(loaded.rightEyeResult?.status, .experimentalThresholdObserved)
        XCTAssertEqual(loaded.leftEyeResult?.status, .experimentalThresholdObserved)
        assertNoNumericPayload(try XCTUnwrap(loaded.rightEyeResult))
        assertNoNumericPayload(try XCTUnwrap(loaded.leftEyeResult))
        XCTAssertEqual(loaded.rightEyeTrials, [auditTrial])
        XCTAssertEqual(loaded.rightEyeTrials.first?.candidateDiopter, -1.25)
        XCTAssertEqual(loaded.rightEyeTrials.first?.actualMedianDistanceMetres, 0.81)
    }

    func testLoadingTamperedDiskHistoryRedactsAndRewritesEveryStatusPayload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-redaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sessions.json")

        var tampered = ScreeningSession()
        tampered.numericResultsAllowed = true
        tampered.rightEyeResult = injectedNumericResult(
            eye: .right,
            status: .unreliableMeasurement
        )
        tampered.leftEyeResult = injectedNumericResult(
            eye: .left,
            status: .deviceUnsupported
        )
        try JSONEncoder().encode(
            StoredEnvelope(schemaVersion: 1, sessions: [tampered])
        ).write(to: fileURL)

        let store = SessionStore(fileURL: fileURL) { data, url in
            try data.write(to: url, options: .atomic)
        }
        let sessions = try await store.loadSessions()
        let loaded = try XCTUnwrap(sessions.first)
        let rewritten = try XCTUnwrap(
            JSONDecoder().decode(
                StoredEnvelope.self,
                from: Data(contentsOf: fileURL)
            ).sessions.first
        )

        for session in [loaded, rewritten] {
            XCTAssertEqual(session.numericResultsAllowed, false)
            XCTAssertEqual(session.rightEyeResult?.status, .unreliableMeasurement)
            XCTAssertEqual(session.leftEyeResult?.status, .deviceUnsupported)
            assertNoNumericPayload(try XCTUnwrap(session.rightEyeResult))
            assertNoNumericPayload(try XCTUnwrap(session.leftEyeResult))
        }
    }

    func testLegacyHistoryWithoutEligibilityFlagLoadsFailClosed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-legacy-redaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sessions.json")

        var legacy = ScreeningSession()
        legacy.numericResultsAllowed = nil
        legacy.rightEyeResult = injectedNumericResult(
            eye: .right,
            status: .experimentalFarthestTargetPassed
        )
        try JSONEncoder().encode(
            StoredEnvelope(schemaVersion: 1, sessions: [legacy])
        ).write(to: fileURL)

        let store = SessionStore(fileURL: fileURL) { data, url in
            try data.write(to: url, options: .atomic)
        }
        let sessions = try await store.loadSessions()
        let loaded = try XCTUnwrap(sessions.first)

        XCTAssertEqual(loaded.numericResultsAllowed, false)
        XCTAssertEqual(loaded.rightEyeResult?.status, .experimentalFarthestTargetPassed)
        assertNoNumericPayload(try XCTUnwrap(loaded.rightEyeResult))
    }

    private func injectedNumericResult(
        eye: Eye,
        status: ScreeningStatus
    ) -> EyeScreeningResult {
        EyeScreeningResult(
            eye: eye,
            status: status,
            lastFailDiopter: -1.0,
            firstPassDiopter: -1.25,
            displayedEstimateDiopter: -1.25,
            thresholdDistanceMetres: 0.8,
            sensorUncertaintyDiopter: 0.02,
            repeatabilityDiopter: 0.03,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: [],
            recommendedAction: .routineExamRecommended
        )
    }

    private func trialAuditEvidence() -> TrialBlock {
        let targets: [OptotypeDirection] = [
            .up, .right, .down, .left, .up, .right, .down, .left
        ]
        return TrialBlock(
            eye: .right,
            candidateDiopter: -1.25,
            targetDistanceMetres: 0.8,
            actualMedianDistanceMetres: 0.81,
            distanceStandardDeviation: 0.01,
            targets: targets,
            responses: targets,
            correctCount: SequentialOptotypeSession.requiredTargetCount,
            outcome: .pass,
            quality: BlockQuality(
                trackingCoverage: 0.98,
                phoneStable: true,
                headPoseValid: true,
                distanceStable: true,
                audioLevelAdequate: true,
                targetGeometryValid: true,
                gazeCoverage: 0.98,
                discardReasons: []
            ),
            responseSource: .voice,
            transcript: nil
        )
    }

    private func assertNoNumericPayload(
        _ result: EyeScreeningResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(result.lastFailDiopter, file: file, line: line)
        XCTAssertNil(result.firstPassDiopter, file: file, line: line)
        XCTAssertNil(result.displayedEstimateDiopter, file: file, line: line)
        XCTAssertNil(result.thresholdDistanceMetres, file: file, line: line)
        XCTAssertNil(result.sensorUncertaintyDiopter, file: file, line: line)
        XCTAssertNil(result.repeatabilityDiopter, file: file, line: line)
    }
}
