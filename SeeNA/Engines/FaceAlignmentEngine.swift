import Foundation

struct GazeAlignment: Equatable, Sendable {
    let yawErrorDegrees: Double
    let pitchErrorDegrees: Double
}

enum FaceAlignmentPolicy {
    static let maximumMeasurementHeadAngleDegrees = 18.0
}

enum GazeAlignmentEngine {
    /// Compares ARKit's estimated eye-gaze ray with the ray from the eye centre
    /// to the TrueDepth camera. The result is advisory UI feedback, never a gate.
    static func errors(
        eyeX: Double,
        eyeY: Double,
        eyeZ: Double,
        lookX: Double,
        lookY: Double,
        lookZ: Double
    ) -> GazeAlignment? {
        let gaze = (x: lookX - eyeX, y: lookY - eyeY, z: lookZ - eyeZ)
        let camera = (x: -eyeX, y: -eyeY, z: -eyeZ)
        let gazeLength = sqrt(gaze.x * gaze.x + gaze.y * gaze.y + gaze.z * gaze.z)
        let cameraLength = sqrt(camera.x * camera.x + camera.y * camera.y + camera.z * camera.z)
        guard gazeLength > 0.000_1, cameraLength > 0.000_1 else { return nil }

        let dot = gaze.x * camera.x + gaze.y * camera.y + gaze.z * camera.z
        guard dot > 0 else { return nil }

        let gazeYaw = atan2(gaze.x, abs(gaze.z))
        let cameraYaw = atan2(camera.x, abs(camera.z))
        let gazePitch = atan2(gaze.y, abs(gaze.z))
        let cameraPitch = atan2(camera.y, abs(camera.z))
        return GazeAlignment(
            yawErrorDegrees: (gazeYaw - cameraYaw) * 180 / .pi,
            pitchErrorDegrees: (gazePitch - cameraPitch) * 180 / .pi
        )
    }
}

enum GazeReadiness: Equatable, Sendable {
    case unavailable
    case aligned
    case offCentre
}

/// Conservative POC gaze thresholds. These values are provisional and have
/// not been clinically validated. Hysteresis avoids flicker from normal gaze
/// noise while missing gaze always fails closed.
enum GazeReadinessPolicy {
    static let entryThresholdDegrees = 8.0
    static let exitThresholdDegrees = 11.0
    static let minimumBlockCoverage = 0.85

    static func classify(
        yawErrorDegrees: Double?,
        pitchErrorDegrees: Double?,
        thresholdDegrees: Double = entryThresholdDegrees
    ) -> GazeReadiness {
        guard let yawErrorDegrees, let pitchErrorDegrees,
              yawErrorDegrees.isFinite, pitchErrorDegrees.isFinite else {
            return .unavailable
        }
        return abs(yawErrorDegrees) <= thresholdDegrees
            && abs(pitchErrorDegrees) <= thresholdDegrees
            ? .aligned
            : .offCentre
    }
}

struct GazeReadinessTracker: Sendable {
    private var wasAligned = false

    mutating func update(
        yawErrorDegrees: Double?,
        pitchErrorDegrees: Double?
    ) -> GazeReadiness {
        let state = GazeReadinessPolicy.classify(
            yawErrorDegrees: yawErrorDegrees,
            pitchErrorDegrees: pitchErrorDegrees,
            thresholdDegrees: wasAligned
                ? GazeReadinessPolicy.exitThresholdDegrees
                : GazeReadinessPolicy.entryThresholdDegrees
        )
        wasAligned = state == .aligned
        return state
    }

    mutating func reset() {
        wasAligned = false
    }
}
