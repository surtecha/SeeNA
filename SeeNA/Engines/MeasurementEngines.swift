import Foundation

enum Statistics {
    static func median(_ values: [Double]) -> Double? {
        // Invalid sensor values are evidence failures, not sortable numbers.
        // Reject the entire input instead of allowing NaN's non-total ordering
        // to produce a platform-dependent median.
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        guard mean.isFinite, variance.isFinite, variance >= 0 else { return nil }
        let result = sqrt(variance)
        return result.isFinite ? result : nil
    }

    static func rejectOutliersMAD(_ values: [Double], multiplier: Double = 3.5) -> [Double] {
        guard multiplier.isFinite, multiplier > 0, values.allSatisfy(\.isFinite) else { return [] }
        guard let centre = median(values), values.count >= 3 else { return values }
        let deviations = values.map { abs($0 - centre) }
        guard let mad = median(deviations), mad > 0 else { return values }
        return values.filter { abs($0 - centre) / mad <= multiplier }
    }
}

enum RefractionEstimator {
    /// Converts an optical far-point distance in metres to myopic spherical
    /// power in diopters. This identity is dimensional optics only. It does not
    /// establish that an optotype response is an optical far point.
    static func diopter(forDistanceMetres distance: Double) -> Double? {
        guard distance.isFinite, distance > 0 else { return nil }
        let result = -1 / distance
        return result.isFinite ? result : nil
    }

    /// Exact inverse of `diopter(forDistanceMetres:)` for finite myopic power.
    static func distanceMetres(forMyopicDiopter diopter: Double) -> Double? {
        guard diopter.isFinite, diopter < 0 else { return nil }
        let result = -1 / diopter
        return result.isFinite && result > 0 ? result : nil
    }

    /// First-order propagation of distance standard uncertainty through
    /// D = -1 / d: sigma_D = sigma_d / d^2.
    ///
    /// This is only the sensor-repeatability component. It deliberately does
    /// not claim to include calibration bias, accommodation, display geometry,
    /// response variability, or clinical-model uncertainty.
    static func sensorUncertainty(distanceMetres: Double, standardDeviationMetres: Double) -> Double? {
        guard distanceMetres.isFinite,
              standardDeviationMetres.isFinite,
              distanceMetres > 0,
              standardDeviationMetres >= 0,
              standardDeviationMetres < distanceMetres else { return nil }
        let result = standardDeviationMetres / (distanceMetres * distanceMetres)
        return result.isFinite ? result : nil
    }

    static func roundedToQuarterDiopter(_ value: Double) -> Double {
        guard value.isFinite,
              abs(value) <= Double.greatestFiniteMagnitude / 4 else { return .nan }
        let result = (value * 4).rounded(.toNearestOrAwayFromZero) / 4
        // Avoid persisting or formatting a surprising negative zero.
        return result == 0 ? 0 : result
    }
}

enum VisualAngleGeometry {
    static let metresPerInch = 0.0254
    static let arcMinutesPerRadian = 180.0 * 60.0 / Double.pi
    static let maximumArcMinutesExclusive = 180.0 * 60.0

    /// Exact chord-free angular geometry for a centred target:
    /// h = 2 d tan(theta / 2).
    static func physicalHeightMetres(
        forArcMinutes arcMinutes: Double,
        atDistanceMetres distanceMetres: Double
    ) -> Double? {
        guard arcMinutes.isFinite,
              distanceMetres.isFinite,
              arcMinutes > 0,
              arcMinutes < maximumArcMinutesExclusive,
              distanceMetres > 0 else { return nil }
        let radians = arcMinutes / arcMinutesPerRadian
        let result = 2 * distanceMetres * tan(radians / 2)
        return result.isFinite && result > 0 ? result : nil
    }

    /// Exact inverse of `physicalHeightMetres(forArcMinutes:atDistanceMetres:)`.
    static func arcMinutes(
        forPhysicalHeightMetres physicalHeightMetres: Double,
        atDistanceMetres distanceMetres: Double
    ) -> Double? {
        guard physicalHeightMetres.isFinite,
              distanceMetres.isFinite,
              physicalHeightMetres > 0,
              distanceMetres > 0 else { return nil }
        let radians = 2 * atan(physicalHeightMetres / (2 * distanceMetres))
        let result = radians * arcMinutesPerRadian
        return result.isFinite && result > 0 ? result : nil
    }

    static func pixels(forPhysicalHeightMetres heightMetres: Double, pixelsPerInch: Double) -> Double? {
        guard heightMetres.isFinite,
              pixelsPerInch.isFinite,
              heightMetres > 0,
              pixelsPerInch > 0 else { return nil }
        let result = heightMetres / metresPerInch * pixelsPerInch
        return result.isFinite && result > 0 ? result : nil
    }

    static func physicalHeightMetres(pixelHeight: Int, pixelsPerInch: Double) -> Double? {
        guard pixelHeight > 0, pixelsPerInch.isFinite, pixelsPerInch > 0 else { return nil }
        let result = Double(pixelHeight) / pixelsPerInch * metresPerInch
        return result.isFinite && result > 0 ? result : nil
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
        guard distanceMetres.isFinite,
              pixelsPerInch.isFinite,
              displayScale.isFinite,
              distanceMetres > 0,
              pixelsPerInch > 0,
              displayScale > 0,
              minimumPixelHeight > 0 else { return nil }

        let requestedArcMinutes = clinicalReferenceArcMinutes * presentationMode.angularSizeMultiplier
        guard let physicalHeightMetres = VisualAngleGeometry.physicalHeightMetres(
            forArcMinutes: requestedArcMinutes,
            atDistanceMetres: distanceMetres
        ), let rawPixels = VisualAngleGeometry.pixels(
            forPhysicalHeightMetres: physicalHeightMetres,
            pixelsPerInch: pixelsPerInch
        ), let angularPixelHeight = landoltAlignedPixelHeight(rawPixels) else { return nil }
        let rounded: Int
        if let pointHeightRange = presentationMode.pointHeightRange {
            // Preserve five-pixel Landolt proportions while guaranteeing that
            // the SwiftUI frame stays within the practical phone POC range.
            guard let minimumPixels = alignedPixelBound(
                points: pointHeightRange.lowerBound,
                displayScale: displayScale,
                rounding: .up
            ), let maximumPixels = alignedPixelBound(
                points: pointHeightRange.upperBound,
                displayScale: displayScale,
                rounding: .down
            ), minimumPixels <= maximumPixels else { return nil }
            rounded = min(max(angularPixelHeight, minimumPixels), maximumPixels)
        } else {
            rounded = angularPixelHeight
        }
        guard rounded >= minimumPixelHeight else { return nil }

        guard let effectivePhysicalHeight = VisualAngleGeometry.physicalHeightMetres(
            pixelHeight: rounded,
            pixelsPerInch: pixelsPerInch
        ), let effectiveArcMinutes = VisualAngleGeometry.arcMinutes(
            forPhysicalHeightMetres: effectivePhysicalHeight,
            atDistanceMetres: distanceMetres
        ) else { return nil }

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
        guard let physicalHeightMetres = VisualAngleGeometry.physicalHeightMetres(
            pixelHeight: pixelHeight,
            pixelsPerInch: pixelsPerInch
        ) else { return nil }
        return VisualAngleGeometry.arcMinutes(
            forPhysicalHeightMetres: physicalHeightMetres,
            atDistanceMetres: distanceMetres
        )
    }

    private enum GridRounding {
        case up
        case down
    }

    private static func landoltAlignedPixelHeight(_ rawPixels: Double) -> Int? {
        let units = (rawPixels / 5).rounded(.toNearestOrAwayFromZero)
        guard units.isFinite,
              units >= 1,
              units <= Double(Int.max / 5) else { return nil }
        return Int(units) * 5
    }

    private static func alignedPixelBound(
        points: Double,
        displayScale: Double,
        rounding: GridRounding
    ) -> Int? {
        guard points.isFinite, points > 0 else { return nil }
        let rawUnits = points * displayScale / 5
        guard rawUnits.isFinite else { return nil }
        let units: Double
        switch rounding {
        case .up: units = ceil(rawUnits)
        case .down: units = floor(rawUnits)
        }
        guard units >= 1, units <= Double(Int.max / 5) else { return nil }
        return Int(units) * 5
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

/// Immutable description of the Landolt protocol that produced a result.
/// Device calibration and a clinically validated measurement protocol are
/// independent gates. A locally calibrated phone cannot promote the active
/// enlarged locator task into a refractive measurement.
struct LandoltProtocolDescriptor: Equatable, Sendable {
    let identifier: String
    let version: Int
    let presentationMode: OptotypePresentationMode
    let responsesPerLevel: Int
    let usesValidatedThresholdModel: Bool
    let permitsPointSizeClamping: Bool

    static let activePhoneLocator = LandoltProtocolDescriptor(
        identifier: "seena-phone-locator",
        version: 3,
        presentationMode: .phonePOCLocator,
        responsesPerLevel: SequentialOptotypeSession.requiredTargetCount,
        usesValidatedThresholdModel: false,
        permitsPointSizeClamping: true
    )

    var releaseIdentifier: String { "\(identifier)@\(version)" }
}

enum NumericResultEligibility {
    static let requiredCalibrationDistances = [0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50, 2.00]

    /// Numeric protocol releases must be added by a source-reviewed release
    /// after external agreement evidence exists. There is intentionally no
    /// approved protocol in this build. Profile JSON or local calibration alone
    /// can therefore never self-authorize a refractive number.
    private static let approvedNumericProtocolReleases: Set<String> = []

    static var hasApprovedNumericProtocolRelease: Bool {
        !approvedNumericProtocolReleases.isEmpty
    }

    static func protocolReleaseIsApproved(_ descriptor: LandoltProtocolDescriptor) -> Bool {
        // Twenty-five responses is only a conservative engineering floor for a
        // threshold model. It is never sufficient on its own: a release must
        // also be externally validated and explicitly source-approved above.
        approvedNumericProtocolReleases.contains(descriptor.releaseIdentifier) &&
            descriptor.presentationMode == .clinicalFiveArcMinute &&
            descriptor.responsesPerLevel >= 25 &&
            descriptor.usesValidatedThresholdModel &&
            !descriptor.permitsPointSizeClamping
    }

    static func allowsNumericResults(
        profile: DeviceProfile?,
        supportsSecondFaceDetection: Bool,
        matchesExactRuntimeDevice: Bool,
        protocolDescriptor: LandoltProtocolDescriptor = .activePhoneLocator
    ) -> Bool {
        guard let profile,
              protocolReleaseIsApproved(protocolDescriptor),
              matchesExactRuntimeDevice,
              profile.isValidated,
              profile.schemaVersion > 0,
              profile.profileVersion > 0,
              !profile.hardwareIdentifiers.isEmpty,
              profile.nativePixelWidth > 0,
              profile.nativePixelHeight > 0,
              profile.displayScale.isFinite,
              profile.displayScale > 0,
              profile.pixelsPerInch.isFinite,
              profile.pixelsPerInch > 0,
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
              let brightness = display.validatedBrightnessFraction,
              brightness.isFinite,
              (0...1).contains(brightness),
              let blackLuminance = display.blackLuminanceCandelaPerSquareMetre,
              blackLuminance.isFinite,
              blackLuminance >= 0,
              let whiteLuminance = display.whiteLuminanceCandelaPerSquareMetre,
              whiteLuminance.isFinite,
              whiteLuminance > blackLuminance,
              display.gammaCharacterizationIdentifier?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty == false,
              let clinical = profile.clinicalValidationEvidence,
              clinical.participantCount >= 100,
              clinical.observationCount >= 1_200,
              clinical.protocolIdentifier == protocolDescriptor.identifier,
              clinical.protocolVersion == protocolDescriptor.version,
              clinical.presentationMode == protocolDescriptor.presentationMode,
              clinical.responsesPerLevel == protocolDescriptor.responsesPerLevel,
              clinical.usedValidatedThresholdModel == protocolDescriptor.usesValidatedThresholdModel,
              clinical.permittedPointSizeClamping == protocolDescriptor.permitsPointSizeClamping,
              let agreement = clinical.agreementMetrics,
              !agreement.studyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !agreement.predefinedAcceptanceCriteriaIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              agreement.meanAbsoluteErrorDiopter.isFinite,
              agreement.meanAbsoluteErrorDiopter >= 0,
              agreement.meanBiasDiopter.isFinite,
              agreement.lower95AgreementLimitDiopter.isFinite,
              agreement.upper95AgreementLimitDiopter.isFinite,
              agreement.lower95AgreementLimitDiopter < agreement.upper95AgreementLimitDiopter,
              agreement.sensitivity.isFinite,
              (0...1).contains(agreement.sensitivity),
              agreement.specificity.isFinite,
              (0...1).contains(agreement.specificity),
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
        numericResultsAllowed: Bool,
        protocolDescriptor: LandoltProtocolDescriptor = .activePhoneLocator
    ) -> EyeScreeningResult {
        let releaseAuthorized = numericResultsAllowed && protocolReleaseIsApproved(protocolDescriptor)
        guard !releaseAuthorized else { return result }

        let containsNumericPayload = result.lastFailDiopter != nil ||
            result.firstPassDiopter != nil ||
            result.displayedEstimateDiopter != nil ||
            result.thresholdDistanceMetres != nil ||
            result.sensorUncertaintyDiopter != nil ||
            result.repeatabilityDiopter != nil
        let qualitativeStatus: ScreeningStatus
        let action: ScreeningAction?
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
            // A malformed or legacy nonnumeric status may still carry stale
            // result-level numbers. Preserve its qualitative meaning, but
            // redact every numeric field before it crosses another boundary.
            qualitativeStatus = result.status
            action = result.recommendedAction
        }

        guard containsNumericPayload || qualitativeStatus != result.status else {
            return result
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
    /// Exact binomial probability that random four-choice guessing reaches the
    /// active 6-of-8 pass threshold: P(X >= 6), X ~ Binomial(8, 0.25).
    static let randomGuessPassProbability = 0.004_226_684_570_312_5

    static func correctCount(targets: [OptotypeDirection], responses: [OptotypeDirection]) -> Int {
        guard SequentialOptotypeSession.isValidTargetSequence(targets),
              responses.count == SequentialOptotypeSession.requiredTargetCount else {
            return 0
        }
        return zip(targets, responses).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 1 : 0)
        }
    }

    static func outcome(correctCount: Int, responseCount: Int) -> TrialOutcome {
        guard responseCount == SequentialOptotypeSession.requiredTargetCount else {
            return .invalid
        }
        switch correctCount {
        case 6...SequentialOptotypeSession.requiredTargetCount: return .pass
        case 5: return .borderline
        case 0...4: return .fail
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
        let trackingValid = sample.trackingCoverage.isFinite &&
            (0...1).contains(sample.trackingCoverage) &&
            thresholds.minimumTrackingCoverage.isFinite &&
            sample.trackingCoverage >= thresholds.minimumTrackingCoverage
        if !trackingValid { reasons.append(.trackingCoverage) }
        let motionValuesValid = sample.attitudeDriftDegrees.isFinite &&
            sample.attitudeDriftDegrees >= 0 &&
            sample.accelerationRMS.isFinite &&
            sample.accelerationRMS >= 0 &&
            thresholds.maximumAttitudeDriftDegrees.isFinite &&
            thresholds.maximumAccelerationRMS.isFinite
        if !sample.phoneStable || !motionValuesValid ||
            sample.attitudeDriftDegrees > thresholds.maximumAttitudeDriftDegrees ||
            sample.accelerationRMS > thresholds.maximumAccelerationRMS {
            reasons.append(.phoneMoved)
        }
        let headPoseValid = sample.headYawDegrees.isFinite &&
            sample.headPitchDegrees.isFinite &&
            thresholds.maximumHeadYawDegrees.isFinite &&
            thresholds.maximumHeadPitchDegrees.isFinite &&
            abs(sample.headYawDegrees) <= thresholds.maximumHeadYawDegrees &&
            abs(sample.headPitchDegrees) <= thresholds.maximumHeadPitchDegrees
        if !headPoseValid { reasons.append(.headPose) }

        let distance = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres ?? .infinity
        let maximumSD = distance < 1 ? thresholds.maximumDistanceSDNearMetres : thresholds.maximumDistanceSDFarMetres
        let distanceStable = distance.isFinite && distance > 0 &&
            maximumSD.isFinite && maximumSD >= 0 &&
            sample.distanceStandardDeviation.map {
                $0.isFinite && $0 >= 0 && $0 <= maximumSD
            } == true
        if !distanceStable { reasons.append(.distanceUnstable) }
        if sample.faceCount != 1 { reasons.append(.multipleFaces) }
        if !sample.luminance.isFinite || sample.luminance < 0.12 { reasons.append(.poorLighting) }
        if responseCount != SequentialOptotypeSession.requiredTargetCount {
            reasons.append(.responseCount)
        }
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
        baselineARDistance = arDistance.isFinite && arDistance > 0 ? arDistance : nil
        baselineInterEyePixels = interEyePixels.isFinite && interEyePixels > 0 ? interEyePixels : nil
        recentValues.removeAll(keepingCapacity: true)
    }

    mutating func estimate(
        rawARDistance: Double?,
        interEyePixels: Double?,
        yawDegrees: Double,
        profile: DeviceProfile?
    ) -> (relative: Double?, fused: Double?, corrected: Double?, standardDeviation: Double?) {
        let relative: Double?
        let validRawAR = rawARDistance.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let validInterEyePixels = interEyePixels.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let validYaw = yawDegrees.isFinite ? yawDegrees : nil
        if let baselineDistance = baselineARDistance,
           let baselinePixels = baselineInterEyePixels,
           let pixels = validInterEyePixels,
           let yaw = validYaw {
            let yawCorrection = max(cos(abs(yaw) * .pi / 180), 0.94)
            let estimate = baselineDistance * (baselinePixels / pixels) * yawCorrection
            relative = estimate.isFinite && estimate > 0 ? estimate : nil
        } else {
            relative = nil
        }

        let fused: Double?
        switch (validRawAR, relative) {
        case let (ar?, scale?): fused = ar * 0.72 + scale * 0.28
        case let (ar?, nil): fused = ar
        case let (nil, scale?): fused = scale
        case (nil, nil): fused = nil
        }

        let validFused = fused.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        if let validFused {
            recentValues.append(validFused)
            if recentValues.count > windowSize { recentValues.removeFirst(recentValues.count - windowSize) }
        }
        let filtered = Statistics.rejectOutliersMAD(recentValues)
        let smoothed: Double?
        if let median = Statistics.median(filtered) {
            smoothed = median
        } else {
            smoothed = validFused
        }
        let corrected: Double?
        if let value = smoothed {
            let candidate: Double
            if let profile {
                guard profile.calibration.scale.isFinite,
                      profile.calibration.scale > 0,
                      profile.calibration.offsetMetres.isFinite else {
                    return (relative, smoothed, nil, Statistics.standardDeviation(filtered))
                }
                candidate = profile.calibration.scale * value + profile.calibration.offsetMetres
            } else {
                candidate = value
            }
            corrected = candidate.isFinite && candidate > 0 ? candidate : nil
        } else {
            corrected = nil
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
        guard observations.count >= 2,
              observations.allSatisfy({
                  $0.groundTruthMetres.isFinite && $0.groundTruthMetres > 0 &&
                  $0.rawDistanceMetres.isFinite && $0.rawDistanceMetres > 0
              }) else { return nil }
        let xs = observations.map(\.rawDistanceMetres)
        let ys = observations.map(\.groundTruthMetres)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard meanX.isFinite,
              meanY.isFinite,
              numerator.isFinite,
              denominator.isFinite,
              denominator > 0 else { return nil }
        let scale = numerator / denominator
        let offset = meanY - scale * meanX
        let residuals = observations.map { $0.groundTruthMetres - (scale * $0.rawDistanceMetres + offset) }
        guard scale.isFinite,
              scale > 0,
              offset.isFinite,
              residuals.allSatisfy(\.isFinite) else { return nil }
        return CalibrationFit(scale: scale, offsetMetres: offset, residualsMetres: residuals)
    }

    static func passesAcceptance(observations: [CalibrationObservation], fit: CalibrationFit) -> Bool {
        guard observations.count >= 1_200,
              observations.allSatisfy({
                  $0.groundTruthMetres.isFinite && $0.groundTruthMetres > 0 &&
                  $0.rawDistanceMetres.isFinite && $0.rawDistanceMetres > 0
              }),
              fit.scale.isFinite,
              fit.scale > 0,
              fit.offsetMetres.isFinite,
              fit.residualsMetres.count == observations.count,
              fit.residualsMetres.allSatisfy(\.isFinite) else { return false }
        let grouped = Dictionary(grouping: observations, by: \.groundTruthMetres)
        let required = NumericResultEligibility.requiredCalibrationDistances
        guard required.allSatisfy({ target in
            grouped.first(where: { abs($0.key - target) < 0.005 })?.value.count ?? 0 >= 150
        }) else { return false }

        return grouped.allSatisfy { groundTruth, group in
            let errors = group.map { abs(groundTruth - (fit.scale * $0.rawDistanceMetres + fit.offsetMetres)) }
            guard let medianError = Statistics.median(errors), medianError.isFinite else { return false }
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
