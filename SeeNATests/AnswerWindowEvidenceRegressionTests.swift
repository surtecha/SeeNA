import Foundation
import XCTest
@testable import SEENACore

final class AnswerWindowEvidenceRegressionTests: XCTestCase {
    func testEarlyInvalidEvidenceStillRejectsAfterMoreThanOldRollingWindowOfCleanFrames() {
        let earlyInvalid = (0..<40).map { index in
            sample(
                timestamp: TimeInterval(index) / 60,
                distance: 0.55,
                trackingCoverage: 0,
                phoneStable: false,
                attitudeDriftDegrees: 3,
                accelerationRMS: 0.05,
                headYawDegrees: 25,
                luminance: 0.05,
                faceCount: 2
            )
        }
        let laterClean = (40..<340).map { index in
            sample(timestamp: TimeInterval(index) / 60)
        }
        let completeAnswerWindowEvidence = earlyInvalid + laterClean

        let completeQuality = BlockMeasurementQualityEngine.evaluate(
            samples: completeAnswerWindowEvidence,
            targetDistanceMetres: 0.40,
            targetToleranceMetres: 0.04,
            thresholds: .conservative
        )
        let oldRollingTailQuality = BlockMeasurementQualityEngine.evaluate(
            samples: Array(completeAnswerWindowEvidence.suffix(280)),
            targetDistanceMetres: 0.40,
            targetToleranceMetres: 0.04,
            thresholds: .conservative
        )

        XCTAssertTrue(oldRollingTailQuality.isAccepted)
        XCTAssertFalse(completeQuality.isAccepted)
        XCTAssertTrue(completeQuality.issues.contains(.distanceOffTarget))
        XCTAssertTrue(completeQuality.issues.contains(.trackingUnreliable))
        XCTAssertTrue(completeQuality.issues.contains(.phoneMoved))
        XCTAssertTrue(completeQuality.issues.contains(.headPose))
        XCTAssertTrue(completeQuality.issues.contains(.poorLighting))
        XCTAssertTrue(completeQuality.issues.contains(.multipleFaces))
    }

    func testBothTasksUseBoundedPrefixPreservingEvidenceAndFailClosedOnOverflow() throws {
        let landolt = try source(named: "SeeNA/Features/EyeTest/EyeTestViewModel.swift")
        let gabor = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")

        XCTAssertTrue(landolt.contains("static let maximumRetainedSampleCount = 16_384"))
        XCTAssertTrue(landolt.contains("guard samples.count < Self.maximumRetainedSampleCount else"))
        XCTAssertTrue(landolt.contains("didExceedCapacity = true"))
        XCTAssertFalse(landolt.contains("blockSamples.removeFirst"))
        XCTAssertFalse(gabor.contains("blockSamples.removeFirst"))

        for model in [landolt, gabor] {
            XCTAssertTrue(model.contains("blockEvidence.record(sample)"))
            XCTAssertTrue(model.contains("samples: blockEvidence.samples"))
            XCTAssertTrue(model.contains("blockEvidence.didExceedCapacity"))
            XCTAssertTrue(model.contains("blockEvidence.reset(releasingCapacity: true)"))
        }
    }

    private func sample(
        timestamp: TimeInterval,
        distance: Double = 0.40,
        trackingCoverage: Double = 1,
        phoneStable: Bool = true,
        attitudeDriftDegrees: Double = 0.1,
        accelerationRMS: Double = 0.001,
        headYawDegrees: Double = 0,
        luminance: Double = 0.8,
        faceCount: Int = 1
    ) -> DistanceSample {
        DistanceSample(
            timestamp: Date(timeIntervalSinceReferenceDate: timestamp),
            rawARDistanceMetres: distance,
            relativeScaleDistanceMetres: distance,
            fusedDistanceMetres: distance,
            correctedDistanceMetres: distance,
            distanceStandardDeviation: 0.001,
            trackingCoverage: trackingCoverage,
            phoneStable: phoneStable,
            attitudeDriftDegrees: attitudeDriftDegrees,
            accelerationRMS: accelerationRMS,
            headYawDegrees: headYawDegrees,
            headPitchDegrees: 0,
            gazeYawErrorDegrees: 0,
            gazePitchErrorDegrees: 0,
            luminance: luminance,
            faceCount: faceCount,
            interEyePixels: 120
        )
    }

    private func source(named path: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
