import XCTest
@testable import SEENACore

final class SceneLifecycleCoordinatorRegressionTests: XCTestCase {
    func testInactiveThenBackgroundProducesOnlyOneSuspension() {
        var lifecycle = SceneLifecycleCoordinator()

        XCTAssertTrue(lifecycle.beginSuspension())
        XCTAssertFalse(lifecycle.beginSuspension())
        XCTAssertTrue(lifecycle.isSuspended)
    }

    func testActiveWithoutSuspensionDoesNothing() {
        var lifecycle = SceneLifecycleCoordinator()

        XCTAssertNil(
            lifecycle.consumeResumePlan(
                requiresLiveSensors: true,
                requiresScreeningBrightness: true
            )
        )
    }

    func testResumeRestoresResourcesForCurrentLiveRouteExactlyOnce() {
        var lifecycle = SceneLifecycleCoordinator()
        XCTAssertTrue(lifecycle.beginSuspension())

        let plan = lifecycle.consumeResumePlan(
            requiresLiveSensors: true,
            requiresScreeningBrightness: true
        )

        XCTAssertEqual(
            plan,
            SceneResumePlan(
                resumesLiveSensors: true,
                restoresScreeningBrightness: true
            )
        )
        XCTAssertNil(
            lifecycle.consumeResumePlan(
                requiresLiveSensors: true,
                requiresScreeningBrightness: true
            )
        )
    }

    func testRouteChangedWhileSuspendedDoesNotRestoreCaptureResources() {
        var lifecycle = SceneLifecycleCoordinator()
        XCTAssertTrue(lifecycle.beginSuspension())

        XCTAssertEqual(
            lifecycle.consumeResumePlan(
                requiresLiveSensors: false,
                requiresScreeningBrightness: false
            ),
            SceneResumePlan(
                resumesLiveSensors: false,
                restoresScreeningBrightness: false
            )
        )
    }
}
