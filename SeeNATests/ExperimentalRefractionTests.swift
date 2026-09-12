import Foundation
import XCTest
@testable import SEENACore

final class ExperimentalRefractionTests: XCTestCase {
    private func level(_ search: FarPointSearch, passed: Bool, distance: Double? = nil,
                       id: UUID = UUID()) -> FarPointLevel {
        FarPointLevel(id: id, eye: search.eye, repetition: search.repetition,
            requestedDiopter: search.requestedDiopter,
            measuredDistanceMetres: distance ?? search.requestedDistance,
            targets: [.up, .left, .down],
            responses: passed ? [.up, .left, .down] : [.notVisible, .notVisible, .notVisible],
            recordedAt: Date(timeIntervalSince1970: 1_000))
    }

    private func run(thresholds: [Double], eye: Eye = .right) -> FarPointSearch {
        var search = FarPointSearch(eye: eye)
        for _ in 0..<100 where !search.isFinished {
            let threshold = thresholds[min(search.repetition, thresholds.count - 1)]
            XCTAssertTrue(search.submit(level(search, passed: search.requestedDiopter <= threshold)))
        }
        XCTAssertTrue(search.isFinished, "Search must terminate")
        return search
    }

    func testIndependentAnalyticGeometryAndResolutionFloor() throws {
        let points = try XCTUnwrap(FarPointProtocol.targetPoints(distance: 1, millimetresPerPoint: 0.15, displayScale: 3))
        XCTAssertEqual(points, 1.4544412997222254 / 0.15, accuracy: 1e-10)
        XCTAssertNotNil(FarPointProtocol.targetPoints(distance: 0.4, millimetresPerPoint: 0.15, displayScale: 3))
        XCTAssertNil(FarPointProtocol.targetPoints(distance: 0.4, millimetresPerPoint: 0.30, displayScale: 3))
        // A rejected target must not be enlarged into a different measurement.
        XCTAssertNil(FarPointProtocol.targetPoints(distance: 0.399, millimetresPerPoint: 0.15, displayScale: 3))
        XCTAssertNil(FarPointProtocol.targetPoints(distance: 2.001, millimetresPerPoint: 0.15, displayScale: 3))
    }

    func testGeometryRejectsInvalidDomains() {
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(FarPointProtocol.targetPoints(distance: invalid, millimetresPerPoint: 0.15, displayScale: 3))
            XCTAssertNil(FarPointProtocol.targetPoints(distance: 1, millimetresPerPoint: invalid, displayScale: 3))
            XCTAssertNil(FarPointProtocol.targetPoints(distance: 1, millimetresPerPoint: 0.15, displayScale: invalid))
        }
    }

    func testIdealThresholdSweepIsBracketedNotClaimedAsClinicalAccuracy() {
        for index in 51...249 {
            let threshold = -Double(index) / 100
            let search = run(thresholds: [threshold])
            guard case .estimate(let midpoint, let lower, let upper) = search.outcome else {
                XCTFail("Expected a bounded synthetic threshold: \(threshold)"); continue
            }
            XCTAssertLessThanOrEqual(lower, threshold)
            XCTAssertGreaterThanOrEqual(upper, threshold)
            XCTAssertLessThanOrEqual(abs(midpoint - threshold), 0.125 + 1e-9)
            XCTAssertEqual(search.brackets.count, 3)
            for bracket in search.brackets {
                XCTAssertLessThanOrEqual(1 / bracket.passingDistance - 1 / bracket.failingDistance, 0.25 + 1e-9)
            }
        }
    }

    func testBoundarySuccessOrFailureDoesNotInventAnEstimate() {
        XCTAssertEqual(run(thresholds: [-0.1]).outcome, .outsideRange)
        XCTAssertEqual(run(thresholds: [-4]).outcome, .outsideRange)
    }

    func testDisagreeingRepeatsReturnNoNumber() {
        XCTAssertEqual(run(thresholds: [-0.8, -1.8, -2.2]).outcome, .inconsistent)
    }

    func testInverseDistanceBoundsUseCorrectSignsAndExactNonlinearConversion() {
        let bracket = FarPointBracket(passingDistance: 0.5, failingDistance: 0.6)
        XCTAssertEqual(bracket.lowerDiopter, -1 / 0.495, accuracy: 1e-12)
        XCTAssertEqual(bracket.upperDiopter, -1 / 0.605, accuracy: 1e-12)
        XCTAssertLessThan(bracket.lowerDiopter, bracket.midpoint)
        XCTAssertGreaterThan(bracket.upperDiopter, bracket.midpoint)
    }

    func testWrongDistanceAndRepeatedEvidenceAreRejectedWithoutStateMutation() {
        var search = FarPointSearch(eye: .right)
        XCTAssertFalse(search.submit(level(search, passed: false, distance: 1.9)))
        XCTAssertTrue(search.levels.isEmpty)
        let first = level(search, passed: false)
        XCTAssertTrue(search.submit(first))
        XCTAssertFalse(search.submit(first))
        XCTAssertEqual(search.levels.count, 1)
        XCTAssertFalse(search.submit(level(search, passed: false, distance: .nan)))
    }

    func testAllThreeAnswersAreRequiredAndOneWrongAnswerFailsLevel() {
        var search = FarPointSearch(eye: .right)
        let partial = FarPointLevel(id: UUID(), eye: .right, repetition: 0, requestedDiopter: -0.5,
            measuredDistanceMetres: 2, targets: [.up, .left, .down], responses: [.up, .left], recordedAt: Date())
        XCTAssertFalse(search.submit(partial))
        let wrong = FarPointLevel(id: UUID(), eye: .right, repetition: 0, requestedDiopter: -0.5,
            measuredDistanceMetres: 2, targets: [.up, .left, .down], responses: [.up, .left, .right], recordedAt: Date())
        XCTAssertFalse(wrong.passed)
        XCTAssertTrue(search.submit(wrong))
        XCTAssertEqual(search.requestedDiopter, -1)
    }

    func testRecordRecomputesBothEyesAndRejectsTampering() {
        let right = run(thresholds: [-1.2])
        let left = run(thresholds: [-1.8], eye: .left)
        let record = makeRecord(levels: right.levels + left.levels)
        XCTAssertEqual(record.outcome(for: .right), right.outcome)
        XCTAssertEqual(record.outcome(for: .left), left.outcome)
        XCTAssertEqual(makeRecord(levels: right.levels, protocolID: "unknown").outcome(for: .right), .incomplete)
        XCTAssertEqual(makeRecord(levels: right.levels, mmPerPoint: 0.3).outcome(for: .right), .inconsistent)
        XCTAssertEqual(makeRecord(levels: right.levels + right.levels).outcome(for: .right), .inconsistent)
        XCTAssertEqual(makeRecord(levels: Array(right.levels.dropLast())).outcome(for: .right), .incomplete)
    }

    func testHistoryRoundTripKeepsDateAndEvidenceAndUpsertsByID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("seena-refraction-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let store = RefractionStore(fileURL: url)
        let older = makeRecord(date: Date(timeIntervalSince1970: 100), levels: run(thresholds: [-1.2]).levels)
        let newer = makeRecord(date: Date(timeIntervalSince1970: 200), levels: run(thresholds: [-1.8]).levels)
        try await store.save(newer)
        try await store.save(older)
        try await store.save(older)
        let reopened = try await RefractionStore(fileURL: url).load()
        XCTAssertEqual(reopened, [newer, older])
        try await store.delete(older.id)
        let remaining = try await store.load()
        XCTAssertEqual(remaining, [newer])
    }

    func testCorruptHistoryCannotBeOverwrittenOrDeleted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("seena-refraction-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let original = Data("invalid json".utf8)
        try original.write(to: url)
        let store = RefractionStore(fileURL: url)
        do { try await store.save(makeRecord(levels: [])); XCTFail("Must preserve corrupt file") } catch {}
        do { try await store.delete(UUID()); XCTFail("Must preserve corrupt file") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSimulatorFixtureCannotRunOnPhysicalOrReleaseBuild() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("SeeNA/Debug/SimulatorRefractionAutomation.swift"), encoding: .utf8)
        XCTAssertTrue(source.hasPrefix("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(source.contains("-SEENA_AUTOMATE_REFRACTION"))
        XCTAssertTrue(source.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("#endif"))
    }

    func testPreviewHistoryDoesNotTouchDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("never-write-\(UUID()).json")
        let store = RefractionStore(fileURL: url, inMemory: true)
        let record = makeRecord(levels: [])
        try await store.save(record)
        let records = try await store.load()
        XCTAssertEqual(records, [record])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeRecord(date: Date = Date(timeIntervalSince1970: 1_000), levels: [FarPointLevel],
                            protocolID: String = FarPointProtocol.identifier, mmPerPoint: Double = 0.15) -> RefractionRecord {
        RefractionRecord(id: UUID(), createdAt: date, protocolIdentifier: protocolID,
            millimetresPerPoint: mmPerPoint, displayScale: 3, levels: levels)
    }
}
