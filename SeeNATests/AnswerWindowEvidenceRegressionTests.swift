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

    func testOverflowPreservesPrefixAndResetsOnlyExplicitly() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        for index in 0...AnswerWindowSensorEvidenceBuffer.maximumRetainedSampleCount {
            buffer.record(sample(timestamp: Double(index)))
        }
        XCTAssertTrue(buffer.didExceedCapacity)
        XCTAssertEqual(buffer.samples.count, AnswerWindowSensorEvidenceBuffer.maximumRetainedSampleCount)
        XCTAssertEqual(buffer.samples.first?.timestamp, Date(timeIntervalSinceReferenceDate: 0))
        buffer.discardPendingWindow()
        XCTAssertTrue(buffer.didExceedCapacity)
        buffer.reset(releasingCapacity: true)
        XCTAssertTrue(buffer.samples.isEmpty)
        XCTAssertFalse(buffer.didExceedCapacity)
    }

    func testGoodAnswersCannotConcealOneBadAnswerAndRetryCanRecover() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        for index in 0..<7 {
            capture(into: &buffer, start: Double(index) * 2, distance: 0.4)
            XCTAssertTrue(accept(&buffer))
        }
        let acceptedCount = buffer.samples.count
        capture(into: &buffer, start: 14, distance: 0.6)
        XCTAssertFalse(accept(&buffer))
        XCTAssertEqual(buffer.samples.count, acceptedCount)
        capture(into: &buffer, start: 16, distance: 0.4)
        XCTAssertTrue(accept(&buffer))
        XCTAssertEqual(buffer.samples.count, acceptedCount + 20)
    }

    func testUnacceptedAttemptDoesNotPoisonNextAttempt() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        capture(into: &buffer, start: 0, distance: 0.6)
        // A failed transcription leaves the attempt unaccepted.
        capture(into: &buffer, start: 2, distance: 0.4)
        XCTAssertTrue(accept(&buffer))
        XCTAssertEqual(buffer.samples.count, 20)
    }

    func testFrozenOrInterruptedSensorStreamCannotPassAWindow() {
        for gapLocation in [0, 1, 2] {
            var buffer = AnswerWindowSensorEvidenceBuffer()
            buffer.beginWindow(at: Date(timeIntervalSinceReferenceDate: 0))
            for index in 0..<20 {
                let gap = gapLocation == 0 || (gapLocation == 1 && index >= 10) ? 2.0 : 0
                buffer.record(sample(timestamp: Double(index) / 20 + gap))
            }
            buffer.endWindow(at: Date(timeIntervalSinceReferenceDate: 3))
            XCTAssertFalse(accept(&buffer), "gap location \(gapLocation)")
            XCTAssertTrue(buffer.samples.isEmpty)
        }
    }

    func testMissingWindowAndEmptyEvidenceFailClosed() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        XCTAssertFalse(accept(&buffer))
        buffer.beginWindow(at: Date(timeIntervalSinceReferenceDate: 0))
        buffer.endWindow(at: Date(timeIntervalSinceReferenceDate: 1))
        XCTAssertFalse(accept(&buffer))
    }

    func testRepeatedFramesCannotPretendToBeIndependentSamples() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        buffer.beginWindow(at: Date(timeIntervalSinceReferenceDate: 0))
        for _ in 0..<20 { buffer.record(sample(timestamp: 0.2)) }
        buffer.endWindow(at: Date(timeIntervalSinceReferenceDate: 0.4))
        XCTAssertFalse(accept(&buffer))
        XCTAssertTrue(buffer.samples.isEmpty)
    }

    func testTimerAndPublisherCanObserveTheSameFreshFrameWithoutRejectingAnswer() {
        var buffer = AnswerWindowSensorEvidenceBuffer()
        buffer.beginWindow(at: Date(timeIntervalSinceReferenceDate: 0))
        for index in 0..<20 {
            let frame = sample(timestamp: Double(index) / 20)
            buffer.record(frame)
            buffer.record(frame)
        }
        buffer.endWindow(at: Date(timeIntervalSinceReferenceDate: 1))
        XCTAssertTrue(accept(&buffer))
        XCTAssertEqual(buffer.samples.count, 20)
    }

    func testNonFiniteSensorEvidenceCannotPassQuality() {
        for invalid in [Double.nan, .infinity, -.infinity] {
            let samples = (0..<20).map { sample(timestamp: Double($0) / 20, trackingCoverage: invalid) }
            let result = BlockMeasurementQualityEngine.evaluate(
                samples: samples, targetDistanceMetres: 0.4,
                targetToleranceMetres: 0.04, thresholds: .conservative
            )
            XCTAssertFalse(result.isAccepted)
            XCTAssertTrue(result.issues.contains(.invalidEvidence))
            XCTAssertTrue(result.trackingCoverage.isFinite)
        }
    }

    func testNonFiniteToleranceCannotDisableDistanceGate() {
        let result = BlockMeasurementQualityEngine.evaluate(
            samples: (0..<20).map { sample(timestamp: Double($0) / 20) },
            targetDistanceMetres: 0.4, targetToleranceMetres: .infinity,
            thresholds: .conservative
        )
        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.issues.contains(.invalidEvidence))
    }

    private func capture(into buffer: inout AnswerWindowSensorEvidenceBuffer, start: Double, distance: Double) {
        buffer.beginWindow(at: Date(timeIntervalSinceReferenceDate: start))
        for index in 0..<20 {
            buffer.record(sample(timestamp: start + Double(index) / 20, distance: distance))
        }
        buffer.endWindow(at: Date(timeIntervalSinceReferenceDate: start + 1))
    }

    private func accept(_ buffer: inout AnswerWindowSensorEvidenceBuffer) -> Bool {
        buffer.acceptWindow(targetDistanceMetres: 0.4, targetToleranceMetres: 0.04, thresholds: .conservative)
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

}
