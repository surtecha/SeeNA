import Foundation
import XCTest

final class ProfessionalCopyRegressionTests: XCTestCase {
    func testNormalJourneyCopyContainsNoInternalEngineeringLanguage() throws {
        let source = try normalJourneySource()
        let disallowed = [
            "research prototype",
            "research poc",
            "experimental poc",
            "poc screening",
            "poc sensor profile",
            "numeric result disabled",
            "physical calibration tool",
            "tape-measure",
            "tape measure",
            "calibration is not",
            "validation is not",
            "numeric verification",
            "unvalidated device",
            "ai does not create",
            "orientation task",
            "task performance",
            "evidence review required",
            "internal consistency checks",
            "numeric comparison"
        ]

        for phrase in disallowed {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(phrase), "Normal journey exposes internal copy: \(phrase)")
        }
    }

    func testProfessionalSafetyFooterIsRetained() throws {
        let theme = try source(named: "SeeNA/App/AppTheme.swift")
        XCTAssertTrue(theme.localizedCaseInsensitiveContains("vision screening · not a prescription"))
        XCTAssertFalse(theme.localizedCaseInsensitiveContains("research prototype"))
    }

    func testResultSurfaceUsesPlainTaskLanguage() throws {
        let results = try [
            source(named: "SeeNA/Features/Results/ResultsViews.swift"),
            source(named: "SeeNA/Features/Results/ResultSummaryComponents.swift")
        ].joined(separator: "\n")

        XCTAssertTrue(results.contains("Your answers were recorded for both eyes."))
        XCTAssertTrue(results.contains("Continue routine eye checks with an eye care professional."))
        XCTAssertTrue(results.contains("Circle task"))
        XCTAssertTrue(results.contains("Pattern task"))
        XCTAssertFalse(results.localizedCaseInsensitiveContains("cannot support a numeric comparison"))
        XCTAssertFalse(results.localizedCaseInsensitiveContains("evidence review required"))
        XCTAssertFalse(results.localizedCaseInsensitiveContains("orientation task complete"))
    }

    func testActiveGaborCopyDescribesOneSimplePatternTask() throws {
        let combinedSource = try [
            source(named: "SeeNA/Engines/GaborContrastEngine.swift"),
            source(named: "SeeNA/Features/EyeTest/GaborTestView.swift"),
            source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        ].joined(separator: "\n")

        XCTAssertTrue(combinedSource.contains("PATTERN TASK"))
        XCTAssertTrue(combinedSource.contains("TASK COMPLETE"))
        for staleCopy in [
            "PATTERN LEVEL",
            "Preparing the next pattern level",
            "ORIENTATION TASK COMPLETE",
            "non-clinical Gabor orientation task complete",
            "Finished, but this orientation task needs repeating"
        ] {
            XCTAssertFalse(
                combinedSource.localizedCaseInsensitiveContains(staleCopy),
                "Single-block Gabor flow exposes stale copy: \(staleCopy)"
            )
        }

        let model = try source(named: "SeeNA/Features/EyeTest/GaborTestViewModel.swift")
        let engine = try source(named: "SeeNA/Engines/ThresholdSearchEngine.swift")
        XCTAssertTrue(model.contains("let targetDistance = 0.40"))
        XCTAssertFalse(model.localizedCaseInsensitiveContains("eighty centimetres"))
        XCTAssertTrue(engine.contains("maximumActivePhoneLocatorDistanceMetres = 0.40"))
    }

    func testCalibrationHarnessHasNoReleaseJourneyEntryPoint() throws {
        let deviceCheck = try source(named: "SeeNA/Features/Setup/DeviceCheckView.swift")
        let harness = try source(named: "SeeNA/Features/Calibration/DeviceCalibrationHarnessView.swift")

        XCTAssertFalse(deviceCheck.contains("DeviceCalibrationHarnessView"))
        XCTAssertTrue(harness.hasPrefix("#if DEBUG"))
        XCTAssertTrue(harness.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("#endif"))
    }

    private func normalJourneySource() throws -> String {
        try [
            "SeeNA/App/AppTheme.swift",
            "SeeNA/App/AppSession.swift",
            "SeeNA/Features/Setup/DeviceCheckView.swift",
            "SeeNA/Features/CoreJourneyViewModels.swift",
            "SeeNA/Features/Welcome/WelcomeView.swift",
            "SeeNA/Features/Eligibility/EligibilityView.swift",
            "SeeNA/Features/EyeTest/EyeTestStageViews.swift",
            "SeeNA/Features/EyeTest/GaborTestView.swift",
            "SeeNA/Features/Results/ResultsViews.swift",
            "SeeNA/Features/Results/ResultSummaryComponents.swift",
            "SeeNA/Features/Results/ResultVerificationBadge.swift",
            "SeeNA/Features/Results/ResultsAnswerAuditView.swift",
            "SeeNA/Features/Evidence/EvidenceView.swift",
            "SeeNA/Engines/ResultsPresentationPolicy.swift"
        ]
        .map(source(named:))
        .joined(separator: "\n")
    }

    private func source(named path: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }
}
