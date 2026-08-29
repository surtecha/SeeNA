import Foundation
import XCTest

final class AccessibilityLayoutRegressionTests: XCTestCase {
    func testPrimaryActionAndGaborLayoutRemainAdaptiveAtAccessibilitySizes() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: repository.appendingPathComponent("SeeNA/App/AppTheme.swift"))
        let gabor = try String(contentsOf: repository.appendingPathComponent("SeeNA/Features/EyeTest/GaborTestView.swift"))

        XCTAssertFalse(theme.contains(".frame(height: 54)"))
        XCTAssertTrue(theme.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(gabor.contains("ScrollView(showsIndicators: dynamicTypeSize.isAccessibilitySize)"))
        XCTAssertTrue(gabor.contains("max(180, available)"))
    }
}
