import Foundation
import XCTest
@testable import SEENACore

final class SensorReadinessRobustnessTests: XCTestCase {
    func testDistanceFilterPreservesHistoryAcrossBriefInvalidFrames() throws {
        var filter = RobustDistanceFilter(windowSize: 7, maximumConsecutiveDropouts: 3)
        for value in [1.98, 2.00, 2.01, 1.99, 2.02] {
            _ = filter.update(value)
        }

        XCTAssertNil(filter.update(nil))
        XCTAssertNil(filter.update(.infinity))
        XCTAssertNil(filter.update(8.0))

        let recovered = try XCTUnwrap(filter.update(2.01))
        XCTAssertEqual(recovered, 2.005, accuracy: 0.015)
    }

    func testDistanceFilterDropsStaleHistoryAfterSustainedLoss() throws {
        var filter = RobustDistanceFilter(windowSize: 7, maximumConsecutiveDropouts: 2)
        for value in [1.98, 2.00, 2.02, 2.01, 1.99] {
            _ = filter.update(value)
        }

        XCTAssertNil(filter.update(nil))
        XCTAssertNil(filter.update(nil))
        XCTAssertNil(filter.update(nil))

        let recovered = try XCTUnwrap(filter.update(1.50))
        XCTAssertEqual(recovered, 1.50, accuracy: 0.000_001)
    }

    func testTargetLockFreezesProgressThroughBriefTrackingDropout() {
        var tracker = DistanceTargetTracker(dropoutGrace: 0.45)
        var state = tracker.update(
            distance: 2.00,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0
        )
        state = tracker.update(
            distance: 2.02,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.20
        )
        let progressBeforeDropout = state.progress

        state = tracker.update(
            distance: nil,
            target: 2.00,
            conditionsReady: false,
            timestamp: 0.30
        )
        XCTAssertTrue(state.isInTargetZone)
        XCTAssertEqual(state.progress, progressBeforeDropout, accuracy: 0.000_001)

        state = tracker.update(
            distance: 2.04,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.50
        )
        XCTAssertTrue(state.isInTargetZone)
        XCTAssertFalse(state.isReady)

        state = tracker.update(
            distance: 1.98,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.70
        )
        XCTAssertTrue(state.isReady)
    }

    func testTargetLockSurvivesBoundaryJitterButRejectsSustainedViolation() {
        var tracker = DistanceTargetTracker(dropoutGrace: 0.45)
        _ = tracker.update(distance: 2.00, target: 2.00, conditionsReady: true, timestamp: 0)
        _ = tracker.update(distance: 2.04, target: 2.00, conditionsReady: true, timestamp: 0.20)

        var state = tracker.update(
            distance: 2.11,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.30
        )
        XCTAssertTrue(state.isInTargetZone)

        state = tracker.update(
            distance: 2.03,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.43
        )
        XCTAssertTrue(state.isInTargetZone)

        state = tracker.update(
            distance: 2.20,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.50
        )
        XCTAssertTrue(state.isInTargetZone)
        state = tracker.update(
            distance: 2.03,
            target: 2.00,
            conditionsReady: true,
            timestamp: 0.96
        )
        XCTAssertEqual(state, .idle)
    }

    func testLiveGazeTreatsMissingAndBoundaryNoiseAsAdvisory() {
        var tracker = GazeReadinessTracker()

        XCTAssertEqual(
            tracker.update(yawErrorDegrees: nil, pitchErrorDegrees: nil),
            .unavailable
        )
        XCTAssertEqual(
            tracker.update(yawErrorDegrees: nil, pitchErrorDegrees: nil),
            .aligned,
            "Unavailable gaze must not permanently block otherwise safe setup"
        )
        XCTAssertEqual(
            tracker.update(yawErrorDegrees: 7.5, pitchErrorDegrees: 2),
            .aligned
        )

        for _ in 0..<(GazeReadinessPolicy.requiredBorderlineViolationSamples - 1) {
            XCTAssertEqual(
                tracker.update(yawErrorDegrees: 11.5, pitchErrorDegrees: 1),
                .aligned,
                "A brief boundary fluctuation is advisory"
            )
        }
        XCTAssertEqual(
            tracker.update(yawErrorDegrees: 11.5, pitchErrorDegrees: 1),
            .offCentre,
            "A sustained, finite violation is actionable"
        )

        XCTAssertEqual(
            GazeReadinessPolicy.classify(
                yawErrorDegrees: nil,
                pitchErrorDegrees: nil,
                thresholdDegrees: GazeReadinessPolicy.exitThresholdDegrees
            ),
            .unavailable,
            "Recorded-block validation must remain strict"
        )
    }

    func testPhoneSetupGazeIsAdvisoryWhilePhysicalSafetySignalsStillGateReadiness() {
        XCTAssertTrue(
            LivePositionReadinessPolicy.phoneSetupIsReady(
                distanceSample(gazeYaw: 35, gazePitch: -28)
            ),
            "An off-centre gaze must not block otherwise-safe phone setup"
        )
        XCTAssertTrue(
            LivePositionReadinessPolicy.phoneSetupIsReady(
                distanceSample(gazeYaw: nil, gazePitch: nil)
            ),
            "Unavailable gaze must not block otherwise-safe phone setup"
        )

        XCTAssertFalse(
            LivePositionReadinessPolicy.phoneSetupIsReady(distanceSample(phoneStable: false))
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.phoneSetupIsReady(distanceSample(luminance: 0.11))
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.phoneSetupIsReady(distanceSample(faceCount: 0))
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.phoneSetupIsReady(distanceSample(faceCount: 2))
        )
    }

    func testCalibrationGazeIsAdvisoryWhilePoseAndPhysicalSafetySignalsRemainStrict() {
        XCTAssertTrue(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(
                distanceSample(gazeYaw: 35, gazePitch: -28)
            ),
            "An off-centre gaze must not reset a valid distance lock"
        )
        XCTAssertTrue(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(
                distanceSample(gazeYaw: nil, gazePitch: nil)
            ),
            "A transient missing gaze estimate must not reset a valid distance lock"
        )

        XCTAssertFalse(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(
                distanceSample(headYaw: FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees + 0.01)
            )
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(
                distanceSample(headPitch: -(FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees + 0.01))
            )
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(distanceSample(phoneStable: false))
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(distanceSample(luminance: 0.11))
        )
        XCTAssertFalse(
            LivePositionReadinessPolicy.calibrationTrackingIsReady(distanceSample(faceCount: 2))
        )
    }

    func testJourneyViewModelsDelegateReadinessToGazeIndependentPolicy() throws {
        let source = try source(named: "SeeNA/Features/CoreJourneyViewModels.swift")

        XCTAssertTrue(source.contains("LivePositionReadinessPolicy.phoneSetupIsReady(sample)"))
        XCTAssertTrue(source.contains("LivePositionReadinessPolicy.calibrationTrackingIsReady(sample)"))
        XCTAssertFalse(source.contains("faceReady && phoneReady && lightReady && gazeReady"))
        XCTAssertFalse(source.contains("&& gazeState == .aligned"))

        let conditionCue = try section(
            in: source,
            from: "private func conditionCue(for sample: DistanceSample?)",
            to: "private func capture(session: AppSession"
        )
        XCTAssertFalse(conditionCue.contains("gazeState"))
    }

    func testStationarityIgnoresSingleImpulseAfterStableLock() {
        var evaluator = MotionStationarityEvaluator()
        let resting = attitude(rotationDegrees: 0)

        for frame in 0...24 {
            _ = evaluator.consume(
                attitude: resting,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }
        evaluator.lock(attitude: resting, timestamp: 0.9)

        var reading = MotionStationarityReading.unavailable
        for frame in 28...49 {
            reading = evaluator.consume(
                attitude: resting,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }
        XCTAssertTrue(reading.isStable)

        reading = evaluator.consume(
            attitude: resting,
            accelerationSquared: 0.09,
            rotationRateMagnitude: 0.40,
            timestamp: 50.0 / 30.0
        )
        XCTAssertTrue(reading.isStable, "One noisy frame must not trigger keep-phone-still")

        reading = evaluator.consume(
            attitude: resting,
            accelerationSquared: 0.000_025,
            rotationRateMagnitude: 0.005,
            timestamp: 51.0 / 30.0
        )
        XCTAssertTrue(reading.isStable)
    }

    func testStationarityRejectsSustainedMotionAfterDebounce() {
        var evaluator = MotionStationarityEvaluator()
        let resting = attitude(rotationDegrees: 0)

        for frame in 0...24 {
            _ = evaluator.consume(
                attitude: resting,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }
        evaluator.lock(attitude: resting, timestamp: 0.9)
        for frame in 28...49 {
            _ = evaluator.consume(
                attitude: resting,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }

        var reading = MotionStationarityReading.unavailable
        for frame in 50...64 {
            reading = evaluator.consume(
                attitude: attitude(rotationDegrees: 4),
                accelerationSquared: 0.01,
                rotationRateMagnitude: 0.40,
                timestamp: Double(frame) / 30
            )
        }

        XCTAssertFalse(reading.isStable)
        XCTAssertEqual(reading.stableDuration, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(reading.attitudeDriftDegrees, 3.9)
    }

    private func attitude(rotationDegrees: Double) -> MotionAttitude {
        let radians = rotationDegrees * .pi / 180
        return MotionAttitude(
            x: 0,
            y: sin(radians / 2),
            z: 0,
            w: cos(radians / 2)
        )
    }

    private func distanceSample(
        phoneStable: Bool = true,
        headYaw: Double = 0,
        headPitch: Double = 0,
        gazeYaw: Double? = 0,
        gazePitch: Double? = 0,
        luminance: Double = 0.5,
        faceCount: Int = 1
    ) -> DistanceSample {
        DistanceSample(
            rawARDistanceMetres: 0.40,
            relativeScaleDistanceMetres: 0.40,
            fusedDistanceMetres: 0.40,
            correctedDistanceMetres: 0.40,
            distanceStandardDeviation: 0.003,
            trackingCoverage: 1,
            phoneStable: phoneStable,
            attitudeDriftDegrees: 0,
            accelerationRMS: 0,
            headYawDegrees: headYaw,
            headPitchDegrees: headPitch,
            gazeYawErrorDegrees: gazeYaw,
            gazePitchErrorDegrees: gazePitch,
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

    private func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }
}
