import Foundation
import XCTest
@testable import SEENACore

final class VoiceCapturePolicyTests: XCTestCase {
    func testQuietNaturalAnswerIsAcceptedAndStopsAfterTrailingSilence() {
        var detector = VoiceActivityDetector()

        XCTAssertEqual(
            detector.observe(averagePowerDB: -74, peakPowerDB: -67, elapsed: 0),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -73, peakPowerDB: -66, elapsed: 0.1),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -59, peakPowerDB: -49, elapsed: 0.3),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -56, peakPowerDB: -46, elapsed: 0.4),
            .keepRecording
        )
        XCTAssertTrue(detector.capturedPlausibleSpeech)

        XCTAssertEqual(
            detector.observe(averagePowerDB: -74, peakPowerDB: -68, elapsed: 1.0),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -74, peakPowerDB: -68, elapsed: 1.2),
            .stop(.answerFinished)
        )
    }

    func testSingleSharpNoiseDoesNotBecomeAnAnswer() {
        var detector = VoiceActivityDetector()

        XCTAssertEqual(
            detector.observe(averagePowerDB: -28, peakPowerDB: -16, elapsed: 0.1),
            .keepRecording
        )
        XCTAssertFalse(detector.capturedPlausibleSpeech)
        XCTAssertEqual(
            detector.observe(averagePowerDB: -78, peakPowerDB: -72, elapsed: 0.5),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -78, peakPowerDB: -72, elapsed: 3.8),
            .stop(.noSpeech)
        )
        XCTAssertFalse(detector.capturedPlausibleSpeech)
    }

    func testSilenceReturnsNoSpeechWithinBoundedTime() {
        var detector = VoiceActivityDetector()

        for index in 0..<38 {
            XCTAssertEqual(
                detector.observe(
                    averagePowerDB: -80,
                    peakPowerDB: -75,
                    elapsed: Double(index) / 10
                ),
                .keepRecording
            )
        }
        XCTAssertEqual(
            detector.observe(averagePowerDB: -80, peakPowerDB: -75, elapsed: 3.8),
            .stop(.noSpeech)
        )
    }

    func testOngoingSoundCannotHoldRecorderForever() {
        var detector = VoiceActivityDetector()

        _ = detector.observe(averagePowerDB: -38, peakPowerDB: -25, elapsed: 0.1)
        _ = detector.observe(averagePowerDB: -37, peakPowerDB: -24, elapsed: 0.2)
        XCTAssertTrue(detector.capturedPlausibleSpeech)

        XCTAssertEqual(
            detector.observe(averagePowerDB: -37, peakPowerDB: -24, elapsed: 3.39),
            .keepRecording
        )
        XCTAssertEqual(
            detector.observe(averagePowerDB: -37, peakPowerDB: -24, elapsed: 3.41),
            .stop(.answerFinished)
        )
    }

    func testNonFiniteMeterValuesAreSafe() {
        var detector = VoiceActivityDetector()

        XCTAssertEqual(
            detector.observe(averagePowerDB: .nan, peakPowerDB: .infinity, elapsed: .nan),
            .keepRecording
        )
        XCTAssertFalse(detector.capturedPlausibleSpeech)
        XCTAssertTrue(detector.noiseFloorDB.isFinite)
    }

    func testTranscriptionBudgetCapsBothAttempts() {
        let policy = TranscriptionTransportPolicy.interactiveAnswer

        XCTAssertEqual(
            policy.timeoutNanoseconds(forAttempt: 0, elapsedNanoseconds: 0),
            7_000_000_000
        )
        XCTAssertEqual(
            policy.timeoutNanoseconds(forAttempt: 1, elapsedNanoseconds: 8_000_000_000),
            1_750_000_000
        )
        XCTAssertNil(
            policy.timeoutNanoseconds(forAttempt: 1, elapsedNanoseconds: 9_750_000_000)
        )
        XCTAssertNil(policy.timeoutNanoseconds(forAttempt: 2, elapsedNanoseconds: 0))
    }

    func testTranscriptionRetriesOnlyOnePlausiblyTransientFailure() {
        let policy = TranscriptionTransportPolicy.interactiveAnswer

        for status in [429, 502, 503, 504] {
            XCTAssertTrue(policy.shouldRetry(statusCode: status, completedAttempt: 0))
            XCTAssertFalse(policy.shouldRetry(statusCode: status, completedAttempt: 1))
        }
        for status in [400, 401, 404, 500] {
            XCTAssertFalse(policy.shouldRetry(statusCode: status, completedAttempt: 0))
        }

        for code in [
            URLError.Code.networkConnectionLost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ] {
            XCTAssertTrue(policy.shouldRetry(urlErrorCode: code, completedAttempt: 0))
            XCTAssertFalse(policy.shouldRetry(urlErrorCode: code, completedAttempt: 1))
        }
        for code in [URLError.Code.timedOut, .cancelled, .notConnectedToInternet] {
            XCTAssertFalse(policy.shouldRetry(urlErrorCode: code, completedAttempt: 0))
        }
    }

    func testRemoteSpeechAlwaysLeavesTimeForLocalFallback() {
        let policy = SpeechTransportPolicy.handsFreePrompt

        XCTAssertTrue(policy.preservesLocalFallback)
        XCTAssertEqual(policy.remoteAttemptTimeout, 2.75, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(policy.localFallbackBudget, 4)
        XCTAssertLessThan(policy.remoteAttemptTimeout, policy.transitionDeadline)
    }
}
