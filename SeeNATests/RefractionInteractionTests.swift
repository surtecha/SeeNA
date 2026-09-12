import Foundation
import XCTest
@testable import SEENACore

final class RefractionInteractionTests: XCTestCase {
    func testOnlyIdleCanStartARecording() {
        XCTAssertTrue(RefractionVoiceState.idle.canStartListening)
        for state in [RefractionVoiceState.speaking, .listening, .processing] {
            XCTAssertFalse(state.canStartListening)
        }
    }

    func testProcessingIsVisibleAndHelperCanReplacePendingVoice() {
        XCTAssertEqual(RefractionVoiceState.processing.label, "Checking answer")
        XCTAssertTrue(RefractionVoiceState.processing.canAcceptHelperAnswer)
        XCTAssertTrue(RefractionVoiceState.listening.canAcceptHelperAnswer)
        XCTAssertTrue(RefractionVoiceState.idle.canAcceptHelperAnswer)
        XCTAssertFalse(RefractionVoiceState.speaking.canAcceptHelperAnswer)
    }

    // Wiring checks complement the pure state tests. These do not simulate a
    // microphone or claim physical-device voice verification.
    func testVoiceCancellationAndExitAreWiredToGenerationGuard() throws {
        let model = try source("SeeNA/Features/Refraction/RefractionViewModel.swift")
        let view = try source("SeeNA/Features/Refraction/RefractionFlowView.swift")
        XCTAssertTrue(model.contains("if token == generation { voiceState = .idle }"))
        XCTAssertTrue(model.contains("voiceState = .processing\n"))
        XCTAssertTrue(model.contains("guard phase == .answering, voiceState.canStartListening else"))
        XCTAssertTrue(view.contains("model.pauseForExit(using: dependencies); confirmExit = true"))
        XCTAssertTrue(view.contains(".disabled(!model.voiceState.canStartListening)"))
        XCTAssertTrue(view.contains(".disabled(model.saving)"))
        XCTAssertTrue(view.contains("Button(\"Keep measuring\")"))
    }

    func testHistoryDoesNotPresentEmptyStateDuringLoad() throws {
        let view = try source("SeeNA/Features/Refraction/RefractionResultsView.swift")
        XCTAssertTrue(view.contains("model.records.isEmpty, model.error == nil, !model.loading"))
        XCTAssertTrue(view.contains("ProgressView(\"Opening saved results\")"))
        XCTAssertTrue(view.contains("guard !loadInProgress, !deleting else"))
        XCTAssertTrue(view.contains("UIAccessibility.post(notification: .announcement"))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
