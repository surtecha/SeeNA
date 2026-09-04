import Foundation
import XCTest

final class AccessibleResultsInteractionRegressionTests: XCTestCase {
    func testBottomActionsBecomeScrollableAtAccessibilityTextSizes() throws {
        let theme = try source(named: "SeeNA/App/AppTheme.swift")
        let welcome = try source(named: "SeeNA/Features/Welcome/WelcomeView.swift")

        XCTAssertTrue(theme.contains("if dynamicTypeSize.isAccessibilitySize {\n                        actionPanel"))
        XCTAssertTrue(theme.contains("if !dynamicTypeSize.isAccessibilitySize {\n                actionPanel"))
        XCTAssertTrue(welcome.contains("if dynamicTypeSize.isAccessibilitySize {\n                            welcomeActions"))
        XCTAssertTrue(welcome.contains("if !dynamicTypeSize.isAccessibilitySize {\n                welcomeActions"))
        XCTAssertTrue(welcome.contains("ScrollView(showsIndicators: dynamicTypeSize.isAccessibilitySize)"))
    }

    func testResultsSpeakConciseSummaryAutomaticallyAndOfferExplicitPlaybackControls() throws {
        let results = try source(named: "SeeNA/Features/Results/ResultsViews.swift")
        let resultsView = try XCTUnwrap(
            results.slice(from: "struct ResultsView: View {", to: "@MainActor\n@Observable\nfinal class SessionHistoryViewModel")
        )

        XCTAssertTrue(resultsView.contains("await speakAndTrack(conciseSpokenSummary)"))
        XCTAssertFalse(resultsView.contains("await speakAndTrack(fullSpokenSummary)"))
        XCTAssertTrue(resultsView.contains("Label(\"Hear full result\""))
        XCTAssertTrue(resultsView.contains("Label(\"Repeat\""))
        XCTAssertTrue(resultsView.contains("Label(\"Stop voice\""))
        XCTAssertTrue(resultsView.contains("dependencies.spokenPrompts.stop()"))
        XCTAssertTrue(resultsView.contains("if UIAccessibility.isVoiceOverRunning"))
        XCTAssertTrue(resultsView.contains("startSpeech(fullSpokenSummary, allowsLongForm: true)"))
        XCTAssertTrue(resultsView.contains("speakLocallyAndWait(text)"))
    }

    func testHistoryErrorsAreVisibleInReadingOrderAndAnnounced() throws {
        let results = try source(named: "SeeNA/Features/Results/ResultsViews.swift")
        let historyView = try XCTUnwrap(results.slice(from: "struct SessionHistoryView: View {", to: "private struct SavedSessionDetailView"))

        XCTAssertTrue(historyView.contains("Section(\"Needs attention\")"))
        XCTAssertTrue(historyView.contains(".accessibilityLabel(\"History error."))
        XCTAssertTrue(historyView.contains(".onChange(of: model.errorMessage)"))
        XCTAssertTrue(historyView.contains("UIAccessibility.post(notification: .announcement"))
        XCTAssertFalse(historyView.contains(".overlay(alignment: .bottom)"))
    }

    func testEssentialSecondaryTextAndControlBordersUseHighContrastTokens() throws {
        let theme = try source(named: "SeeNA/App/AppTheme.swift")
        let secondaryOpacity = try opacity(named: "secondaryInk", in: theme)
        let controlBorderOpacity = try opacity(named: "controlBorder", in: theme)

        XCTAssertGreaterThanOrEqual(
            contrastRatioForBlack(opacity: secondaryOpacity, onWhite: true),
            4.5,
            "Secondary text must meet WCAG AA contrast for normal-sized text"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatioForBlack(opacity: controlBorderOpacity, onWhite: true),
            3.0,
            "Control boundaries must meet WCAG non-text contrast"
        )
        XCTAssertTrue(theme.contains("Capsule().stroke(SEENATheme.controlBorder"))
    }

    private func opacity(named token: String, in source: String) throws -> Double {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\s*=\\s*Color\\.black\\.opacity\\(([0-9.]+)\\)"
        let expression = try NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let match = try XCTUnwrap(expression.firstMatch(in: source, range: fullRange))
        let valueRange = try XCTUnwrap(Range(match.range(at: 1), in: source))
        return try XCTUnwrap(Double(source[valueRange]))
    }

    private func contrastRatioForBlack(opacity: Double, onWhite: Bool) -> Double {
        precondition(onWhite)
        let blendedSRGB = 1 - opacity
        let luminance = blendedSRGB <= 0.03928
            ? blendedSRGB / 12.92
            : pow((blendedSRGB + 0.055) / 1.055, 2.4)
        return 1.05 / (luminance + 0.05)
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
