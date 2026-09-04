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

    func testGazeReadinessTreatsMissingAsUnavailableAndUsesHysteresis() {
        var tracker = GazeReadinessTracker()
        XCTAssertEqual(tracker.update(yawErrorDegrees: nil, pitchErrorDegrees: nil), .unavailable)
        XCTAssertEqual(tracker.update(yawErrorDegrees: 7.5, pitchErrorDegrees: 2), .aligned)
        XCTAssertEqual(tracker.update(yawErrorDegrees: 9.5, pitchErrorDegrees: 2), .aligned)
        XCTAssertEqual(tracker.update(yawErrorDegrees: 12, pitchErrorDegrees: 2), .offCentre)
    }

    func testDiopterConversionUsesMeasuredDistance() throws {
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 2.0)), -0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 1.0)), -1.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.5)), -2.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(RefractionEstimator.diopter(forDistanceMetres: 0.4)), -2.5, accuracy: 0.000_001)
        XCTAssertNil(RefractionEstimator.diopter(forDistanceMetres: 0))
    }

    func testPresentedGeometryFreezesNativeScaleAndPixelBounds() throws {
        let frozen = try XCTUnwrap(PresentedOptotypeGeometry.calculate(
            distanceMetres: 0.8,
            pixelsPerInch: 460,
            nativeScale: 3
        ))
        XCTAssertTrue(frozen.geometry.pixelHeight.isMultiple(of: 5))
        XCTAssertEqual(
            frozen.geometry.pointHeight,
            Double(frozen.geometry.pixelHeight) / 3,
            accuracy: 0.000_001
        )
        XCTAssertEqual(frozen.presentationDistanceMetres, 0.8)
        XCTAssertEqual(frozen.nativeScale, 3)
        XCTAssertNotNil(frozen.computedArcMinutes(at: 0.81))
    }

    func testLiveEyeViewModelGeometryPolicyUsesReadablePhonePOCTarget() throws {
        for distance in [0.40, 0.80, 2.0] {
            let presented = try XCTUnwrap(LiveEyeTestGeometryPolicy.calculate(
                distanceMetres: distance,
                pixelsPerInch: 460,
                nativeScale: 3
            ))
            XCTAssertEqual(presented.geometry.presentationMode, .phonePOCLocator)
            XCTAssertGreaterThanOrEqual(presented.geometry.pointHeight, 96)
            XCTAssertLessThanOrEqual(presented.geometry.pointHeight, 220)
            XCTAssertEqual(presented.geometry.requestedArcMinutes, 96, accuracy: 0.000_001)
            XCTAssertGreaterThan(presented.geometry.effectiveArcMinutes, 0)
        }
    }

    func testBoundedSpeechReturnsTimeoutWhenPromptDoesNotComplete() async {
        let result = await BoundedSpeechPolicy.wait(timeoutNanoseconds: 10_000_000) {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return .finished
            } catch {
                return .cancelled
            }
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testBoundedSpeechAndNavigationRejectCancellationOrBackNavigation() async {
        let task = Task {
            await BoundedSpeechPolicy.wait(timeoutNanoseconds: 5_000_000_000) {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .finished
                } catch {
                    return .cancelled
                }
            }
        }
        task.cancel()
        let cancelledResult = await task.value
        XCTAssertEqual(cancelledResult, .completed(.cancelled))

        let generation = UUID()
        XCTAssertTrue(CompletionNavigationPolicy.shouldAdvance(
            after: .failed,
            expectedRoute: "calibration",
            currentRoute: "calibration",
            expectedGeneration: generation,
            currentGeneration: generation,
            taskIsCancelled: false
        ))
        XCTAssertFalse(CompletionNavigationPolicy.shouldAdvance(
            after: .finished,
            expectedRoute: "right-eye",
            currentRoute: "instructions",
            expectedGeneration: generation,
            currentGeneration: generation,
            taskIsCancelled: false
        ))
        XCTAssertFalse(CompletionNavigationPolicy.shouldAdvance(
            after: .finished,
            expectedRoute: "right-eye",
            currentRoute: "right-eye",
            expectedGeneration: generation,
            currentGeneration: UUID(),
            taskIsCancelled: false
        ))
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
        for distance in [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00] {
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
            XCTAssertGreaterThanOrEqual(geometry.pointHeight, 96)
            XCTAssertLessThanOrEqual(geometry.pointHeight, 220)
            XCTAssertEqual(geometry.pixelHeight % 5, 0)
            XCTAssertEqual(geometry.strokePixels * 5, geometry.pixelHeight)
            XCTAssertEqual(geometry.innerDiameterPixels + geometry.strokePixels * 2, geometry.pixelHeight)
            XCTAssertEqual(geometry.gapPixels, geometry.strokePixels)
            XCTAssertGreaterThan(geometry.effectiveArcMinutes, 0)
        }
    }

    func testPhonePOCSingleTargetTruthfullyRecordsPointClamping() throws {
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

        XCTAssertTrue(near.wasPointSizeClamped)
        XCTAssertTrue(far.wasPointSizeClamped)
        XCTAssertEqual(near.requestedArcMinutes, far.requestedArcMinutes)
        XCTAssertNotEqual(near.effectiveArcMinutes, far.effectiveArcMinutes)
        XCTAssertEqual(near.pointHeight, 290.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(far.pointHeight, 220, accuracy: 0.001)
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

    func testLandoltScoringUsesIndependentSixOfEightRule() {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down, .left]
        let responses: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .left, .up]
        XCTAssertEqual(TrialScorer.correctCount(targets: targets, responses: responses), 6)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 6, responseCount: 8), .pass)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 8, responseCount: 8), .pass)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 5, responseCount: 8), .borderline)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 4, responseCount: 8), .fail)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 0, responseCount: 8), .fail)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 6, responseCount: 7), .invalid)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 6, responseCount: 9), .invalid)
        XCTAssertEqual(TrialScorer.outcome(correctCount: -1, responseCount: 8), .invalid)
        XCTAssertEqual(TrialScorer.outcome(correctCount: 9, responseCount: 8), .invalid)
        XCTAssertEqual(TrialScorer.randomGuessPassProbability, 0.004_226_684_570_312_5)
        XCTAssertEqual(LandoltProtocolDescriptor.activePhoneLocator.version, 3)
        XCTAssertEqual(
            LandoltProtocolDescriptor.activePhoneLocator.responsesPerLevel,
            SequentialOptotypeSession.requiredTargetCount
        )
    }

    func testGaborScoringUsesIndependentSevenOfEightRule() {
        let targets: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left, .right]
        let responses: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left, .left]
        XCTAssertEqual(GaborScorer.correctCount(targets: targets, responses: responses), 7)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 7, responseCount: 8), .pass)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 8, responseCount: 8), .pass)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 6, responseCount: 8), .borderline)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 5, responseCount: 8), .fail)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 0, responseCount: 8), .fail)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 7, responseCount: 7), .invalid)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 7, responseCount: 9), .invalid)
        XCTAssertEqual(GaborScorer.outcome(correctCount: -1, responseCount: 8), .invalid)
        XCTAssertEqual(GaborScorer.outcome(correctCount: 9, responseCount: 8), .invalid)
        XCTAssertEqual(GaborScorer.randomGuessPassProbability, 0.035_156_25)
    }

    func testGaborUsesOneVisibleBlockAndCompletesNeutrallyForEveryValidScore() {
        XCTAssertEqual(GaborContrastEngine.contrastLevels, [0.40])

        for eye in Eye.allCases {
            for scoreOutcome in [TrialOutcome.pass, .borderline, .fail] {
                var engine = GaborContrastEngine(eye: eye)
                XCTAssertEqual(engine.nextAction, .test(contrast: 0.40))

                guard case .completed(let result) = engine.submit(
                    gaborTrial(contrast: 0.40, outcome: scoreOutcome, eye: eye)
                ) else { return XCTFail("One valid Gabor block must complete the task") }

                XCTAssertEqual(result.eye, eye)
                XCTAssertEqual(result.status, .completed)
                XCTAssertEqual(result.responseConsistency, .good)
                XCTAssertEqual(
                    GaborCompletionPolicy.disposition(for: result, integrityIsValid: true),
                    .reliableCompletion
                )
                XCTAssertEqual(engine.nextAction, .completed(result))
            }
        }
    }

    func testGaborContrastStaircaseRejectsStaleWrongLevel() {
        var engine = GaborContrastEngine(eye: .right)

        guard case .completed(let result) = engine.submit(gaborTrial(contrast: 0.25, outcome: .pass)) else {
            return XCTFail("Expected stale contrast to terminate as unreliable")
        }

        XCTAssertEqual(result.status, .unreliableMeasurement)
        XCTAssertEqual(result.responseConsistency, .poor)
    }

    func testActiveLandoltUsesOneFortyCentimetreBlockAndNeverMovesFarther() {
        XCTAssertEqual(ThresholdSearchEngine.coarseCandidates, [-2.50])
        XCTAssertEqual(ThresholdSearchEngine.maximumActivePhoneLocatorDistanceMetres, 0.40)

        for eye in Eye.allCases {
            for scoreOutcome in [TrialOutcome.pass, .borderline, .fail] {
                var engine = ThresholdSearchEngine(eye: eye)
                guard case .test(let candidate, .coarse) = engine.nextAction else {
                    return XCTFail("Expected the one active block")
                }
                XCTAssertEqual(candidate.diopter, -2.50)
                XCTAssertEqual(candidate.distanceMetres, 0.40, accuracy: 0.000_001)

                guard case .completed(let result) = engine.submit(block: block(
                    eye: eye,
                    candidate: candidate.diopter,
                    distance: candidate.distanceMetres,
                    outcome: scoreOutcome
                )) else { return XCTFail("One quality-valid block must complete the task") }

                XCTAssertEqual(result.eye, eye)
                XCTAssertEqual(result.status, .experimentalTaskCompleted)
                XCTAssertEqual(result.recommendedAction, .unavailable)
                assertNoNumericPayload(result)
            }
        }
    }

    func testFutureClinicalProtocolKeepsItsExistingTwoMetreSearchRange() {
        let descriptor = LandoltProtocolDescriptor(
            identifier: "future-clinical-five-arcminute",
            version: 1,
            presentationMode: .clinicalFiveArcMinute,
            responsesPerLevel: SequentialOptotypeSession.requiredTargetCount,
            usesValidatedThresholdModel: true,
            permitsPointSizeClamping: false
        )
        var engine = ThresholdSearchEngine(eye: .right, protocolDescriptor: descriptor)

        XCTAssertEqual(
            engine.submit(block: block(
                eye: .right,
                candidate: -2.50,
                distance: 0.40,
                outcome: .pass
            )),
            .test(candidate: .init(diopter: -1.25), stage: .coarse)
        )
        XCTAssertEqual(
            engine.submit(block: block(
                eye: .right,
                candidate: -1.25,
                distance: 0.80,
                outcome: .pass
            )),
            .test(candidate: .init(diopter: -0.50), stage: .coarse)
        )
        XCTAssertEqual(
            engine.submit(block: block(
                eye: .right,
                candidate: -0.50,
                distance: 2.00,
                outcome: .pass
            )),
            .test(candidate: .init(diopter: -0.50), stage: .confirmation)
        )
    }

    func testFutureClinicalPathStillBracketsRefinesAndConfirms() {
        var engine = ThresholdSearchEngine(
            eye: .left,
            protocolDescriptor: futureClinicalDescriptor
        )
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2.5, distance: 0.40, outcome: .pass)), .test(candidate: .init(diopter: -1.25), stage: .coarse))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -1.25, distance: 0.80, outcome: .fail)), .test(candidate: .init(diopter: -2), stage: .fine))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2, distance: 0.50, outcome: .fail)), .test(candidate: .init(diopter: -2.25), stage: .fine))
        XCTAssertEqual(engine.submit(block: block(eye: .left, candidate: -2.25, distance: 0.445, outcome: .pass)), .test(candidate: .init(diopter: -2.25), stage: .confirmation))

        guard case .completed(let result) = engine.submit(block: block(eye: .left, candidate: -2.25, distance: 0.44, outcome: .pass)) else {
            return XCTFail("Expected valid result")
        }
        XCTAssertEqual(result.status, .experimentalThresholdObserved)
        assertNoNumericPayload(result)
    }

    func testPhoneTaskCompletesOnceWithoutNumericPayloadForAnyDescriptorFlags() {
        let descriptors = [
            LandoltProtocolDescriptor.activePhoneLocator,
            LandoltProtocolDescriptor(
                identifier: "locally-spoofed-phone-protocol",
                version: 999,
                presentationMode: .phonePOCLocator,
                responsesPerLevel: 100,
                usesValidatedThresholdModel: true,
                permitsPointSizeClamping: false
            )
        ]

        for descriptor in descriptors {
            var engine = ThresholdSearchEngine(
                eye: .right,
                protocolDescriptor: descriptor
            )
            guard case .completed(let result) = engine.submit(block: block(
                eye: .right,
                candidate: -2.5,
                distance: 0.40,
                outcome: .pass
            )) else {
                return XCTFail("Expected phone locator completion")
            }

            XCTAssertEqual(result.status, .experimentalTaskCompleted)
            XCTAssertEqual(result.recommendedAction, .unavailable)
            assertNoNumericPayload(result)
        }
    }

    func testMalformedActiveBlockRepeatsThenAValidBlockCompletes() {
        var engine = ThresholdSearchEngine(eye: .right)
        let valid = block(eye: .right, candidate: -2.5, distance: 0.40, outcome: .pass)
        let malformed = TrialBlock(
            eye: valid.eye,
            candidateDiopter: valid.candidateDiopter,
            targetDistanceMetres: valid.targetDistanceMetres,
            actualMedianDistanceMetres: valid.actualMedianDistanceMetres,
            distanceStandardDeviation: valid.distanceStandardDeviation,
            targets: valid.targets,
            responses: Array(valid.responses.dropLast()),
            correctCount: valid.correctCount - 1,
            outcome: .pass,
            quality: valid.quality,
            responseSource: valid.responseSource,
            transcript: valid.transcript
        )

        XCTAssertEqual(
            engine.submit(block: malformed),
            .test(candidate: .init(diopter: -2.5), stage: .coarse)
        )
        guard case .completed(let result) = engine.submit(block: valid) else {
            return XCTFail("A valid retry should complete")
        }
        XCTAssertEqual(result.status, .experimentalTaskCompleted)
    }

    func testActiveLandoltIntegrityRequiresExactlyOneValidBlockPerEye() {
        for eye in Eye.allCases {
            let valid = block(
                eye: eye,
                candidate: -2.5,
                distance: 0.40,
                outcome: .fail
            )
            var engine = ThresholdSearchEngine(eye: eye)
            guard case .completed(let result) = engine.submit(block: valid) else {
                return XCTFail("Expected neutral task completion")
            }

            XCTAssertTrue(
                ResultIntegrityValidator.validate(result, against: [valid]).isValid
            )
            XCTAssertFalse(
                ResultIntegrityValidator.validate(result, against: [valid, valid]).isValid
            )

            let malformed = TrialBlock(
                eye: valid.eye,
                candidateDiopter: valid.candidateDiopter,
                targetDistanceMetres: valid.targetDistanceMetres,
                actualMedianDistanceMetres: valid.actualMedianDistanceMetres,
                distanceStandardDeviation: valid.distanceStandardDeviation,
                targets: valid.targets,
                responses: Array(valid.responses.dropLast()),
                correctCount: valid.correctCount,
                outcome: valid.outcome,
                quality: valid.quality,
                responseSource: valid.responseSource,
                transcript: valid.transcript
            )
            XCTAssertFalse(
                ResultIntegrityValidator.validate(result, against: [malformed]).isValid
            )
        }
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
            responseCount: SequentialOptotypeSession.requiredTargetCount,
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

    func testBlockGazeCoverageAcceptsMinorityNoiseAndRejectsMissingOrOffCentre() {
        let aligned = (0..<18).map { _ in sample(
            distance: 0.4, standardDeviation: 0.005, tracking: 0.99,
            stable: true, drift: 0.1, acceleration: 0.002,
            yaw: 0, pitch: 0, luminance: 0.5, faceCount: 1,
            gazeYaw: 2, gazePitch: 2
        ) }
        let noise = (0..<2).map { _ in sample(
            distance: 0.4, standardDeviation: 0.005, tracking: 0.99,
            stable: true, drift: 0.1, acceleration: 0.002,
            yaw: 0, pitch: 0, luminance: 0.5, faceCount: 1,
            gazeYaw: 15, gazePitch: 2
        ) }
        let accepted = BlockMeasurementQualityEngine.evaluate(
            samples: aligned + noise,
            targetDistanceMetres: 0.4,
            targetToleranceMetres: 0.06,
            thresholds: .conservative
        )
        XCTAssertTrue(accepted.isAccepted)

        let missing = aligned.map { value in sample(
            distance: value.correctedDistanceMetres ?? 0.4,
            standardDeviation: 0.005, tracking: 0.99, stable: true,
            drift: 0.1, acceleration: 0.002, yaw: 0, pitch: 0,
            luminance: 0.5, faceCount: 1, gazeYaw: nil, gazePitch: nil
        ) }
        XCTAssertTrue(BlockMeasurementQualityEngine.evaluate(
            samples: missing, targetDistanceMetres: 0.4,
            targetToleranceMetres: 0.06, thresholds: .conservative
        ).issues.contains(.gazeUnavailable))

        let offCentre = aligned.map { _ in sample(
            distance: 0.4, standardDeviation: 0.005, tracking: 0.99,
            stable: true, drift: 0.1, acceleration: 0.002,
            yaw: 0, pitch: 0, luminance: 0.5, faceCount: 1,
            gazeYaw: 14, gazePitch: 0
        ) }
        XCTAssertTrue(BlockMeasurementQualityEngine.evaluate(
            samples: offCentre, targetDistanceMetres: 0.4,
            targetToleranceMetres: 0.06, thresholds: .conservative
        ).issues.contains(.gazeOffCentre))
    }

    func testUnvalidatedProfileCannotUnlockNumericResults() {
        let result = EyeScreeningResult(
            eye: .right,
            status: .validEstimate,
            lastFailDiopter: -2,
            firstPassDiopter: -2.25,
            displayedEstimateDiopter: -2.25,
            thresholdDistanceMetres: 0.44,
            sensorUncertaintyDiopter: 0.05,
            repeatabilityDiopter: 0.05,
            trackingQuality: .good,
            responseConsistency: .good,
            warnings: []
        )
        let safe = NumericResultEligibility.sanitize(result, numericResultsAllowed: false)
        XCTAssertEqual(safe.status, .experimentalThresholdObserved)
        XCTAssertEqual(safe.recommendedAction, .professionalReviewRecommended)
        XCTAssertNil(safe.displayedEstimateDiopter)
        XCTAssertNil(safe.thresholdDistanceMetres)
        XCTAssertTrue(ResultIntegrityValidator.validate(safe).isValid)
    }

    func testNumericEligibilityCannotBeUnlockedWithoutAnApprovedProtocolRelease() {
        let profile = DeviceProfile(
            schemaVersion: 1,
            profileVersion: 2,
            hardwareIdentifiers: ["iPhone-test"],
            marketingFamily: "Test iPhone",
            variant: "Exact",
            nativePixelWidth: 1_200,
            nativePixelHeight: 2_600,
            displayScale: 3,
            pixelsPerInch: 460,
            expectedCameraType: .trueDepth,
            calibration: DistanceCalibration(
                scale: 1,
                offsetMetres: 0,
                baselineDistanceMetres: 0.40,
                validatedDistancesMetres: NumericResultEligibility.requiredCalibrationDistances
            ),
            qualityThresholds: .conservative,
            minimumValidatedDistance: 0.40,
            maximumValidatedDistance: 2.00,
            validationEvidence: ValidationSummary(
                sampleCount: 1_200,
                maximumMedianErrorBelowOneMetre: 0.02,
                maximumMedianPercentageErrorAtOrAboveOneMetre: 0.04,
                validatedAt: Date(),
                notes: "Test fixture"
            ),
            displayRasterValidation: DisplayRasterValidation(
                sampleCount: 100,
                nativePixelWidth: 1_200,
                nativePixelHeight: 2_600,
                displayScale: 3,
                pixelsPerInch: 460,
                validatedAt: Date(),
                notes: "Independent test fixture"
            ),
            clinicalValidationEvidence: ClinicalValidationEvidence(
                participantCount: 100,
                observationCount: 1_200,
                protocolIdentifier: "fixture-protocol",
                validatedAt: Date(),
                notes: "Independent test fixture"
            ),
            isValidated: true
        )

        let distanceOnly = DeviceProfile(
            schemaVersion: profile.schemaVersion,
            profileVersion: profile.profileVersion,
            hardwareIdentifiers: profile.hardwareIdentifiers,
            marketingFamily: profile.marketingFamily,
            variant: profile.variant,
            nativePixelWidth: profile.nativePixelWidth,
            nativePixelHeight: profile.nativePixelHeight,
            displayScale: profile.displayScale,
            pixelsPerInch: profile.pixelsPerInch,
            expectedCameraType: profile.expectedCameraType,
            calibration: profile.calibration,
            qualityThresholds: profile.qualityThresholds,
            minimumValidatedDistance: profile.minimumValidatedDistance,
            maximumValidatedDistance: profile.maximumValidatedDistance,
            validationEvidence: profile.validationEvidence,
            isValidated: true
        )
        XCTAssertFalse(NumericResultEligibility.allowsNumericResults(
            profile: distanceOnly,
            supportsSecondFaceDetection: true,
            matchesExactRuntimeDevice: true
        ))
        XCTAssertFalse(NumericResultEligibility.allowsNumericResults(
            profile: profile,
            supportsSecondFaceDetection: true,
            matchesExactRuntimeDevice: false
        ))
        XCTAssertFalse(NumericResultEligibility.allowsNumericResults(
            profile: profile,
            supportsSecondFaceDetection: false,
            matchesExactRuntimeDevice: true
        ))
        XCTAssertFalse(NumericResultEligibility.allowsNumericResults(
            profile: profile,
            supportsSecondFaceDetection: true,
            matchesExactRuntimeDevice: true
        ))
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
        var engine = ThresholdSearchEngine(
            eye: .right,
            protocolDescriptor: futureClinicalDescriptor
        )
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

    func testDebugDistanceOwnerRejectsStaleWriterAcrossRightAndLeftJourney() {
        var controller = ExclusiveDistanceTargetController()
        let rightOwner = controller.claim()
        XCTAssertTrue(controller.update(0.40, owner: rightOwner))
        XCTAssertEqual(controller.targetDistanceMetres, 0.40, accuracy: 0.000_1)
        XCTAssertTrue(controller.release(owner: rightOwner))

        let leftOwner = controller.claim()
        XCTAssertTrue(controller.update(0.40, owner: leftOwner))
        XCTAssertFalse(controller.update(1.33, owner: rightOwner))
        XCTAssertEqual(controller.targetDistanceMetres, 0.40, accuracy: 0.000_1)
        XCTAssertTrue(controller.update(0.80, owner: leftOwner))
        XCTAssertEqual(controller.targetDistanceMetres, 0.80, accuracy: 0.000_1)
        XCTAssertFalse(controller.release(owner: rightOwner))
        XCTAssertEqual(controller.owner, leftOwner)
    }

    func testOnlyFinishedSpeechMayAdvanceAndSensorEpochInvalidatesStaleWork() {
        XCTAssertTrue(SpeechProgressionPolicy.shouldAdvance(after: .finished))
        XCTAssertFalse(SpeechProgressionPolicy.shouldAdvance(after: .cancelled))
        XCTAssertFalse(SpeechProgressionPolicy.shouldAdvance(after: .failed))

        var epochs = SensorStreamEpochState()
        let activeBlockEpoch = epochs.epoch
        XCTAssertTrue(epochs.isCurrent(activeBlockEpoch))
        XCTAssertEqual(epochs.invalidate(), 1)
        XCTAssertFalse(epochs.isCurrent(activeBlockEpoch))
    }

    func testTrialGeometryFieldsRemainBackwardCodable() throws {
        let current = block(eye: .right, candidate: -2.5, distance: 0.4, outcome: .pass)
        let encoded = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in [
            "presentationDistanceMetres", "renderedPixelHeight", "renderedPointHeight",
            "renderedAngularSizeArcMinutes", "actualAngularSizeArcMinutes",
            "geometryDistanceDriftFraction", "presentedGeometry"
        ] {
            object.removeValue(forKey: key)
        }
        if var quality = object["quality"] as? [String: Any] {
            quality.removeValue(forKey: "gazeCoverage")
            object["quality"] = quality
        }

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TrialBlock.self, from: legacyData)
        XCTAssertNil(decoded.presentationDistanceMetres)
        XCTAssertNil(decoded.actualAngularSizeArcMinutes)
        XCTAssertNil(decoded.quality.gazeCoverage)
    }

    private func block(eye: Eye, candidate: Double, distance: Double, outcome: TrialOutcome) -> TrialBlock {
        let targets: [OptotypeDirection] = [.up, .right, .down, .left, .up, .right, .down, .left]
        let requiredCorrect = outcome == .pass ? 8 : outcome == .borderline ? 5 : 2
        let responses = targets.enumerated().map { index, target in
            index < requiredCorrect ? target : wrongDirection(for: target)
        }
        let targetDistance = 1 / abs(candidate)
        let presentation = PresentedOptotypeGeometry.calculate(
            distanceMetres: targetDistance,
            pixelsPerInch: 460,
            nativeScale: 3,
            presentationMode: .phonePOCLocator
        )!
        let actualAngle = presentation.computedArcMinutes(at: distance)!
        let renderedAngle = presentation.geometry.effectiveArcMinutes
        let drift = abs(actualAngle - renderedAngle) / renderedAngle
        return TrialBlock(
            eye: eye,
            candidateDiopter: candidate,
            targetDistanceMetres: targetDistance,
            actualMedianDistanceMetres: distance,
            distanceStandardDeviation: 0.008,
            targets: targets,
            responses: responses,
            correctCount: requiredCorrect,
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
            transcript: nil,
            presentationDistanceMetres: targetDistance,
            renderedPixelHeight: presentation.geometry.pixelHeight,
            renderedPointHeight: presentation.geometry.pointHeight,
            renderedAngularSizeArcMinutes: renderedAngle,
            actualAngularSizeArcMinutes: actualAngle,
            geometryDistanceDriftFraction: drift,
            presentedGeometry: presentation
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
            correctCount: SequentialOptotypeSession.requiredTargetCount,
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
        faceCount: Int,
        gazeYaw: Double? = 0,
        gazePitch: Double? = 0
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
            gazeYawErrorDegrees: gazeYaw,
            gazePitchErrorDegrees: gazePitch,
            luminance: luminance,
            faceCount: faceCount,
            interEyePixels: 200
        )
    }

    private func gaborTrial(
        contrast: Double,
        outcome: TrialOutcome,
        eye: Eye = .right
    ) -> GaborTrial {
        let targets: [GaborOrientation] = [.left, .right, .left, .right, .left, .right, .left, .right]
        let requiredCorrect = outcome == .pass ? 8 : outcome == .borderline ? 6 : 2
        let responses = targets.enumerated().map { index, target in
            index < requiredCorrect ? target : (target == .left ? .right : .left)
        }
        return GaborTrial(
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses,
            correctCount: requiredCorrect,
            outcome: outcome,
            responseSource: .voice,
            transcript: nil,
            presentationGeometry: GaborPresentationGeometry(
                pointDiameter: 360,
                displayScale: 3
            )!,
            quality: BlockQuality(
                trackingCoverage: 0.98,
                phoneStable: true,
                headPoseValid: true,
                distanceStable: true,
                audioLevelAdequate: true,
                targetGeometryValid: true,
                gazeCoverage: 0.98,
                discardReasons: []
            )
        )
    }

    private var futureClinicalDescriptor: LandoltProtocolDescriptor {
        LandoltProtocolDescriptor(
            identifier: "future-clinical-five-arcminute",
            version: 1,
            presentationMode: .clinicalFiveArcMinute,
            responsesPerLevel: SequentialOptotypeSession.requiredTargetCount,
            usesValidatedThresholdModel: true,
            permitsPointSizeClamping: false
        )
    }

    private func wrongDirection(for target: OptotypeDirection) -> OptotypeDirection {
        switch target {
        case .up: return .right
        case .right: return .down
        case .down: return .left
        case .left: return .up
        }
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

    private func attitude(rotationDegrees: Double) -> MotionAttitude {
        let halfAngle = rotationDegrees * .pi / 360
        return MotionAttitude(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
    }
}
