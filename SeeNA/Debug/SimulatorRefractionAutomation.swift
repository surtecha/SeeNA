#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Explicit simulator-only QA fixture. Never part of an iPhone/Release build.
/// Runs the real search, recording and history UI with synthetic measurements;
/// this is reproducible interaction evidence, not measured human refraction.
@MainActor
enum SimulatorRefractionAutomation {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-SEENA_AUTOMATE_REFRACTION")
    }

    static func response(model: RefractionViewModel) -> OptotypeResponse? {
        guard let target = model.currentTarget else { return nil }
        let syntheticThreshold = model.eye == .right ? -1.20 : -1.80
        return model.search.requestedDiopter <= syntheticThreshold ? OptotypeResponse(target) : .notVisible
    }

    static func drive(_ model: RefractionViewModel, dependencies: AppDependencies, displayScale: Double) async {
        guard enabled else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            switch model.phase {
            case .introduction, .answering: break
            case .calibration:
                // Synthetic ruler value is never used by the normal app.
                model.rulerMillimetres = "30"
                model.calibrate(displayScale: displayScale)
            case .positioning:
                model.distanceCentimetres = model.requestedCentimetres
                model.startLevel(using: dependencies)
            case .nextEye: model.nextEye()
            case .finished: return
            }
        }
    }
}
#endif
