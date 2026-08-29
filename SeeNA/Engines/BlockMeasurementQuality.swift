import Foundation

enum BlockMeasurementIssue: String, Codable, Hashable, Sendable {
    case insufficientSamples
    case distanceUnavailable
    case distanceOffTarget
    case distanceUnstable
    case trackingUnreliable
    case phoneMoved
    case headPose
    case poorLighting
    case multipleFaces
}

/// A block-level view of the sensor stream captured while a participant sees
/// and answers one visual row. Unlike a last-frame check, this tolerates an
/// occasional noisy frame while rejecting conditions that persist long enough
/// to make the response unreliable.
struct BlockMeasurementQuality: Equatable, Sendable {
    let sampleCount: Int
    let validDistanceSampleCount: Int
    let medianDistanceMetres: Double?
    let distanceStandardDeviationMetres: Double?
    let distanceCoverage: Double
    let targetDistanceCoverage: Double
    let trackingCoverage: Double
    let phoneStableCoverage: Double
    let headPoseCoverage: Double
    let lightingCoverage: Double
    let singleFaceCoverage: Double
    let issues: [BlockMeasurementIssue]

    var isAccepted: Bool { issues.isEmpty }

    /// Maps aggregate sensor failures onto the app's existing persisted quality
    /// reasons. Sample-count and target-distance failures are deliberately
    /// represented as distance instability because that is the actionable retry.
    var blockDiscardReasons: [BlockDiscardReason] {
        let mapped = issues.map { issue -> BlockDiscardReason in
            switch issue {
            case .insufficientSamples, .distanceUnavailable, .distanceOffTarget, .distanceUnstable:
                return .distanceUnstable
            case .trackingUnreliable:
                return .trackingCoverage
            case .phoneMoved:
                return .phoneMoved
            case .headPose:
                return .headPose
            case .poorLighting:
                return .poorLighting
            case .multipleFaces:
                return .multipleFaces
            }
        }
        return Array(Set(mapped)).sorted { $0.rawValue < $1.rawValue }
    }
}

enum BlockMeasurementQualityEngine {
    static func evaluate(
        samples: [DistanceSample],
        targetDistanceMetres: Double,
        targetToleranceMetres: Double,
        thresholds: QualityThresholds,
        minimumSampleCount: Int = 12,
        minimumConditionCoverage: Double = 0.90
    ) -> BlockMeasurementQuality {
        let requiredSamples = max(1, minimumSampleCount)
        let requiredCoverage = min(max(minimumConditionCoverage, 0), 1)
        let validTarget = targetDistanceMetres.isFinite && targetDistanceMetres > 0
        let tolerance = max(0, targetToleranceMetres)
        let count = samples.count

        let distances = samples.compactMap(Self.distance(from:))
        let robustDistances = robustValues(distances)
        let medianDistance = Statistics.median(robustDistances)
        let distanceSD = Statistics.standardDeviation(robustDistances)

        let distanceCoverage = coverage(distances.count, outOf: count)
        let targetDistanceCount = validTarget
            ? distances.filter { abs($0 - targetDistanceMetres) <= tolerance }.count
            : 0
        let targetDistanceCoverage = coverage(targetDistanceCount, outOf: count)
        let trackingCoverage = count == 0 ? 0 : samples.reduce(0) {
            $0 + min(max($1.trackingCoverage, 0), 1)
        } / Double(count)
        let phoneStableCoverage = coverage(samples.filter {
            $0.phoneStable
                && $0.attitudeDriftDegrees <= thresholds.maximumAttitudeDriftDegrees
                && $0.accelerationRMS <= thresholds.maximumAccelerationRMS
        }.count, outOf: count)
        let headPoseCoverage = coverage(samples.filter {
            abs($0.headYawDegrees) <= thresholds.maximumHeadYawDegrees
                && abs($0.headPitchDegrees) <= thresholds.maximumHeadPitchDegrees
        }.count, outOf: count)
        let lightingCoverage = coverage(samples.filter { $0.luminance >= 0.12 }.count, outOf: count)
        let singleFaceCoverage = coverage(samples.filter { $0.faceCount == 1 }.count, outOf: count)

        var issues: [BlockMeasurementIssue] = []
        if count < requiredSamples { issues.append(.insufficientSamples) }
        if distanceCoverage < requiredCoverage || medianDistance == nil { issues.append(.distanceUnavailable) }
        if !validTarget
            || medianDistance.map({ abs($0 - targetDistanceMetres) > tolerance }) != false
            || targetDistanceCoverage < requiredCoverage {
            issues.append(.distanceOffTarget)
        }
        let maximumDistanceSD = targetDistanceMetres < 1
            ? thresholds.maximumDistanceSDNearMetres
            : thresholds.maximumDistanceSDFarMetres
        if distanceSD.map({ $0 > maximumDistanceSD }) != false { issues.append(.distanceUnstable) }
        if trackingCoverage < thresholds.minimumTrackingCoverage { issues.append(.trackingUnreliable) }
        if phoneStableCoverage < requiredCoverage { issues.append(.phoneMoved) }
        if headPoseCoverage < requiredCoverage { issues.append(.headPose) }
        if lightingCoverage < requiredCoverage { issues.append(.poorLighting) }
        if singleFaceCoverage < requiredCoverage { issues.append(.multipleFaces) }

        return BlockMeasurementQuality(
            sampleCount: count,
            validDistanceSampleCount: distances.count,
            medianDistanceMetres: medianDistance,
            distanceStandardDeviationMetres: distanceSD,
            distanceCoverage: distanceCoverage,
            targetDistanceCoverage: targetDistanceCoverage,
            trackingCoverage: trackingCoverage,
            phoneStableCoverage: phoneStableCoverage,
            headPoseCoverage: headPoseCoverage,
            lightingCoverage: lightingCoverage,
            singleFaceCoverage: singleFaceCoverage,
            issues: Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func distance(from sample: DistanceSample) -> Double? {
        let value = sample.correctedDistanceMetres
            ?? sample.fusedDistanceMetres
            ?? sample.rawARDistanceMetres
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Median absolute deviation keeps isolated AR jumps from inflating the
    /// block's spread. The small absolute fallback handles the common case in
    /// which most readings are identical and MAD is therefore zero.
    private static func robustValues(_ values: [Double]) -> [Double] {
        guard values.count >= 3, let centre = Statistics.median(values) else { return values }
        let deviations = values.map { abs($0 - centre) }
        guard let mad = Statistics.median(deviations) else { return values }
        let limit = mad > 0
            ? max(3.5 * 1.4826 * mad, 0.005)
            : max(0.005, abs(centre) * 0.005)
        let filtered = values.filter { abs($0 - centre) <= limit }
        return filtered.count >= max(2, Int(ceil(Double(values.count) * 0.70)))
            ? filtered
            : values
    }

    private static func coverage(_ validCount: Int, outOf totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(validCount) / Double(totalCount)
    }
}
