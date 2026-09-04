import Foundation
import XCTest

final class EligibilityAndAuditAccessibilityRegressionTests: XCTestCase {
    func testSafetyQuestionUsesOneSerialConstrainedVoiceCycle() throws {
        let eligibility = try source(named: "SeeNA/Features/Eligibility/EligibilityView.swift")
        let conversation = try XCTUnwrap(
            eligibility.slice(
                from: "func begin(session: AppSession, dependencies: AppDependencies) async {",
                to: "func answer(hasExclusion: Bool"
            )
        )

        XCTAssertTrue(conversation.contains("audioRecorder.requestPermission()"))
        XCTAssertTrue(conversation.contains("spokenPrompts.speakAndWait(prompt)"))
        XCTAssertTrue(conversation.contains("audioRecorder.record(maximumDuration: 8)"))
        XCTAssertTrue(conversation.contains("mode: .constrainedChoice"))
        XCTAssertTrue(conversation.contains("choiceSetID: \"eligibility\""))
        XCTAssertTrue(conversation.contains("needs microphone access. Tap Allow."))
        XCTAssertEqual(conversation.components(separatedBy: "spokenPrompts.speakAndWait(prompt)").count - 1, 1)

        let speech = try XCTUnwrap(conversation.range(of: "spokenPrompts.speakAndWait(prompt)"))
        let recording = try XCTUnwrap(conversation.range(of: "audioRecorder.record(maximumDuration: 8)"))
        XCTAssertLessThan(speech.lowerBound, recording.lowerBound, "Listening must not start before speech finishes")
    }

    func testSafetyAnswerSemanticsRetryAndCancellationStayFailSafe() throws {
        let eligibility = try source(named: "SeeNA/Features/Eligibility/EligibilityView.swift")

        XCTAssertTrue(eligibility.contains("response.choice == \"no\""))
        XCTAssertTrue(eligibility.contains("answer(hasExclusion: false"))
        XCTAssertTrue(eligibility.contains("response.choice == \"yes\""))
        XCTAssertTrue(eligibility.contains("answer(hasExclusion: true"))
        XCTAssertTrue(eligibility.contains("phase = .selectReason"))
        XCTAssertTrue(eligibility.contains("session.navigate(to: .permissions)"))
        XCTAssertTrue(eligibility.contains("prompt = retryQuestion"))
        XCTAssertTrue(eligibility.contains("failedAttempts < 2"))
        XCTAssertTrue(eligibility.contains("session.path.last == .eligibility"))
        XCTAssertTrue(eligibility.contains("conversationID = nil"))
        XCTAssertGreaterThanOrEqual(
            eligibility.components(separatedBy: "dependencies.audioRecorder.stop()").count - 1,
            3
        )
        XCTAssertTrue(eligibility.contains("Button(\"No, none apply\")"))
        XCTAssertTrue(eligibility.contains("Button(\"Yes, one applies\")"))
    }

    func testImportantSetupTextScalesWithoutChangingStimulusGeometry() throws {
        let welcome = try source(named: "SeeNA/Features/Welcome/WelcomeView.swift")
        let phoneSetup = try source(named: "SeeNA/Features/Setup/PhoneSetupView.swift")
        let calibration = try source(named: "SeeNA/Features/Calibration/BaselineCalibrationView.swift")

        XCTAssertTrue(welcome.contains("@ScaledMetric(relativeTo: .largeTitle) private var brandSize"))
        XCTAssertFalse(welcome.contains(".font(.system(size: 58"))
        XCTAssertTrue(phoneSetup.contains("@ScaledMetric(relativeTo: .title) private var distanceTextSize"))
        XCTAssertFalse(phoneSetup.contains(".font(.system(size: 30"))
        XCTAssertTrue(calibration.contains("@ScaledMetric(relativeTo: .largeTitle) private var distanceTextSize"))
        XCTAssertFalse(calibration.contains(".font(.system(size: 42"))

        XCTAssertTrue(phoneSetup.contains(".frame(width: 172, height: 172)"))
        XCTAssertTrue(calibration.contains(".frame(width: 214, height: 214)"))
        XCTAssertTrue(phoneSetup.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(calibration.contains("dynamicTypeSize.isAccessibilitySize"))
    }

    func testAnswerAuditShowsOnlyAnswersAndScores() throws {
        let audit = try source(named: "SeeNA/Features/Results/ResultsAnswerAuditView.swift")
        let components = try source(named: "SeeNA/Features/Results/ResultsAnswerAuditComponents.swift")

        XCTAssertTrue(audit.contains("\\(block.correctCount)/\\(block.targets.count) correct"))
        XCTAssertFalse(audit.localizedCaseInsensitiveContains("arcmin"))
        XCTAssertFalse(audit.localizedCaseInsensitiveContains("actualMedianDistance"))
        XCTAssertFalse(audit.localizedCaseInsensitiveContains("geometryDistanceDrift"))
        XCTAssertFalse(audit.localizedCaseInsensitiveContains("requested/computed"))
        XCTAssertTrue(components.contains("Correct answer"))
        XCTAssertTrue(components.contains("Accepted answer"))
        XCTAssertTrue(components.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertFalse(components.contains("Your answer"))
    }

    private func source(named path: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex) else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
