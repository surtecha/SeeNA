import Foundation
import XCTest

final class LandoltHandsFreeFlowRegressionTests: XCTestCase {
    func testGazeRemainsCoachingInsteadOfAStartOrCountdownGate() throws {
        let source = try eyeTestViewModelSource()
        let readiness = try section(
            in: source,
            from: "let validPose = sample.map",
            to: "let timestamp ="
        )
        let countdownGate = try section(
            in: source,
            from: "private func positionIsAcceptable()",
            to: "private func announce("
        )

        XCTAssertFalse(readiness.contains("gazeState == .aligned"))
        XCTAssertFalse(countdownGate.contains("gazeState == .aligned"))
        XCTAssertTrue(countdownGate.contains("abs(currentDistance - targetDistance)"))
        XCTAssertTrue(countdownGate.contains("DistanceGuidanceEngine.exitTolerance"))
        XCTAssertTrue(source.contains("if gazeState != .aligned { return .lookAtCentre }"))
    }

    func testVoiceFailuresRetryTheSameTargetHandsFree() throws {
        let source = try eyeTestViewModelSource()
        let collection = try section(
            in: source,
            from: "private func collectSequentialAnswers(",
            to: "private enum SingleAnswerCapture"
        )

        XCTAssertTrue(source.contains("speakLocallyForTransition(spokenPrompt)"))
        XCTAssertTrue(source.contains("I missed that. Same circle. Please answer again."))
        XCTAssertTrue(source.contains("sequentialSession?.currentIndex == activeSession.currentIndex"))
        XCTAssertFalse(source.contains("if operatorModeRequested || !dependencies.network.isConnected"))
        XCTAssertTrue(collection.contains("var consecutiveVoiceFailureCount = 0"))
        XCTAssertTrue(collection.contains("consecutiveVoiceFailureCount = 0"))
        XCTAssertTrue(collection.contains("consecutiveVoiceFailureCount += 1"))
    }

    func testPersistentOfflineVoiceEntersStickyOperatorFallback() throws {
        let source = try eyeTestViewModelSource()
        let blockStart = try section(
            in: source,
            from: "private func runVoiceBlock(",
            to: "private func collectSequentialAnswers("
        )
        let collection = try section(
            in: source,
            from: "private func collectSequentialAnswers(",
            to: "private enum SingleAnswerCapture"
        )

        XCTAssertTrue(blockStart.contains("if !dependencies.network.isConnected"))
        XCTAssertTrue(blockStart.contains("waitForVoiceConnection"))
        XCTAssertTrue(blockStart.contains("operatorModeRequested = true"))
        XCTAssertTrue(blockStart.contains("Voice is offline"))
        XCTAssertTrue(collection.contains("Self.maximumAutomaticVoiceFailureCount"))
        XCTAssertTrue(collection.contains("|| !dependencies.network.isConnected"))
        XCTAssertTrue(collection.contains("operatorModeRequested = true"))
        XCTAssertTrue(collection.contains("Voice is unavailable"))
        XCTAssertTrue(collection.contains("RecordingError.permissionDenied"))
        XCTAssertTrue(collection.contains("session.responseMode = .operatorOnly"))
    }

    func testLandoltTranscriptionAndDirectionSequenceStayConstrained() throws {
        let modelSource = try eyeTestViewModelSource()
        let sequence = try source(named: "SeeNA/Engines/SequentialOptotypeSession.swift")

        XCTAssertTrue(modelSource.contains("phraseID: \"landolt-single\""))
        XCTAssertTrue(modelSource.contains("Self.isNotVisibleChoice(response.choice)"))
        XCTAssertTrue(modelSource.contains("let directions = LandoltTargetSequence.make()"))
        XCTAssertTrue(sequence.contains("Array(repeating: direction, count: 2)"))
        XCTAssertTrue(sequence.contains("isValidTargetSequence(shuffled)"))
        XCTAssertFalse(modelSource.contains("Self.randomDirections()"))
    }

    func testGuidanceUsesTheLastRealFilteredDistance() throws {
        let source = try eyeTestViewModelSource()

        XCTAssertTrue(source.contains("lastFilteredDistance = currentDistance"))
        XCTAssertTrue(source.contains("let guidanceDistance = currentDistance ?? lastFilteredDistance"))
        XCTAssertFalse(source.contains("The test row is no longer active"))
        XCTAssertFalse(source.contains("repeat the row"))
    }

    func testCancellingOperatorFallbackDoesNotRestartLandoltVoiceCapture() throws {
        let source = try eyeTestViewModelSource()
        let dismissal = try section(
            in: source,
            from: "func operatorInputDidDismiss(",
            to: "func submitOperatorResponses("
        )
        let fallback = try section(
            in: String(dismissal),
            from: "if operatorModeRequested {",
            to: "guard candidate != nil"
        )

        XCTAssertTrue(fallback.contains("Microphone response is off"))
        XCTAssertTrue(fallback.contains("return"))
        XCTAssertFalse(fallback.contains("launchVoiceFlow"))
        XCTAssertFalse(fallback.contains("announceGuidance"))

        let fallbackStart = try XCTUnwrap(dismissal.range(of: "if operatorModeRequested {")?.lowerBound)
        let voiceRestart = try XCTUnwrap(dismissal.range(of: "launchVoiceFlow(")?.lowerBound)
        XCTAssertLessThan(fallbackStart, voiceRestart)

        let manualRetry = try section(
            in: source,
            from: "func repeatVoice(",
            to: "private func resumeVoiceBlock("
        )
        XCTAssertTrue(source.contains("if operatorModeRequested { return \"Open helper controls\" }"))
        XCTAssertTrue(manualRetry.contains("if operatorModeRequested"))
        XCTAssertTrue(manualRetry.contains("presentOperatorInput(using: dependencies)"))
    }

    private func eyeTestViewModelSource() throws -> String {
        try source(named: "SeeNA/Features/EyeTest/EyeTestViewModel.swift")
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
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
