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

    var isStable: Bool {
        attitudeDriftDegrees < MotionStationarityEvaluator.maximumDriftDegrees
            && accelerationRMS < MotionStationarityEvaluator.maximumAccelerationRMS
            && rotationRateMagnitude < MotionStationarityEvaluator.maximumRotationRate
            && stableDuration >= MotionStationarityEvaluator.requiredStableDuration
    }

    static let unavailable = MotionStationarityReading(
        attitudeDriftDegrees: .infinity,
        accelerationRMS: .infinity,
        rotationRateMagnitude: .infinity,
        stableDuration: 0
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

    private let accelerationWindowSize = 12
    private var referenceAttitude: MotionAttitude?
    private var stableSince: TimeInterval?
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

        let accelerationRMS = sqrt(
            accelerationSquaredWindow.reduce(0, +) / Double(max(1, accelerationSquaredWindow.count))
        )
        var drift = Self.angularDifferenceDegrees(referenceAttitude, attitude)
        let motionIsQuiet = accelerationRMS < Self.maximumAccelerationRMS
            && rotationRateMagnitude < Self.maximumRotationRate

        if !referenceIsLocked,
           referenceAttitude == nil || !motionIsQuiet || drift >= Self.maximumDriftDegrees {
            // Placement movement is expected. Follow it until the phone becomes quiet,
            // then require a continuous stable interval from the new resting position.
            referenceAttitude = attitude
            stableSince = motionIsQuiet ? timestamp : nil
            drift = 0
        } else if motionIsQuiet && drift < Self.maximumDriftDegrees {
            stableSince = stableSince ?? timestamp
        } else {
            stableSince = nil
        }

        return MotionStationarityReading(
            attitudeDriftDegrees: drift,
            accelerationRMS: accelerationRMS,
            rotationRateMagnitude: rotationRateMagnitude,
            stableDuration: stableSince.map { max(0, timestamp - $0) } ?? 0
        )
    }

    mutating func lock(attitude: MotionAttitude?, timestamp: TimeInterval) {
        if let attitude { referenceAttitude = attitude }
        referenceIsLocked = true
        stableSince = timestamp
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
    }

    mutating func reset() {
        referenceAttitude = nil
        stableSince = nil
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
        referenceIsLocked = false
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
