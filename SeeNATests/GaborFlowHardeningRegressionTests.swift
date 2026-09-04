import Foundation
import XCTest

final class GaborFlowHardeningRegressionTests: XCTestCase {
    func testGaborFlowKeepsTheScoredPatchStableAndVoiceRecoveryHandsFree() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let view = try source(named: "SeeNA/Features/EyeTest/GaborTestView.swift")
        let renderer = try source(named: "SeeNA/Engines/GaborRenderer.swift")
        let domain = try source(named: "SeeNA/Models/DomainModels.swift")

        XCTAssertTrue(model.contains("targets = GaborTargetSequence.make()"))
        XCTAssertTrue(model.contains("phraseID: \"gabor-single\""))
        XCTAssertTrue(model.contains("eye pattern test complete."))
        XCTAssertFalse(model.contains("disposition.spokenMessage(for: eye)"))
        XCTAssertTrue(model.contains("speakLocallyForTransition(message)"))
        XCTAssertTrue(model.contains("currentPatchMatches(index: expectedIndex, target: expectedTarget)"))
        XCTAssertTrue(domain.contains("struct GaborPresentationGeometry: Codable"))
        XCTAssertTrue(model.contains("presentationGeometry: presentationGeometry"))
        XCTAssertTrue(model.contains("displayedGeometry == presentationGeometry"))
        XCTAssertFalse(model.contains("auditDescription"))
        XCTAssertFalse(model.contains("&& gazeState == .aligned"))
        XCTAssertFalse(model.contains("gazeState == .aligned,"))

        XCTAssertTrue(view.contains("let proposedTargetSize = max(180, available)"))
        XCTAssertFalse(view.contains("min(220, max(180, available))"))
        XCTAssertFalse(view.contains(".scale(scale: 0.94)"))

        XCTAssertTrue(renderer.contains("let size = geometry.rasterPixelDiameter"))
        XCTAssertTrue(renderer.contains("let imageScale = geometry.displayScale"))
        XCTAssertTrue(renderer.contains("shouldInterpolate: false"))
    }

    func testCancellingOperatorFallbackDoesNotRestartGaborVoiceCapture() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let dismissal = try section(
            in: model,
            from: "func operatorInputDidDismiss(",
            to: "func submitOperatorResponses("
        )
        let fallback = try section(
            in: String(dismissal),
            from: "if operatorModeRequested {",
            to: "guard sequentialSession?.currentTarget != nil"
        )

        XCTAssertTrue(fallback.contains("Microphone response is off"))
        XCTAssertTrue(fallback.contains("return"))
        XCTAssertFalse(fallback.contains("activeTask = Task"))
        XCTAssertFalse(fallback.contains("collectRequiredAnswers"))
        XCTAssertFalse(fallback.contains("restartPositioning"))

        let fallbackStart = try XCTUnwrap(dismissal.range(of: "if operatorModeRequested {")?.lowerBound)
        let voiceRestart = try XCTUnwrap(dismissal.range(of: "activeTask = Task")?.lowerBound)
        XCTAssertLessThan(fallbackStart, voiceRestart)
    }

    func testFirstGaborTargetWaitsForClearOrientationInstruction() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let view = try source(named: "SeeNA/Features/EyeTest/GaborTestView.swift")
        let block = try section(
            in: model,
            from: "private func runBlock(",
            to: "private func collectRequiredAnswers("
        )

        XCTAssertTrue(model.contains(
            "Stripes from upper left to lower right mean left. The other way means right."
        ))
        XCTAssertTrue(model.contains(
            "private static let responseInstruction = \"Say left, right, or I can’t see it.\""
        ))
        XCTAssertFalse(model.contains(
            "responseInstruction = \"\\(orientationInstruction)"
        ))
        XCTAssertTrue(block.contains("phase = .teaching"))
        XCTAssertTrue(block.contains("speakLocallyForTransition("))
        XCTAssertTrue(block.contains("Self.orientationInstructionTimeoutNanoseconds"))
        XCTAssertTrue(block.contains("SpeechProgressionPolicy.shouldAdvance(after: teachingOutcome)"))
        XCTAssertTrue(block.contains("SpokenTestCountdown.fromAcceptedPosition("))
        XCTAssertTrue(block.contains("hasExplainedOrientation = true"))
        XCTAssertTrue(view.contains("model.phase == .teaching"))
        XCTAssertTrue(view.contains("GaborTestViewModel.orientationInstruction"))
        XCTAssertTrue(view.contains("private var orientationTeaching: some View"))
        XCTAssertTrue(view.contains(".font(.system(.title2, design: .rounded, weight: .bold))"))
        XCTAssertTrue(view.contains(".accessibilityLabel("))

        let instruction = try XCTUnwrap(block.range(of: "phase = .teaching")?.lowerBound)
        let teachingSpeech = try XCTUnwrap(block.range(of: "speakLocallyForTransition(")?.lowerBound)
        let teachingAccepted = try XCTUnwrap(block.range(of: "hasExplainedOrientation = true")?.lowerBound)
        let countdown = try XCTUnwrap(block.range(of: "SpokenTestCountdown.fromAcceptedPosition(")?.lowerBound)
        let targetVisible = try XCTUnwrap(block.range(of: "isScoredTargetVisible = true")?.lowerBound)
        XCTAssertLessThan(instruction, teachingSpeech)
        XCTAssertLessThan(teachingSpeech, teachingAccepted)
        XCTAssertLessThan(teachingAccepted, countdown)
        XCTAssertLessThan(countdown, targetVisible)
    }

    func testOrientationTeachingHasASeparateExplicitDeadline() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")

        XCTAssertTrue(model.contains(
            "private static let orientationInstructionTimeoutNanoseconds: UInt64 = 10_000_000_000"
        ))
        XCTAssertTrue(model.contains(
            "timeoutNanoseconds: Self.orientationInstructionTimeoutNanoseconds"
        ))
    }

    func testRepeatNeededNeverAnnouncesCompletionOrAdvances() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let completion = try section(
            in: model,
            from: "private func complete(",
            to: "private func flowIsCurrent("
        )

        let repeatGate = try XCTUnwrap(
            completion.range(of: "guard disposition == .reliableCompletion else")?.lowerBound
        )
        let repeatSpeech = try XCTUnwrap(
            completion.range(of: "pattern task needs another try")?.lowerBound
        )
        let completionSpeech = try XCTUnwrap(
            completion.range(of: "eye pattern test complete")?.lowerBound
        )
        let navigation = try XCTUnwrap(completion.range(of: "session.navigate(to:")?.lowerBound)

        XCTAssertTrue(completion.contains("phase = disposition == .reliableCompletion ? .completed : .needsRepeat"))
        XCTAssertLessThan(repeatGate, repeatSpeech)
        XCTAssertLessThan(repeatSpeech, completionSpeech)
        XCTAssertLessThan(completionSpeech, navigation)
        XCTAssertTrue(String(completion[repeatGate..<completionSpeech]).contains("return"))
    }

    func testBothSubmissionPathsUseTheSameGatedCompletionHandler() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let voiceScoring = try section(
            in: model,
            from: "private func scoreBlock(",
            to: "private func restartPositioning("
        )
        let operatorScoring = try section(
            in: model,
            from: "func submitOperatorResponses(",
            to: "func sensorStreamInvalidated("
        )

        for path in [voiceScoring, operatorScoring] {
            XCTAssertTrue(path.contains("case .completed(let result):"))
            XCTAssertTrue(path.contains("await complete("))
            XCTAssertFalse(path.contains("session.navigate(to:"))
            XCTAssertFalse(path.contains("eye pattern test complete"))
        }
    }

    func testRepeatControlResetsCompletedEngineEvidenceAndPositioning() throws {
        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let view = try source(named: "SeeNA/Features/EyeTest/GaborTestView.swift")
        let repeatFlow = try section(
            in: model,
            from: "func repeatBlock(",
            to: "func cancel("
        )

        XCTAssertTrue(repeatFlow.contains("completionDisposition == .repeatNeeded"))
        XCTAssertTrue(repeatFlow.contains("engine = GaborContrastEngine(eye: eye)"))
        XCTAssertTrue(repeatFlow.contains("rightGaborTrials = []"))
        XCTAssertTrue(repeatFlow.contains("rightGaborResult = nil"))
        XCTAssertTrue(repeatFlow.contains("leftGaborTrials = []"))
        XCTAssertTrue(repeatFlow.contains("leftGaborResult = nil"))
        XCTAssertTrue(repeatFlow.contains("restartPositioning("))

        XCTAssertTrue(view.contains("if model.phase == .needsRepeat"))
        XCTAssertTrue(view.contains("Button(\"Repeat pattern task\")"))
        XCTAssertTrue(view.contains("await model.repeatBlock("))
        XCTAssertTrue(view.contains("Restarts positioning and repeats this eye's pattern task"))
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
