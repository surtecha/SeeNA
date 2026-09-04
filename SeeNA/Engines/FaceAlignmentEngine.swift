import Foundation

struct GazeAlignment: Equatable, Sendable {
    let yawErrorDegrees: Double
    let pitchErrorDegrees: Double
}

enum FaceAlignmentPolicy {
    static let maximumMeasurementHeadAngleDegrees = 18.0
}

/// Readiness for the live positioning screens is based only on signals that
/// reliably describe the device and the person's physical position. ARKit gaze
/// remains visible coaching, but never blocks or resets an otherwise safe lock.
/// Recorded-block quality continues to validate gaze independently.
enum LivePositionReadinessPolicy {
    static let minimumLuminance = 0.12

    static func hasSingleFace(_ sample: DistanceSample?) -> Bool {
        sample?.faceCount == 1
    }

    static func isPhoneStable(_ sample: DistanceSample?) -> Bool {
        sample?.phoneStable == true
    }

    static func hasEnoughLight(_ sample: DistanceSample?) -> Bool {
        guard let luminance = sample?.luminance, luminance.isFinite else { return false }
        return luminance >= minimumLuminance
    }

    static func hasAcceptableHeadPose(_ sample: DistanceSample?) -> Bool {
        guard let sample,
              sample.headYawDegrees.isFinite,
              sample.headPitchDegrees.isFinite else {
            return false
        }
        return hasSingleFace(sample)
            && abs(sample.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && abs(sample.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
    }

    static func phoneSetupIsReady(_ sample: DistanceSample?) -> Bool {
        hasSingleFace(sample)
            && isPhoneStable(sample)
            && hasEnoughLight(sample)
    }

    static func calibrationTrackingIsReady(_ sample: DistanceSample?) -> Bool {
        isPhoneStable(sample)
            && hasAcceptableHeadPose(sample)
            && hasEnoughLight(sample)
    }
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

/// Gaze is useful as live alignment guidance, but ARKit's estimated look-at
/// point is not a clinical eye tracker. The aggregate measurement-quality gate
/// applies these strict thresholds to the recorded block. Live readiness uses
/// the tracker below so an unavailable or boundary-noisy gaze sample cannot
/// strand a person who is otherwise correctly positioned.
enum GazeReadinessPolicy {
    static let entryThresholdDegrees = 8.0
    static let exitThresholdDegrees = 11.0
    static let decisiveOffCentreThresholdDegrees = 12.0
    static let requiredBorderlineViolationSamples = 4
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
    private var consecutiveUnavailableSamples = 0
    private var consecutiveBorderlineViolations = 0

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
        switch state {
        case .unavailable:
            consecutiveUnavailableSamples += 1
            consecutiveBorderlineViolations = 0

            // Preserve an explicit startup state for the UI. After the sensor
            // has had one frame to initialise, unavailable gaze stays advisory
            // and does not block face, pose, light, motion, and distance checks.
            if wasAligned || consecutiveUnavailableSamples > 1 {
                wasAligned = true
                return .aligned
            }
            return .unavailable

        case .aligned:
            consecutiveUnavailableSamples = 0
            consecutiveBorderlineViolations = 0
            wasAligned = true
            return .aligned

        case .offCentre:
            consecutiveUnavailableSamples = 0
            let maximumError = max(
                abs(yawErrorDegrees ?? 0),
                abs(pitchErrorDegrees ?? 0)
            )
            if maximumError >= GazeReadinessPolicy.decisiveOffCentreThresholdDegrees {
                consecutiveBorderlineViolations = 0
                wasAligned = false
                return .offCentre
            }

            consecutiveBorderlineViolations += 1
            guard consecutiveBorderlineViolations
                    >= GazeReadinessPolicy.requiredBorderlineViolationSamples else {
                return .aligned
            }
            wasAligned = false
            return .offCentre
        }
    }

    mutating func reset() {
        wasAligned = false
        consecutiveUnavailableSamples = 0
        consecutiveBorderlineViolations = 0
    }
}
