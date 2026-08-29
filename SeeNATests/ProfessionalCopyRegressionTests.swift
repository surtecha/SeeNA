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
            "ai does not create"
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
