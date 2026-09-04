import Foundation

struct MotionAttitude: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

struct MotionStationarityReading: Equatable, Sendable {
    let attitudeDriftDegrees: Double
    let accelerationRMS: Double
    let rotationRateMagnitude: Double
    let stableDuration: TimeInterval
    let isStable: Bool

    static let unavailable = MotionStationarityReading(
        attitudeDriftDegrees: .infinity,
        accelerationRMS: .infinity,
        rotationRateMagnitude: .infinity,
        stableDuration: 0,
        isStable: false
    )
}

/// Establishes a fresh quiet reference while the phone is being positioned, then
/// preserves the final reference after setup so later movement cannot be hidden by
/// automatic re-basing.
struct MotionStationarityEvaluator: Sendable {
    static let maximumDriftDegrees = 1.5
    static let maximumAccelerationRMS = 0.02
    static let maximumRotationRate = 0.08
    static let requiredStableDuration: TimeInterval = 0.6
    static let transientViolationGrace: TimeInterval = 0.25

    private let accelerationWindowSize = 12
    private var referenceAttitude: MotionAttitude?
    private var stableDuration: TimeInterval = 0
    private var lastTimestamp: TimeInterval?
    private var violationSince: TimeInterval?
    private var accelerationSquaredWindow: [Double] = []
    private var referenceIsLocked = false

    mutating func consume(
        attitude: MotionAttitude,
        accelerationSquared: Double,
        rotationRateMagnitude: Double,
        timestamp: TimeInterval
    ) -> MotionStationarityReading {
        accelerationSquaredWindow.append(max(0, accelerationSquared))
        if accelerationSquaredWindow.count > accelerationWindowSize {
            accelerationSquaredWindow.removeFirst(accelerationSquaredWindow.count - accelerationWindowSize)
        }

        let accelerationRMS = Self.robustAccelerationRMS(accelerationSquaredWindow)
        var drift = Self.angularDifferenceDegrees(referenceAttitude, attitude)
        let dynamicsAreQuiet = accelerationRMS < Self.maximumAccelerationRMS
            && rotationRateMagnitude < Self.maximumRotationRate
        let frameDuration = min(0.20, max(0, timestamp - (lastTimestamp ?? timestamp)))
        lastTimestamp = timestamp

        if referenceAttitude == nil {
            referenceAttitude = attitude
            drift = 0
            if dynamicsAreQuiet {
                stableDuration += frameDuration
            }
        } else {
            let sampleIsWithinLimits = dynamicsAreQuiet && drift < Self.maximumDriftDegrees
            if sampleIsWithinLimits {
                violationSince = nil
                stableDuration += frameDuration
            } else {
                violationSince = violationSince ?? timestamp
                let violationDuration = max(0, timestamp - (violationSince ?? timestamp))
                if violationDuration >= Self.transientViolationGrace {
                    stableDuration = 0
                    if !referenceIsLocked {
                        // Placement movement is expected. Rebase only after it
                        // persists, so one noisy frame cannot erase a valid hold.
                        referenceAttitude = attitude
                        drift = 0
                        if dynamicsAreQuiet {
                            violationSince = nil
                        } else {
                            violationSince = timestamp
                        }
                    }
                }
            }
        }

        let violationDuration = violationSince.map { max(0, timestamp - $0) } ?? 0
        let violationIsConfirmed = violationSince != nil
            && violationDuration >= Self.transientViolationGrace
        let isStable = stableDuration >= Self.requiredStableDuration && !violationIsConfirmed

        return MotionStationarityReading(
            attitudeDriftDegrees: drift,
            accelerationRMS: accelerationRMS,
            rotationRateMagnitude: rotationRateMagnitude,
            stableDuration: stableDuration,
            isStable: isStable
        )
    }

    mutating func lock(attitude: MotionAttitude?, timestamp: TimeInterval) {
        if let attitude { referenceAttitude = attitude }
        referenceIsLocked = true
        stableDuration = 0
        lastTimestamp = timestamp
        violationSince = nil
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
    }

    mutating func reset() {
        referenceAttitude = nil
        stableDuration = 0
        lastTimestamp = nil
        violationSince = nil
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
        referenceIsLocked = false
    }

    /// Ignores at most two isolated impulse samples while retaining RMS
    /// sensitivity to sustained movement. This avoids a sensor spike producing
    /// an audible failure, without allowing real handling or vibration through.
    private static func robustAccelerationRMS(_ squaredValues: [Double]) -> Double {
        guard !squaredValues.isEmpty else { return .infinity }
        let sorted = squaredValues.sorted()
        let trimCount: Int
        if sorted.count >= 10 {
            trimCount = 2
        } else if sorted.count >= 5 {
            trimCount = 1
        } else {
            trimCount = 0
        }
        let retained = sorted.dropLast(trimCount)
        return sqrt(retained.reduce(0, +) / Double(max(1, retained.count)))
    }

    private static func angularDifferenceDegrees(
        _ lhs: MotionAttitude?,
        _ rhs: MotionAttitude
    ) -> Double {
        guard let lhs else { return .infinity }
        let dot = abs(lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z + lhs.w * rhs.w)
        return 2 * acos(min(1, max(-1, dot))) * 180 / .pi
    }
}
