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

struct OptotypeGeometry: Equatable, Sendable {
    static let fiveArcMinutesInRadians = (5.0 / 60.0) * (.pi / 180.0)

    let pixelHeight: Int
    let pointHeight: Double
    let strokePixels: Int
    let innerDiameterPixels: Int
    let gapPixels: Int
    let effectiveArcMinutes: Double

    static func calculate(
        distanceMetres: Double,
        pixelsPerInch: Double,
        displayScale: Double,
        minimumPixelHeight: Int = 10
    ) -> OptotypeGeometry? {
        guard distanceMetres > 0, pixelsPerInch > 0, displayScale > 0 else { return nil }

        let physicalHeightMetres = 2 * distanceMetres * tan(fiveArcMinutesInRadians / 2)
        let rawPixels = physicalHeightMetres / 0.0254 * pixelsPerInch
        let rounded = max(5, Int((rawPixels / 5).rounded()) * 5)
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
            effectiveArcMinutes: effectiveArcMinutes
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

enum ReadabilityEngine {
    static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func wordAccuracy(reference: String, transcript: String) -> Double {
        let source = normalizedWords(reference)
        let candidate = normalizedWords(transcript)
        guard !source.isEmpty else { return candidate.isEmpty ? 1 : 0 }

        var matrix = Array(
            repeating: Array(repeating: 0, count: candidate.count + 1),
            count: source.count + 1
        )
        for i in 0...source.count { matrix[i][0] = i }
        for j in 0...candidate.count { matrix[0][j] = j }

        if !source.isEmpty, !candidate.isEmpty {
            for i in 1...source.count {
                for j in 1...candidate.count {
                    let substitution = matrix[i - 1][j - 1] + (source[i - 1] == candidate[j - 1] ? 0 : 1)
                    matrix[i][j] = min(substitution, matrix[i - 1][j] + 1, matrix[i][j - 1] + 1)
                }
            }
        }
        let errorRate = Double(matrix[source.count][candidate.count]) / Double(source.count)
        return max(0, 1 - errorRate)
    }

    static func recommendation(forComfortablePointSize pointSize: Double) -> DynamicTypeRecommendation {
        switch pointSize {
        case ..<20: return .large
        case ..<24: return .extraLarge
        case ..<28: return .extraExtraLarge
        case ..<34: return .extraExtraExtraLarge
        case ..<40: return .accessibility1
        case ..<48: return .accessibility2
        default: return .accessibility3
        }
    }
}

enum AccessibilityProfileEngine {
    static func makeProfile(from answers: AccessibilityAssessmentAnswers) -> AccessibilityProfile {
        let minimum = max(16, min(48, answers.minimumReadablePointSize))
        let comfortable = max(minimum, min(56, answers.comfortablePointSize))
        return AccessibilityProfile(
            minimumReadablePointSize: minimum,
            comfortablePointSize: comfortable,
            recommendedDynamicType: ReadabilityEngine.recommendation(forComfortablePointSize: comfortable),
            highContrastEnabled: answers.prefersHighContrast,
            boldTextEnabled: answers.prefersHighContrast || comfortable >= 28,
            increasedLineSpacing: comfortable >= 28,
            largeControlsEnabled: answers.prefersLargeControls,
            readAloudEnabled: answers.prefersReadAloud,
            simplifiedContentEnabled: answers.prefersSimplifiedContent,
            preferredLanguage: answers.preferredLanguage
        )
    }
}
