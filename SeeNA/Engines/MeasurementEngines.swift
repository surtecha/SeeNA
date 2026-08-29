import Foundation

enum Statistics {
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return values.isEmpty ? nil : 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    static func rejectOutliersMAD(_ values: [Double], multiplier: Double = 3.5) -> [Double] {
        guard let centre = median(values), values.count >= 3 else { return values }
        let deviations = values.map { abs($0 - centre) }
        guard let mad = median(deviations), mad > 0 else { return values }
        return values.filter { abs($0 - centre) / mad <= multiplier }
    }
}

enum RefractionEstimator {
    static func diopter(forDistanceMetres distance: Double) -> Double? {
        guard distance > 0 else { return nil }
        return -1 / distance
    }

    static func sensorUncertainty(distanceMetres: Double, standardDeviationMetres: Double) -> Double? {
        guard distanceMetres > 0, standardDeviationMetres >= 0 else { return nil }
        return standardDeviationMetres / pow(distanceMetres, 2)
    }

    static func roundedToQuarterDiopter(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }
}

enum OptotypePresentationMode: Equatable, Sendable {
    /// The clinical 5-arcminute reference geometry. This remains available for
    /// calibration and evidence, but is too small for this phone-based POC at
    /// the screening distances used by the app.
    case clinicalFiveArcMinute

    /// A single, centred, non-scored locator enlarged for a phone-screen POC.
    ///
    /// The requested angle is 96 arcminutes. That yields a clearly visible
    /// ~67-point target at 40 cm and a nearly screen-width ~336-point target at
    /// 2 m on a 460-ppi iPhone. Unlike a point-size clamp, the target keeps the
    /// same visual angle at every distance. It helps a participant find the
    /// centre of the phone before the scored target appears, but it must never
    /// contribute to a refractive estimate or be interpreted as a clinical
    /// 5-arcminute acuity target.
    case phonePOCLocator

    var angularSizeMultiplier: Double {
        switch self {
        case .clinicalFiveArcMinute: return 1
        case .phonePOCLocator: return 19.2
        }
    }

    var pointHeightRange: ClosedRange<Double>? {
        switch self {
        case .clinicalFiveArcMinute: return nil
        case .phonePOCLocator: return nil
        }
    }
}

struct OptotypeGeometry: Equatable, Sendable {
    static let clinicalReferenceArcMinutes = 5.0

    let pixelHeight: Int
    let pointHeight: Double
    let strokePixels: Int
    let innerDiameterPixels: Int
    let gapPixels: Int
    let presentationMode: OptotypePresentationMode
    let requestedArcMinutes: Double
    let effectiveArcMinutes: Double
    let wasPointSizeClamped: Bool

    static func calculate(
        distanceMetres: Double,
        pixelsPerInch: Double,
        displayScale: Double,
        minimumPixelHeight: Int = 10,
        presentationMode: OptotypePresentationMode = .clinicalFiveArcMinute
    ) -> OptotypeGeometry? {
        guard distanceMetres > 0, pixelsPerInch > 0, displayScale > 0 else { return nil }

        let requestedArcMinutes = clinicalReferenceArcMinutes * presentationMode.angularSizeMultiplier
        let requestedRadians = (requestedArcMinutes / 60) * (.pi / 180)
        let physicalHeightMetres = 2 * distanceMetres * tan(requestedRadians / 2)
        let rawPixels = physicalHeightMetres / 0.0254 * pixelsPerInch
        let angularPixelHeight = max(5, Int((rawPixels / 5).rounded()) * 5)
        let rounded: Int
        if let pointHeightRange = presentationMode.pointHeightRange {
            // Preserve five-pixel Landolt proportions while guaranteeing that
            // the SwiftUI frame stays within the practical phone POC range.
            let minimumPixels = Int(ceil(pointHeightRange.lowerBound * displayScale / 5)) * 5
            let maximumPixels = Int(floor(pointHeightRange.upperBound * displayScale / 5)) * 5
            rounded = min(max(angularPixelHeight, minimumPixels), maximumPixels)
        } else {
            rounded = angularPixelHeight
        }
        guard rounded >= minimumPixelHeight else { return nil }

        let effectivePhysicalHeight = Double(rounded) / pixelsPerInch * 0.0254
        let effectiveRadians = 2 * atan(effectivePhysicalHeight / (2 * distanceMetres))
        let effectiveArcMinutes = effectiveRadians * 180 / .pi * 60

        return OptotypeGeometry(
            pixelHeight: rounded,
            pointHeight: Double(rounded) / displayScale,
            strokePixels: rounded / 5,
            innerDiameterPixels: rounded * 3 / 5,
            gapPixels: rounded / 5,
            presentationMode: presentationMode,
            requestedArcMinutes: requestedArcMinutes,
            effectiveArcMinutes: effectiveArcMinutes,
            wasPointSizeClamped: rounded != angularPixelHeight
        )
    }
}

enum TrialScorer {
    static func correctCount(targets: [OptotypeDirection], responses: [OptotypeDirection]) -> Int {
        guard targets.count == 7, responses.count == 7 else { return 0 }
        return zip(targets, responses).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 1 : 0)
        }
    }

    static func outcome(correctCount: Int, hasExactlySevenResponses: Bool) -> TrialOutcome {
        guard hasExactlySevenResponses else { return .invalid }
        switch correctCount {
        case 5...7: return .pass
        case 0...3: return .fail
        case 4: return .borderline
        default: return .invalid
        }
    }
}

enum QualityGateEngine {
    static func evaluate(
        sample: DistanceSample,
        responseCount: Int,
        audioLevelAdequate: Bool,
        targetGeometryValid: Bool,
        orientationChanged: Bool,
        thresholds: QualityThresholds
    ) -> BlockQuality {
        var reasons: [BlockDiscardReason] = []
        if sample.trackingCoverage < thresholds.minimumTrackingCoverage { reasons.append(.trackingCoverage) }
        if !sample.phoneStable || sample.attitudeDriftDegrees > thresholds.maximumAttitudeDriftDegrees || sample.accelerationRMS > thresholds.maximumAccelerationRMS {
            reasons.append(.phoneMoved)
        }
        let headPoseValid = abs(sample.headYawDegrees) <= thresholds.maximumHeadYawDegrees && abs(sample.headPitchDegrees) <= thresholds.maximumHeadPitchDegrees
        if !headPoseValid { reasons.append(.headPose) }

        let distance = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres ?? .infinity
        let maximumSD = distance < 1 ? thresholds.maximumDistanceSDNearMetres : thresholds.maximumDistanceSDFarMetres
        let distanceStable = (sample.distanceStandardDeviation ?? .infinity) <= maximumSD
        if !distanceStable { reasons.append(.distanceUnstable) }
        if sample.faceCount != 1 { reasons.append(.multipleFaces) }
        if sample.luminance < 0.12 { reasons.append(.poorLighting) }
        if responseCount != 7 { reasons.append(.responseCount) }
        if !audioLevelAdequate { reasons.append(.audioLevel) }
        if !targetGeometryValid { reasons.append(.targetGeometry) }
        if orientationChanged { reasons.append(.orientationChanged) }

        return BlockQuality(
            trackingCoverage: sample.trackingCoverage,
            phoneStable: sample.phoneStable,
            headPoseValid: headPoseValid,
            distanceStable: distanceStable,
            audioLevelAdequate: audioLevelAdequate,
            targetGeometryValid: targetGeometryValid,
            discardReasons: Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        )
    }
}

struct DistanceFusionEngine: Sendable {
    private(set) var baselineARDistance: Double?
    private(set) var baselineInterEyePixels: Double?
    private var recentValues: [Double] = []
    private let windowSize: Int

    init(windowSize: Int = 12) {
        self.windowSize = max(10, min(15, windowSize))
    }

    mutating func setBaseline(arDistance: Double, interEyePixels: Double) {
        baselineARDistance = arDistance
        baselineInterEyePixels = interEyePixels
        recentValues.removeAll(keepingCapacity: true)
    }

    mutating func estimate(
        rawARDistance: Double?,
        interEyePixels: Double?,
        yawDegrees: Double,
        profile: DeviceProfile?
    ) -> (relative: Double?, fused: Double?, corrected: Double?, standardDeviation: Double?) {
        let relative: Double?
        if let baselineDistance = baselineARDistance,
           let baselinePixels = baselineInterEyePixels,
           let pixels = interEyePixels,
           pixels > 0 {
            let yawCorrection = max(cos(abs(yawDegrees) * .pi / 180), 0.94)
            relative = baselineDistance * (baselinePixels / pixels) * yawCorrection
        } else {
            relative = nil
        }

        let fused: Double?
        switch (rawARDistance, relative) {
        case let (ar?, scale?): fused = ar * 0.72 + scale * 0.28
        case let (ar?, nil): fused = ar
        case let (nil, scale?): fused = scale
        case (nil, nil): fused = nil
        }

        if let fused {
            recentValues.append(fused)
            if recentValues.count > windowSize { recentValues.removeFirst(recentValues.count - windowSize) }
        }
        let filtered = Statistics.rejectOutliersMAD(recentValues)
        let smoothed = Statistics.median(filtered) ?? fused
        let corrected = smoothed.map { value in
            guard let profile else { return value }
            return profile.calibration.scale * value + profile.calibration.offsetMetres
        }
        return (relative, smoothed, corrected, Statistics.standardDeviation(filtered))
    }
}

struct CalibrationObservation: Codable, Equatable, Sendable {
    let groundTruthMetres: Double
    let rawDistanceMetres: Double
}

struct CalibrationFit: Codable, Equatable, Sendable {
    let scale: Double
    let offsetMetres: Double
    let residualsMetres: [Double]
}

enum CalibrationFitter {
    static func affineFit(observations: [CalibrationObservation]) -> CalibrationFit? {
        guard observations.count >= 2 else { return nil }
        let xs = observations.map(\.rawDistanceMetres)
        let ys = observations.map(\.groundTruthMetres)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard denominator > 0 else { return nil }
        let scale = numerator / denominator
        let offset = meanY - scale * meanX
        let residuals = observations.map { $0.groundTruthMetres - (scale * $0.rawDistanceMetres + offset) }
        return CalibrationFit(scale: scale, offsetMetres: offset, residualsMetres: residuals)
    }

    static func passesAcceptance(observations: [CalibrationObservation], fit: CalibrationFit) -> Bool {
        let grouped = Dictionary(grouping: observations, by: \.groundTruthMetres)
        let required = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]
        guard required.allSatisfy({ target in grouped.keys.contains(where: { abs($0 - target) < 0.005 }) }) else { return false }

        return grouped.allSatisfy { groundTruth, group in
            let errors = group.map { abs(groundTruth - (fit.scale * $0.rawDistanceMetres + fit.offsetMetres)) }
            guard let medianError = Statistics.median(errors) else { return false }
            return groundTruth < 1 ? medianError <= 0.03 : medianError / groundTruth <= 0.05
        }
    }
}
