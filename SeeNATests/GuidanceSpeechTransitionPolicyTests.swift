import XCTest
@testable import SEENACore

final class GuidanceSpeechTransitionPolicyTests: XCTestCase {
    func testAcceptedPositionInterruptsOnlyMovementGuidance() {
        XCTAssertTrue(GuidanceSpeechTransitionPolicy.shouldInterruptForAcceptedPosition(
            activeRequestKind: .guidanceIntro,
            navigationFinishedVeryRecently: false
        ))
        XCTAssertTrue(GuidanceSpeechTransitionPolicy.shouldInterruptForAcceptedPosition(
            activeRequestKind: .navigation,
            navigationFinishedVeryRecently: false
        ))
        XCTAssertFalse(GuidanceSpeechTransitionPolicy.shouldInterruptForAcceptedPosition(
            activeRequestKind: .prompt,
            navigationFinishedVeryRecently: false
        ))
    }

    func testAcceptedPositionClearsRecentNavigationHandoffButNotIdleChannel() {
        XCTAssertTrue(GuidanceSpeechTransitionPolicy.shouldInterruptForAcceptedPosition(
            activeRequestKind: nil,
            navigationFinishedVeryRecently: true
        ))
        XCTAssertFalse(GuidanceSpeechTransitionPolicy.shouldInterruptForAcceptedPosition(
            activeRequestKind: nil,
            navigationFinishedVeryRecently: false
        ))
    }
}
