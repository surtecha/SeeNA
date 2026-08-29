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

enum OptotypePresentationMode: String, Codable, Equatable, Sendable {
    /// The clinical 5-arcminute reference geometry. This remains available for
    /// calibration and evidence, but is too small for this phone-based POC at
    /// the screening distances used by the app.
    case clinicalFiveArcMinute

    /// A single, centred, non-scored locator enlarged for a phone-screen POC.
    ///
    /// The requested angle is 96 arcminutes, then the live renderer is bounded
    /// to 96...220 points so it remains readable and fits the phone. Requested
    /// and effective rendered angles are both retained; clamping is never
    /// disguised as constant-angle or clinical geometry. This POC target must
    /// never unlock a refractive estimate or be interpreted as a clinical
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
        case .phonePOCLocator: return 96...220
        }
    }
}

struct OptotypeGeometry: Codable, Equatable, Sendable {
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

    static func angularSizeArcMinutes(
        pixelHeight: Int,
        distanceMetres: Double,
        pixelsPerInch: Double
    ) -> Double? {
        guard pixelHeight > 0, distanceMetres > 0, pixelsPerInch > 0 else { return nil }
        let physicalHeightMetres = Double(pixelHeight) / pixelsPerInch * 0.0254
        let radians = 2 * atan(physicalHeightMetres / (2 * distanceMetres))
        return radians * 180 / .pi * 60
    }
}

/// One immutable presentation record shared by the renderer and persisted
/// block evidence. Values are requested/computed POC geometry until exact
/// physical raster validation exists; they are not clinically validated.
struct PresentedOptotypeGeometry: Codable, Equatable, Sendable {
    let presentationDistanceMetres: Double
    let nativeScale: Double
    let pixelsPerInch: Double
    let geometry: OptotypeGeometry

    static func calculate(
        distanceMetres: Double,
        pixelsPerInch: Double,
        nativeScale: Double,
        presentationMode: OptotypePresentationMode = .clinicalFiveArcMinute
    ) -> PresentedOptotypeGeometry? {
        guard let geometry = OptotypeGeometry.calculate(
            distanceMetres: distanceMetres,
            pixelsPerInch: pixelsPerInch,
            displayScale: nativeScale,
            presentationMode: presentationMode
        ) else { return nil }
        return PresentedOptotypeGeometry(
            presentationDistanceMetres: distanceMetres,
            nativeScale: nativeScale,
            pixelsPerInch: pixelsPerInch,
            geometry: geometry
        )
    }

    func computedArcMinutes(at actualDistanceMetres: Double) -> Double? {
        OptotypeGeometry.angularSizeArcMinutes(
            pixelHeight: geometry.pixelHeight,
            distanceMetres: actualDistanceMetres,
            pixelsPerInch: pixelsPerInch
        )
    }
}

/// The single geometry entry point used by the live Landolt journey.
///
/// Keeping this policy in the testable core prevents a view model from silently
/// falling back to the tiny clinical reference target. The resulting geometry
/// remains requested/computed phone-POC evidence and never unlocks numeric or
/// clinical output.
enum LiveEyeTestGeometryPolicy {
    static let presentationMode: OptotypePresentationMode = .phonePOCLocator

    static func calculate(
        distanceMetres: Double,
        pixelsPerInch: Double,
        nativeScale: Double
    ) -> PresentedOptotypeGeometry? {
        PresentedOptotypeGeometry.calculate(
            distanceMetres: distanceMetres,
            pixelsPerInch: pixelsPerInch,
            nativeScale: nativeScale,
            presentationMode: presentationMode
        )
    }
}

enum SpeechDeadlineResult: Equatable, Sendable {
    case completed(SpeechOutcome)
    case timedOut
}

/// Bounds a cancellation-aware speech operation without introducing a second
/// audio channel. The caller owns the one active prompt and stops it if this
/// policy reports a timeout.
enum BoundedSpeechPolicy {
    static func wait(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async -> SpeechOutcome
    ) async -> SpeechDeadlineResult {
        guard !Task.isCancelled else { return .completed(.cancelled) }

        return await withTaskGroup(of: SpeechDeadlineResult.self) { group in
            group.addTask {
                .completed(await operation())
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return .timedOut
                } catch {
                    return .completed(.cancelled)
                }
            }

            let first = await group.next() ?? .completed(.failed)
            group.cancelAll()
            guard !Task.isCancelled else { return .completed(.cancelled) }
            return first
        }
    }
}

/// A committed screen transition is independent of speech success, but it may
/// only append while the originating task, epoch, and route are still current.
enum CompletionNavigationPolicy {
    static func shouldAdvance<Route: Equatable>(
        after speechOutcome: SpeechOutcome,
        expectedRoute: Route,
        currentRoute: Route?,
        expectedGeneration: UUID,
        currentGeneration: UUID,
        taskIsCancelled: Bool
    ) -> Bool {
        _ = speechOutcome
        return !taskIsCancelled
            && expectedRoute == currentRoute
            && expectedGeneration == currentGeneration
    }
}

enum NumericResultEligibility {
    static let requiredCalibrationDistances = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]

    static func allowsNumericResults(
        profile: DeviceProfile?,
        supportsSecondFaceDetection: Bool,
        matchesExactRuntimeDevice: Bool
    ) -> Bool {
        guard let profile,
              matchesExactRuntimeDevice,
              profile.isValidated,
              profile.validationEvidence.sampleCount >= 1_200,
              profile.validationEvidence.validatedAt != nil,
              let nearError = profile.validationEvidence.maximumMedianErrorBelowOneMetre,
              nearError.isFinite,
              nearError <= 0.03,
              let farError = profile.validationEvidence.maximumMedianPercentageErrorAtOrAboveOneMetre,
              farError.isFinite,
              farError <= 0.05,
              profile.calibration.scale.isFinite,
              profile.calibration.scale > 0,
              profile.calibration.offsetMetres.isFinite,
              profile.minimumValidatedDistance <= 0.40,
              profile.maximumValidatedDistance >= 2.00,
              let display = profile.displayRasterValidation,
              display.sampleCount >= 100,
              display.validatedAt != nil,
              display.nativePixelWidth == profile.nativePixelWidth,
              display.nativePixelHeight == profile.nativePixelHeight,
              abs(display.displayScale - profile.displayScale) < 0.001,
              abs(display.pixelsPerInch - profile.pixelsPerInch) < 0.1,
              let clinical = profile.clinicalValidationEvidence,
              clinical.participantCount >= 100,
              clinical.observationCount >= 1_200,
              !clinical.protocolIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              clinical.validatedAt != nil,
              supportsSecondFaceDetection else { return false }
        return requiredCalibrationDistances.allSatisfy { required in
            profile.calibration.validatedDistancesMetres.contains {
                abs($0 - required) < 0.005
            }
        }
    }

    static func sanitize(
        _ result: EyeScreeningResult,
        numericResultsAllowed: Bool
    ) -> EyeScreeningResult {
        guard !numericResultsAllowed,
              [.validEstimate, .noMyopiaDetectedWithinRange, .strongerThanSupportedRange]
                .contains(result.status) else { return result }
        let qualitativeStatus: ScreeningStatus
        let action: ScreeningAction
        switch result.status {
        case .validEstimate:
            qualitativeStatus = .experimentalThresholdObserved
            action = .professionalReviewRecommended
        case .noMyopiaDetectedWithinRange:
            qualitativeStatus = .experimentalFarthestTargetPassed
            action = .routineExamRecommended
        case .strongerThanSupportedRange:
            qualitativeStatus = .experimentalAdverseBoundary
            action = .professionalReviewRecommended
        default:
            qualitativeStatus = .experimentalTaskCompleted
            action = .repeatRequired
        }
        return EyeScreeningResult(
            eye: result.eye,
            status: qualitativeStatus,
            lastFailDiopter: nil,
            firstPassDiopter: nil,
            displayedEstimateDiopter: nil,
            thresholdDistanceMetres: nil,
            sensorUncertaintyDiopter: nil,
            repeatabilityDiopter: nil,
            trackingQuality: result.trackingQuality,
            responseConsistency: result.responseConsistency,
            warnings: Array(Set(result.warnings + [
                .researchPrototype, .notPrescription, .clinicalAccuracyNotEstablished
            ])),
            recommendedAction: action
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

/// A small ownership reducer used by the DEBUG sensor simulator. Only the
/// screen that currently owns the token can move the synthetic distance,
/// preventing a disappearing screen from racing the next eye/test screen.
struct ExclusiveDistanceTargetController: Equatable, Sendable {
    private(set) var owner: UUID?
    private(set) var targetDistanceMetres: Double = 0.40

    mutating func claim() -> UUID {
        let token = UUID()
        owner = token
        targetDistanceMetres = 0.40
        return token
    }

    @discardableResult
    mutating func update(_ distance: Double, owner token: UUID?) -> Bool {
        guard token == owner, distance.isFinite, distance > 0 else { return false }
        targetDistanceMetres = distance
        return true
    }

    @discardableResult
    mutating func release(owner token: UUID?) -> Bool {
        guard token == owner else { return false }
        owner = nil
        return true
    }

    mutating func reset() {
        owner = nil
        targetDistanceMetres = 0.40
    }
}

enum SpeechProgressionPolicy {
    static func shouldAdvance(after outcome: SpeechOutcome) -> Bool {
        outcome == .finished
    }
}

struct SensorStreamEpochState: Equatable, Sendable {
    private(set) var epoch: UInt64 = 0

    mutating func invalidate() -> UInt64 {
        epoch &+= 1
        return epoch
    }

    func isCurrent(_ capturedEpoch: UInt64) -> Bool {
        capturedEpoch == epoch
    }
}
