import XCTest
@testable import SEENACore

final class MeasurementEngineTests: XCTestCase {
    func testDistanceGuidanceUsesStepsAndStopsInsideFarTolerance() {
        XCTAssertEqual(
            DistanceGuidanceEngine.cue(currentDistance: 0.40, targetDistance: 2.00),
            .moveBack(steps: 5)
        )
        XCTAssertEqual(
            DistanceGuidanceEngine.cue(currentDistance: 2.70, targetDistance: 2.00),
            .moveCloser(steps: 2)
        )
        XCTAssertEqual(
            DistanceGuidanceEngine.cue(currentDistance: 1.93, targetDistance: 2.00),
            .tinyStepBack
        )
        XCTAssertEqual(
            DistanceGuidanceEngine.cue(currentDistance: 1.96, targetDistance: 2.00),
            .stop
        )
    }

    func testFarTargetLockSurvivesNormalHeadMovementAndStartsQuickly() {
        var tracker = DistanceTargetTracker()
        var state = tracker.update(distance: 2.00, target: 2.00, conditionsReady: true, timestamp: 0)
        XCTAssertTrue(state.isInTargetZone)
        XCTAssertFalse(state.isReady)

        state = tracker.update(distance: 2.08, target: 2.00, conditionsReady: true, timestamp: 0.20)
        XCTAssertTrue(state.isInTargetZone)
        state = tracker.update(distance: 2.12, target: 2.00, conditionsReady: true, timestamp: 0.30)
        XCTAssertTrue(state.isInTargetZone, "One noisy frame must not throw the user out of position")
        state = tracker.update(distance: 1.99, target: 2.00, conditionsReady: true, timestamp: 0.50)
        XCTAssertTrue(state.isInTargetZone)
        state = tracker.update(distance: 2.04, target: 2.00, conditionsReady: true, timestamp: 0.70)
        XCTAssertTrue(state.isReady, "The far target should lock in well under one second")
    }

    func testDistanceFilterRejectsSingleFarRangeJump() throws {
        var filter = RobustDistanceFilter(windowSize: 9)
        for value in [1.99, 2.00, 2.01, 2.00, 1.98, 2.01, 2.00, 1.99] {
            _ = filter.update(value)
        }
        let filtered = try XCTUnwrap(filter.update(1.60))
        XCTAssertEqual(filtered, 2.00, accuracy: 0.015)
    }

    func testVoiceGuidanceWaitsForStableMeaningfulChanges() {
        var scheduler = VoiceGuidanceScheduler()
        scheduler.begin(at: 0)

        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 5), at: 0.60))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 5), at: 1.10))
        XCTAssertTrue(scheduler.shouldAnnounce(.moveBack(steps: 5), at: 1.50))

        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 4), at: 1.60))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 4), at: 2.20))
        XCTAssertTrue(scheduler.shouldAnnounce(.moveBack(steps: 4), at: 4.30))

        XCTAssertFalse(scheduler.shouldAnnounce(.stop, at: 4.40))
        XCTAssertFalse(scheduler.shouldAnnounce(.stop, at: 4.60))
        XCTAssertTrue(scheduler.shouldAnnounce(.stop, at: 5.00))
    }

    func testVoiceGuidanceSuppressesMovementAndStopAfterTargetAcceptance() {
        var scheduler = VoiceGuidanceScheduler()
        scheduler.begin(at: 0)
        scheduler.acceptTarget()

        XCTAssertFalse(scheduler.shouldAnnounce(.stop, at: 1))
        XCTAssertFalse(scheduler.shouldAnnounce(.stop, at: 10))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 3), at: 11))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveBack(steps: 3), at: 20))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 30))
    }

    func testVoiceGuidanceResumesOnlyWhenANewPositioningPhaseBegins() {
        var scheduler = VoiceGuidanceScheduler()
        scheduler.begin(at: 0)
        scheduler.acceptTarget()

        XCTAssertFalse(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 10))
        scheduler.reset()
        XCTAssertFalse(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 20))

        scheduler.begin(at: 30)
        XCTAssertFalse(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 30.50))
        XCTAssertFalse(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 31.00))
        XCTAssertTrue(scheduler.shouldAnnounce(.moveCloser(steps: 2), at: 31.50))
    }

    func testGazeAlignmentAtCameraHasNoAngularError() throws {
        let alignment = try XCTUnwrap(
            GazeAlignmentEngine.errors(
                eyeX: 0.03,
                eyeY: -0.02,
                eyeZ: -0.50,
                lookX: 0,
                lookY: 0,
                lookZ: 0
            )
        )

        XCTAssertEqual(alignment.yawErrorDegrees, 0, accuracy: 0.000_001)
        XCTAssertEqual(alignment.pitchErrorDegrees, 0, accuracy: 0.000_001)
    }

    func testGazeAlignmentReportsOffCentreAndRejectsOppositeRay() throws {
        let offCentre = try XCTUnwrap(
            GazeAlignmentEngine.errors(
                eyeX: 0,
                eyeY: 0,
                eyeZ: -0.50,
                lookX: 0.20,
                lookY: 0,
                lookZ: 0
            )
        )

        XCTAssertGreaterThan(offCentre.yawErrorDegrees, 15)
        XCTAssertNil(
            GazeAlignmentEngine.errors(
                eyeX: 0,
                eyeY: 0,
                eyeZ: -0.50,
                lookX: 0,
                lookY: 0,
                lookZ: -1
            )
        )
    }

    func testDiopterConversionUsesMeasuredDistance() throws {
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 2.0)), -0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 1.0)), -1.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.5)), -2.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.4)), -2.5, accuracy: 0.000_001)
        XCTAssertNil(RefractionEstimator.diopter(forDistanceMetres: 0))
    }

    func testClinicalReferenceGeometryRemainsPixelAlignedAndNearFiveArcMinutes() throws {
        for distance in [0.4, 0.5, 0.67, 0.8, 1.0, 1.33, 1.5, 2.0] {
            let geometry = try XCTUnwrap(
                OptotypeGeometry.calculate(
                    distanceMetres: distance,
                    pixelsPerInch: 460,
                    displayScale: 3,
                    presentationMode: .clinicalFiveArcMinute
                )
            )
            XCTAssertEqual(geometry.pixelHeight % 5, 0)
            XCTAssertEqual(geometry.strokePixels * 5, geometry.pixelHeight)
            XCTAssertEqual(geometry.innerDiameterPixels + geometry.strokePixels * 2, geometry.pixelHeight)
            XCTAssertEqual(geometry.gapPixels, geometry.strokePixels)
            XCTAssertEqual(geometry.requestedArcMinutes, 5)
            XCTAssertLessThan(abs(geometry.effectiveArcMinutes - 5), 1.3)
        }
    }

    func testPhonePOCSingleTargetIsLargePixelAlignedAndHonestAcrossSearchDistances() throws {
        let expectedPointHeights: [Double: Double] = [
            0.40: 200.0 / 3,
            0.50: 255.0 / 3,
            0.67: 340.0 / 3,
            0.80: 405.0 / 3,
            1.00: 505.0 / 3,
            1.33: 675.0 / 3,
            1.50: 760.0 / 3,
            2.00: 1_010.0 / 3
        ]

        for distance in expectedPointHeights.keys.sorted() {
            let geometry = try XCTUnwrap(
                OptotypeGeometry.calculate(
                    distanceMetres: distance,
                    pixelsPerInch: 460,
                    displayScale: 3,
                    presentationMode: .phonePOCLocator
                )
            )

            XCTAssertEqual(geometry.presentationMode, .phonePOCLocator)
            XCTAssertEqual(geometry.requestedArcMinutes, 96)
            XCTAssertEqual(geometry.pointHeight, try XCTUnwrap(expectedPointHeights[distance]), accuracy: 0.001)
            XCTAssertEqual(geometry.pixelHeight % 5, 0)
            XCTAssertEqual(geometry.strokePixels * 5, geometry.pixelHeight)
            XCTAssertEqual(geometry.innerDiameterPixels + geometry.strokePixels * 2, geometry.pixelHeight)
            XCTAssertEqual(geometry.gapPixels, geometry.strokePixels)
            XCTAssertFalse(geometry.wasPointSizeClamped)
            XCTAssertLessThan(abs(geometry.effectiveArcMinutes - 96), 1.3)
        }
    }

    func testPhonePOCSingleTargetKeepsConstantVisualAngleWithoutPointClamp() throws {
        let near = try XCTUnwrap(
            OptotypeGeometry.calculate(
                distanceMetres: 0.4,
                pixelsPerInch: 460,
                displayScale: 3,
                presentationMode: .phonePOCLocator
            )
        )
        let far = try XCTUnwrap(
            OptotypeGeometry.calculate(
                distanceMetres: 2,
                pixelsPerInch: 460,
                displayScale: 3,
                presentationMode: .phonePOCLocator
            )
        )

        XCTAssertFalse(near.wasPointSizeClamped)
        XCTAssertFalse(far.wasPointSizeClamped)
        XCTAssertEqual(near.requestedArcMinutes, far.requestedArcMinutes)
        XCTAssertEqual(near.effectiveArcMinutes, far.effectiveArcMinutes, accuracy: 1.3)
        XCTAssertGreaterThan(far.pointHeight, near.pointHeight * 4.9)
    }

    func testOptotypeRejectsSubPixelGeometry() {
        XCTAssertNil(
            OptotypeGeometry.calculate(
                distanceMetres: 0.1,
                pixelsPerInch: 460,
                displayScale: 3,
                minimumPixelHeight: 10,
                presentationMode: .clinicalFiveArcMinute
            )
        )
    }

    func testQualityGateRejectsEverySafetyFailure() {
        let sample = sample(
            distance: 1,
            standardDeviation: 0.08,
            tracking: 0.7,
            stable: false,
            drift: 3,
            acceleration: 0.04,
            yaw: 20,
            pitch: 15,
            luminance: 0.05,
            faceCount: 2
        )
        let quality = QualityGateEngine.evaluate(
            sample: sample,
            responseCount: 5,
            audioLevelAdequate: false,
            targetGeometryValid: false,
            orientationChanged: true,
            thresholds: .conservative
        )

        XCTAssertFalse(quality.isValid)
        XCTAssertEqual(
            Set(quality.discardReasons),
            Set([
                .trackingCoverage, .phoneMoved, .headPose, .distanceUnstable,
                .multipleFaces, .poorLighting, .responseCount, .audioLevel,
                .targetGeometry, .orientationChanged
            ])
        )
    }

    func testDirectionScoring() {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down]
        let responses: [OptotypeDirection] = [.up, .right, .down, .left, .up, .left, .right]
        XCTAssertEqual(TrialScorer.correctCount(targets: targets, responses: responses), 5)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 5, hasExactlySevenResponses: true), .pass)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 4, hasExactlySevenResponses: true), .borderline)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 3, hasExactlySevenResponses: true), .fail)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 7, hasExactlySevenResponses: false), .invalid)
    }

    func testGaborScoringUsesSameConservativeSevenAnswerRule() {
        let targets: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left]
        let responses: [GaborOrientation] = [.left, .right, .left, .right, .right, .left, .left]
        XCTAssertEqual(GaborScorer.correctCount(targets: targets, responses: responses), 5)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 5, hasExactlySevenResponses: true), .pass)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 4, hasExactlySevenResponses: true), .borderline)
    }

    func testGaborContrastStaircaseStopsAtFirstFailedLevel() {
        var engine = GaborContrastEngine(eye: .right)
        XCTAssertEqual(engine.nextAction, .test(contrast: 0.40))
        XCTAssertEqual(engine.submit(gaborTrial(contrast: 0.40, outcome: .pass)), .test(contrast: 0.25))
        XCTAssertEqual(engine.submit(gaborTrial(contrast: 0.25, outcome: .pass)), .test(contrast: 0.16))

        guard case .completed(let result) = engine.submit(gaborTrial(contrast: 0.16, outcome: .fail)) else {
            return XCTFail("Expected a completed Gabor result")
        }
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.responseConsistency, .good)
    }

    func testGaborContrastStaircaseRejectsStaleWrongLevel() {
        var engine = GaborContrastEngine(eye: .right)

        guard case .completed(let result) = engine.submit(gaborTrial(contrast: 0.25, outcome: .pass)) else {
            return XCTFail("Expected stale contrast to terminate as unreliable")
        }

        XCTAssertEqual(result.status, .unreliableMeasurement)
        XCTAssertEqual(result.responseConsistency, .poor)
    }

    func testSearchStartsCloseAndMovesFartherOnlyAfterPassing() {
        var engine = ThresholdSearchEngine(eye: .right)
        XCTAssertEqual(
            engine.nextAction,
            .test(candidate: .init(diopter: -2.5), stage: .coarse)
        )
        XCTAssertEqual(
            engine.submit(block: block(eye: .right, candidate: -2.5, distance: 0.40, outcome: .pass)),
            .test(candidate: .init(diopter: -1.25), stage: .coarse)
        )
        XCTAssertEqual(
            engine.submit(block: block(eye: .right, candidate: -1.25, distance: 0.80, outcome: .pass)),
            .test(candidate: .init(diopter: -0.5), stage: .coarse)
        )
    }

    func testPassingThroughFarthestCandidateRequiresConfirmationAndReturnsBoundaryStatus() {
        var engine = ThresholdSearchEngine(eye: .right)
        for (candidate, nextCandidate) in zip(
            ThresholdSearchEngine.coarseCandidates.dropLast(),
            ThresholdSearchEngine.coarseCandidates.dropFirst()
        ) {
            XCTAssertEqual(
                engine.submit(block: block(eye: .right, candidate: candidate, distance: 1 / abs(candidate), outcome: .pass)),
                .test(candidate: .init(diopter: nextCandidate), stage: .coarse)
            )
        }
        XCTAssertEqual(
            engine.submit(block: block(eye: .right, candidate: -0.5, distance: 2.01, outcome: .pass)),
            .test(candidate: .init(diopter: -0.5), stage: .confirmation)
        )

        let confirmation = block(eye: .right, candidate: -0.5, distance: 1.98, outcome: .pass)
        guard case .completed(let result) = engine.submit(block: confirmation) else {
            return XCTFail("Expected completed boundary result")
        }
        XCTAssertEqual(result.status, .noMyopiaDetectedWithinRange)
        XCTAssertNil(result.displayedEstimateDiopter)
        XCTAssertEqual(result.thresholdDistanceMetres, 1.98)
    }

    func testFirstFarFailureIsBracketedWithNearestPassThenConfirmed() {
        var engine = ThresholdSearchEngine(eye: .left)
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2.5, distance: 0.40, outcome: .pass)), .test(candidate: .init(diopter: -1.25), stage: .coarse))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -1.25, distance: 0.80, outcome: .fail)), .test(candidate: .init(diopter: -2), stage: .fine))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2, distance: 0.50, outcome: .fail)), .test(candidate: .init(diopter: -2.25), stage: .fine))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2.25, distance: 0.445, outcome: .pass)), .test(candidate: .init(diopter: -2.25), stage: .confirmation))

        guard case .completed(let result) = engine.submit(block: block(eye: .left, candidate: -2.25, distance: 0.44, outcome: .pass)) else {
            return XCTFail("Expected valid result")
        }
        XCTAssertEqual(result.status, .validEstimate)
        XCTAssertEqual(result.lastFailDiopter, -2)
        XCTAssertEqual(result.firstPassDiopter, -2.25)
        XCTAssertEqual(try XCTUnwrap(result.displayedEstimateDiopter), -2.25, accuracy: 0.000_001)
        XCTAssertEqual(result.thresholdDistanceMetres, 0.44)
    }

    func testFailingClosestCandidateRequiresConfirmationAndReturnsStrongBoundary() {
        var engine = ThresholdSearchEngine(eye: .right)
        XCTAssertEqual(
            engine.submit(block: block(eye: .right, candidate: -2.5, distance: 0.40, outcome: .fail)),
            .test(candidate: .init(diopter: -2.5), stage: .boundaryConfirmation)
        )
        guard case .completed(let result) = engine.submit(block: block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .fail)) else {
            return XCTFail("Expected completed strong-boundary result")
        }
        XCTAssertEqual(result.status, .strongerThanSupportedRange)
        XCTAssertNil(result.displayedEstimateDiopter)
        XCTAssertEqual(result.thresholdDistanceMetres, 0.4)
    }

    func testBorderlineRepeatsOnceThenReturnsUnreliable() {
        var engine = ThresholdSearchEngine(eye: .right)
        let borderline = block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .borderline)
        XCTAssertEqual(engine.submit(block: borderline), .test(candidate: .init(diopter: -2.5), stage: .coarse))
        guard case .completed(let result) = engine.submit(block: borderline) else {
            return XCTFail("Expected unreliable result")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
    }

    func testCalibrationAcceptanceRequiresAllDistancesAndEnoughAccuracy() throws {
        let required = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]
        let observations = required.flatMap { distance in
            (0..<150).map { index in
                CalibrationObservation(
                    groundTruthMetres: distance,
                    rawDistanceMetres: (distance + 0.008) / 1.018 + Double(index % 3 - 1) * 0.001
                )
            }
        }
        let fit = try XCTUnwrap(CalibrationFitter.affineFit(observations: observations))
        XCTAssertTrue(CalibrationFitter.passesAcceptance(observations: observations, fit: fit))
    }

    func testStatisticsAndDistanceFusionRejectNoise() throws {
        XCTAssertEqual(Statistics.median([9, 1, 5, 3]), 4)
        XCTAssertEqual(try XCTUnwrap(Statistics.standardDeviation([1, 1, 1])), 0, accuracy: 0.000_001)
        XCTAssertEqual(Statistics.rejectOutliersMAD([1.0, 1.01, 0.99, 4.0]).count, 3)

        var fusion = DistanceFusionEngine(windowSize: 12)
        fusion.setBaseline(arDistance: 0.4, interEyePixels: 200)
        let estimate = fusion.estimate(rawARDistance: 0.8, interEyePixels: 100, yawDegrees: 0, profile: nil)
        XCTAssertEqual(try XCTUnwrap(estimate.relative), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(estimate.fused), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(estimate.corrected), 0.8, accuracy: 0.000_001)
    }

    func testStationarityRebasesAfterPlacementThenRecognisesStillPhone() {
        var evaluator = MotionStationarityEvaluator()
        let held = attitude(rotationDegrees: 0)
        let placed = attitude(rotationDegrees: 75)

        _ = evaluator.consume(
            attitude: held,
            accelerationSquared: 0.04,
            rotationRateMagnitude: 0.6,
            timestamp: 0
        )
        for frame in 1...18 {
            _ = evaluator.consume(
                attitude: placed,
                accelerationSquared: 0.04,
                rotationRateMagnitude: 0.6,
                timestamp: Double(frame) / 30
            )
        }

        var reading = MotionStationarityReading.unavailable
        for frame in 19...75 {
            reading = evaluator.consume(
                attitude: placed,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }

        XCTAssertTrue(reading.isStable)
        XCTAssertLessThan(reading.attitudeDriftDegrees, 0.01)
    }

    func testLockedStationarityNeverRebasesAfterPhoneMoves() {
        var evaluator = MotionStationarityEvaluator()
        let resting = attitude(rotationDegrees: 0)
        let moved = attitude(rotationDegrees: 5)

        for frame in 0...30 {
            _ = evaluator.consume(
                attitude: resting,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }
        evaluator.lock(attitude: resting, timestamp: 1.1)

        var reading = MotionStationarityReading.unavailable
        for frame in 34...100 {
            reading = evaluator.consume(
                attitude: moved,
                accelerationSquared: 0.000_025,
                rotationRateMagnitude: 0.005,
                timestamp: Double(frame) / 30
            )
        }

        XCTAssertFalse(reading.isStable)
        XCTAssertEqual(reading.attitudeDriftDegrees, 5, accuracy: 0.001)
    }

    func testGoodQualityBlockPassesGate() {
        let quality = QualityGateEngine.evaluate(
            sample: sample(
                distance: 0.8,
                standardDeviation: 0.008,
                tracking: 0.98,
                stable: true,
                drift: 0.3,
                acceleration: 0.004,
                yaw: 1,
                pitch: 1,
                luminance: 0.5,
                faceCount: 1
            ),
            responseCount: 7,
            audioLevelAdequate: true,
            targetGeometryValid: true,
            orientationChanged: false,
            thresholds: .conservative
        )
        XCTAssertTrue(quality.isValid)
        XCTAssertTrue(quality.discardReasons.isEmpty)
    }

    func testBlockMeasurementQualityAcceptsSmallMinorityOfNoisyFrames() throws {
        var samples = (0..<20).map { index in
            sample(
                distance: 2 + Double(index % 3 - 1) * 0.004,
                standardDeviation: 0.008,
                tracking: 0.98,
                stable: true,
                drift: 0.2,
                acceleration: 0.004,
                yaw: 1,
                pitch: 1,
                luminance: 0.5,
                faceCount: 1
            )
        }
        samples.append(sample(
            distance: 1.2,
            standardDeviation: 0.3,
            tracking: 0,
            stable: false,
            drift: 5,
            acceleration: 0.1,
            yaw: 35,
            pitch: 35,
            luminance: 0.02,
            faceCount: 2
        ))

        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: samples,
            targetDistanceMetres: 2,
            targetToleranceMetres: 0.10,
            thresholds: .conservative
        )

        XCTAssertTrue(aggregate.isAccepted)
        XCTAssertEqual(try XCTUnwrap(aggregate.medianDistanceMetres), 2, accuracy: 0.005)
        XCTAssertLessThan(try XCTUnwrap(aggregate.distanceStandardDeviationMetres), 0.01)
    }

    func testBlockMeasurementQualityRejectsSustainedMovement() {
        let samples = (0..<20).map { index in
            let moved = index >= 11
            return sample(
                distance: moved ? 1.72 + Double(index - 11) * 0.01 : 2,
                standardDeviation: moved ? 0.08 : 0.008,
                tracking: 0.98,
                stable: !moved,
                drift: moved ? 4 : 0.2,
                acceleration: moved ? 0.06 : 0.004,
                yaw: 1,
                pitch: 1,
                luminance: 0.5,
                faceCount: 1
            )
        }

        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: samples,
            targetDistanceMetres: 2,
            targetToleranceMetres: 0.10,
            thresholds: .conservative
        )

        XCTAssertFalse(aggregate.isAccepted)
        XCTAssertTrue(aggregate.issues.contains(.phoneMoved))
        XCTAssertTrue(aggregate.issues.contains(.distanceOffTarget))
    }

    func testBlockMeasurementQualityRejectsPersistentPoorConditions() {
        let samples = (0..<20).map { index in
            let poor = index >= 14
            return sample(
                distance: 2,
                standardDeviation: 0.008,
                tracking: poor ? 0.20 : 0.98,
                stable: true,
                drift: 0.2,
                acceleration: 0.004,
                yaw: poor ? 30 : 1,
                pitch: poor ? 30 : 1,
                luminance: poor ? 0.03 : 0.5,
                faceCount: poor ? 2 : 1
            )
        }

        let aggregate = BlockMeasurementQualityEngine.evaluate(
            samples: samples,
            targetDistanceMetres: 2,
            targetToleranceMetres: 0.10,
            thresholds: .conservative
        )

        XCTAssertFalse(aggregate.isAccepted)
        XCTAssertTrue(aggregate.issues.contains(.trackingUnreliable))
        XCTAssertTrue(aggregate.issues.contains(.headPose))
        XCTAssertTrue(aggregate.issues.contains(.poorLighting))
        XCTAssertTrue(aggregate.issues.contains(.multipleFaces))
    }

    func testCalibrationRejectsMissingDistanceAndPoorFit() throws {
        let incomplete = [
            CalibrationObservation(groundTruthMetres: 0.4, rawDistanceMetres: 0.4),
            CalibrationObservation(groundTruthMetres: 0.5, rawDistanceMetres: 0.5)
        ]
        let incompleteFit = try XCTUnwrap(CalibrationFitter.affineFit(observations: incomplete))
        XCTAssertFalse(CalibrationFitter.passesAcceptance(observations: incomplete, fit: incompleteFit))

        let required = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]
        let poor = required.flatMap { distance in
            (0..<10).map { _ in CalibrationObservation(groundTruthMetres: distance, rawDistanceMetres: distance * distance) }
        }
        let poorFit = try XCTUnwrap(CalibrationFitter.affineFit(observations: poor))
        XCTAssertFalse(CalibrationFitter.passesAcceptance(observations: poor, fit: poorFit))
    }

    func testConfirmationDisagreementReturnsNoReliableResult() {
        var engine = ThresholdSearchEngine(eye: .right)
        _ = engine.submit(block: block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .pass))
        _ = engine.submit(block: block(eye: .right, candidate: -1.25, distance: 0.8, outcome: .fail))
        _ = engine.submit(block: block(eye: .right, candidate: -2, distance: 0.5, outcome: .fail))
        _ = engine.submit(block: block(eye: .right, candidate: -2.25, distance: 0.445, outcome: .pass))

        let firstDisagreement = engine.submit(block: block(eye: .right, candidate: -2.25, distance: 0.445, outcome: .fail))
        XCTAssertEqual(firstDisagreement, .test(candidate: .init(diopter: -2.25), stage: .confirmation))
        guard case .completed(let result) = engine.submit(block: block(eye: .right, candidate: -2.25, distance: 0.445, outcome: .fail)) else {
            return XCTFail("Expected a conservative no-result")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
    }

    func testThreeInvalidAttemptsReturnNoReliableResult() {
        var engine = ThresholdSearchEngine(eye: .right)
        let invalid = invalidBlock(eye: .right, candidate: -2.5, distance: 0.4)
        _ = engine.submit(block: invalid)
        _ = engine.submit(block: invalid)
        guard case .completed(let result) = engine.submit(block: invalid) else {
            return XCTFail("Expected invalid retry budget to end")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
    }

    func testWrongEyeCannotContaminateSearch() {
        var engine = ThresholdSearchEngine(eye: .right)
        guard case .completed(let result) = engine.submit(block: block(eye: .left, candidate: -2.5, distance: 0.4, outcome: .pass)) else {
            return XCTFail("Expected wrong-eye rejection")
        }
        XCTAssertEqual(result.status, .unreliableMeasurement)
    }

    func testStaleCandidateOrTargetDistanceCannotAdvanceSearch() {
        var staleCandidate = ThresholdSearchEngine(eye: .right)
        guard case .completed(let staleCandidateResult) = staleCandidate.submit(block:
            block(eye: .right, candidate: -1.25, distance: 0.8, outcome: .pass)
        ) else {
            return XCTFail("A stale candidate must end without an estimate")
        }
        XCTAssertEqual(staleCandidateResult.status, .unreliableMeasurement)

        var wrongTargetDistance = ThresholdSearchEngine(eye: .right)
        let requested = block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .pass)
        let tampered = TrialBlock(
            eye: requested.eye,
            candidateDiopter: requested.candidateDiopter,
            targetDistanceMetres: 0.5,
            actualMedianDistanceMetres: requested.actualMedianDistanceMetres,
            distanceStandardDeviation: requested.distanceStandardDeviation,
            targets: requested.targets,
            responses: requested.responses,
            correctCount: requested.correctCount,
            outcome: requested.outcome,
            quality: requested.quality,
            responseSource: requested.responseSource,
            transcript: requested.transcript
        )
        guard case .completed(let wrongTargetResult) = wrongTargetDistance.submit(block: tampered) else {
            return XCTFail("A target-distance mismatch must end without an estimate")
        }
        XCTAssertEqual(wrongTargetResult.status, .unreliableMeasurement)
    }

    private func block(eye: Eye, candidate: Double, distance: Double, outcome: TrialOutcome) -> TrialBlock {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down]
        let responses = outcome == .pass ? targets : Array(repeating: OptotypeDirection.left, count: 7)
        return TrialBlock(
            eye: eye,
            candidateDiopter: candidate,
            targetDistanceMetres: 1 / abs(candidate),
            actualMedianDistanceMetres: distance,
            distanceStandardDeviation: 0.008,
            targets: targets,
            responses: responses,
            correctCount: outcome == .pass ? 7 : outcome == .borderline ? 4 : 2,
            outcome: outcome,
            quality: BlockQuality(
                trackingCoverage: 0.98,
                phoneStable: true,
                headPoseValid: true,
                distanceStable: true,
                audioLevelAdequate: true,
                targetGeometryValid: true,
                discardReasons: []
            ),
            responseSource: .voice,
            transcript: nil
        )
    }

    private func invalidBlock(eye: Eye, candidate: Double, distance: Double) -> TrialBlock {
        let valid = block(eye: eye, candidate: candidate, distance: distance, outcome: .pass)
        return TrialBlock(
            eye: eye,
            candidateDiopter: candidate,
            targetDistanceMetres: valid.targetDistanceMetres,
            actualMedianDistanceMetres: distance,
            distanceStandardDeviation: 0.2,
            targets: valid.targets,
            responses: valid.responses,
            correctCount: 7,
            outcome: .invalid,
            quality: BlockQuality(
                trackingCoverage: 0.5,
                phoneStable: false,
                headPoseValid: true,
                distanceStable: false,
                audioLevelAdequate: true,
                targetGeometryValid: true,
                discardReasons: [.phoneMoved, .distanceUnstable]
            ),
            responseSource: .voice,
            transcript: nil
        )
    }

    private func sample(
        distance: Double,
        standardDeviation: Double,
        tracking: Double,
        stable: Bool,
        drift: Double,
        acceleration: Double,
        yaw: Double,
        pitch: Double,
        luminance: Double,
        faceCount: Int
    ) -> DistanceSample {
        DistanceSample(
            rawARDistanceMetres: distance,
            relativeScaleDistanceMetres: distance,
            fusedDistanceMetres: distance,
            correctedDistanceMetres: distance,
            distanceStandardDeviation: standardDeviation,
            trackingCoverage: tracking,
            phoneStable: stable,
            attitudeDriftDegrees: drift,
            accelerationRMS: acceleration,
            headYawDegrees: yaw,
            headPitchDegrees: pitch,
            luminance: luminance,
            faceCount: faceCount,
            interEyePixels: 200
        )
    }

    private func gaborTrial(contrast: Double, outcome: TrialOutcome) -> GaborTrial {
        let targets: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left]
        return GaborTrial(
            eye: .right,
            contrast: contrast,
            targets: targets,
            responses: targets,
            correctCount: outcome == .pass ? 7 : 2,
            outcome: outcome,
            responseSource: .voice,
            transcript: nil
        )
    }

    private func attitude(rotationDegrees: Double) -> MotionAttitude {
        let halfAngle = rotationDegrees * .pi / 360
        return MotionAttitude(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
    }
}
