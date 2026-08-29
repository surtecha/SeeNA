import Foundation

enum SpeechOutcome: Equatable, Sendable {
    case finished
    case cancelled
    case failed
}

enum Eye: String, Codable, CaseIterable, Sendable {
    case right
    case left

    var displayName: String { rawValue.capitalized }
    var eyeToCover: String { self == .right ? "left" : "right" }
}

enum OptotypeDirection: String, Codable, CaseIterable, Sendable {
    case up
    case right
    case down
    case left

    var rotationDegrees: Double {
        switch self {
        case .right: return 0
        case .down: return 90
        case .left: return 180
        case .up: return 270
        }
    }
}

/// The participant's auditable answer to one Landolt target.
///
/// The four direction raw values intentionally match the former
/// `[OptotypeDirection]` encoding, so previously saved sessions continue to
/// decode after `TrialBlock.responses` adopts this richer answer type.
enum OptotypeResponse: String, Codable, Equatable, Sendable {
    case up
    case right
    case down
    case left
    case notVisible

    init(_ direction: OptotypeDirection) {
        switch direction {
        case .up: self = .up
        case .right: self = .right
        case .down: self = .down
        case .left: self = .left
        }
    }

    var direction: OptotypeDirection? {
        switch self {
        case .up: return .up
        case .right: return .right
        case .down: return .down
        case .left: return .left
        case .notVisible: return nil
        }
    }

    func matches(_ target: OptotypeDirection) -> Bool {
        direction == target
    }

    var auditCode: String {
        switch self {
        case .up: return "U"
        case .right: return "R"
        case .down: return "D"
        case .left: return "L"
        case .notVisible: return "NV"
        }
    }
}

enum GaborOrientation: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

/// The participant's auditable answer to one Gabor orientation target.
///
/// `notVisible` is deliberately persisted as its own response rather than
/// being encoded as the opposite orientation. That preserves the difference
/// between an incorrect answer and an explicit inability to see the patch.
enum GaborResponse: String, Codable, Equatable, Sendable {
    case left
    case right
    case notVisible

    init(_ orientation: GaborOrientation) {
        self = orientation == .left ? .left : .right
    }

    var orientation: GaborOrientation? {
        switch self {
        case .left: return .left
        case .right: return .right
        case .notVisible: return nil
        }
    }

    func matches(_ target: GaborOrientation) -> Bool {
        orientation == target
    }
}

enum GaborScreeningStatus: String, Codable, Sendable {
    case completed
    case unreliableMeasurement
}

struct GaborTrial: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eye: Eye
    let contrast: Double
    let targets: [GaborOrientation]
    let responses: [GaborResponse]
    let correctCount: Int
    let outcome: TrialOutcome
    let responseSource: ResponseSource
    let transcript: String?
    let quality: BlockQuality?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        eye: Eye,
        contrast: Double,
        targets: [GaborOrientation],
        responses: [GaborResponse],
        correctCount: Int,
        outcome: TrialOutcome,
        responseSource: ResponseSource,
        transcript: String?,
        quality: BlockQuality? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.eye = eye
        self.contrast = contrast
        self.targets = targets
        self.responses = responses
        self.correctCount = correctCount
        self.outcome = outcome
        self.responseSource = responseSource
        self.transcript = transcript
        self.quality = quality
        self.timestamp = timestamp
    }

    /// Source-compatible convenience for direction-only test fixtures and
    /// historical callers. New trial records preserve `notVisible` explicitly.
    init(
        id: UUID = UUID(),
        eye: Eye,
        contrast: Double,
        targets: [GaborOrientation],
        responses: [GaborOrientation],
        correctCount: Int,
        outcome: TrialOutcome,
        responseSource: ResponseSource,
        transcript: String?,
        quality: BlockQuality? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            eye: eye,
            contrast: contrast,
            targets: targets,
            responses: responses.map(GaborResponse.init),
            correctCount: correctCount,
            outcome: outcome,
            responseSource: responseSource,
            transcript: transcript,
            quality: quality,
            timestamp: timestamp
        )
    }
}

struct GaborScreeningResult: Codable, Equatable, Sendable {
    let eye: Eye
    let status: GaborScreeningStatus
    let responseConsistency: QualityLabel
}

enum ResponseSource: String, Codable, Sendable {
    case voice
    case operatorInput = "operator"
}

enum ScreeningStatus: String, Codable, Sendable {
    case validEstimate
    case noMyopiaDetectedWithinRange
    case strongerThanSupportedRange
    /// Nonnumeric equivalents preserve what happened in the task without
    /// presenting an unvalidated refractive measurement.
    case experimentalThresholdObserved
    case experimentalFarthestTargetPassed
    case experimentalAdverseBoundary
    case experimentalTaskCompleted
    case unreliableMeasurement
    case deviceUnsupported
    case userIneligible
}

enum ScreeningAction: String, Codable, Sendable {
    case professionalReviewRecommended
    case routineExamRecommended
    case repeatRequired
    case unavailable
}

enum QualityLabel: String, Codable, Sendable {
    case good
    case moderate
    case poor
    case unavailable
}

enum ResultWarning: String, Codable, Hashable, Sendable {
    case researchPrototype
    case notPrescription
    case hyperopiaNotAssessed
    case clinicalAccuracyNotEstablished
    case eyesProducedDifferentResults
    case operatorResponseUsed
}

enum AccessibilityOnlyReason: String, Codable, Sendable {
    case unvalidatedDevice
    case faceTrackingUnavailable
    case contactLenses
    case unsafeMovement
    case under18
    case cameraPermissionDenied
    case calibrationFailed
    case screeningUnavailable
}

enum UnsupportedDeviceReason: String, Codable, Sendable {
    case nonIPhone
    case operatingSystemTooOld
    case contradictoryMetadata
    case unsafeConfiguration
}

enum DeviceCapabilityTier: Equatable, Sendable {
    case fullScreening(profile: DeviceProfile)
    case accessibilityOnly(reason: AccessibilityOnlyReason)
    case unsupported(reason: UnsupportedDeviceReason)
}

enum CameraType: String, Codable, Sendable {
    case trueDepth
    case frontCamera
}

struct DistanceCalibration: Codable, Equatable, Sendable {
    let scale: Double
    let offsetMetres: Double
    let baselineDistanceMetres: Double
    let validatedDistancesMetres: [Double]
}

struct QualityThresholds: Codable, Equatable, Sendable {
    let minimumTrackingCoverage: Double
    let maximumAttitudeDriftDegrees: Double
    let maximumAccelerationRMS: Double
    let maximumHeadYawDegrees: Double
    let maximumHeadPitchDegrees: Double
    let maximumDistanceSDNearMetres: Double
    let maximumDistanceSDFarMetres: Double

    static let conservative = QualityThresholds(
        minimumTrackingCoverage: 0.90,
        maximumAttitudeDriftDegrees: 1.5,
        maximumAccelerationRMS: 0.02,
        maximumHeadYawDegrees: 18,
        maximumHeadPitchDegrees: 18,
        maximumDistanceSDNearMetres: 0.02,
        maximumDistanceSDFarMetres: 0.05
    )
}

struct ValidationSummary: Codable, Equatable, Sendable {
    let sampleCount: Int
    let maximumMedianErrorBelowOneMetre: Double?
    let maximumMedianPercentageErrorAtOrAboveOneMetre: Double?
    let validatedAt: Date?
    let notes: String

    static let notValidated = ValidationSummary(
        sampleCount: 0,
        maximumMedianErrorBelowOneMetre: nil,
        maximumMedianPercentageErrorAtOrAboveOneMetre: nil,
        validatedAt: nil,
        notes: "Physical tape validation has not been completed for this exact device."
    )
}

/// Independent evidence that the requested optotype pixels and SwiftUI points
/// were physically checked on the exact display. Distance tape observations do
/// not satisfy this gate.
struct DisplayRasterValidation: Codable, Equatable, Sendable {
    let sampleCount: Int
    let nativePixelWidth: Int
    let nativePixelHeight: Int
    let displayScale: Double
    let pixelsPerInch: Double
    let validatedAt: Date?
    let notes: String
}

/// Independent participant-level evidence for the complete measurement
/// protocol. This is intentionally absent from bundled POC profiles.
struct ClinicalValidationEvidence: Codable, Equatable, Sendable {
    let participantCount: Int
    let observationCount: Int
    let protocolIdentifier: String
    let validatedAt: Date?
    let notes: String
}

struct DeviceProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String { hardwareIdentifiers.first ?? marketingFamily }

    let schemaVersion: Int
    let profileVersion: Int
    let hardwareIdentifiers: [String]
    let marketingFamily: String
    let variant: String
    let nativePixelWidth: Int
    let nativePixelHeight: Int
    let displayScale: Double
    let pixelsPerInch: Double
    let expectedCameraType: CameraType
    let calibration: DistanceCalibration
    let qualityThresholds: QualityThresholds
    let minimumValidatedDistance: Double
    let maximumValidatedDistance: Double
    let validationEvidence: ValidationSummary
    let displayRasterValidation: DisplayRasterValidation?
    let clinicalValidationEvidence: ClinicalValidationEvidence?
    let isValidated: Bool

    init(
        schemaVersion: Int,
        profileVersion: Int,
        hardwareIdentifiers: [String],
        marketingFamily: String,
        variant: String,
        nativePixelWidth: Int,
        nativePixelHeight: Int,
        displayScale: Double,
        pixelsPerInch: Double,
        expectedCameraType: CameraType,
        calibration: DistanceCalibration,
        qualityThresholds: QualityThresholds,
        minimumValidatedDistance: Double,
        maximumValidatedDistance: Double,
        validationEvidence: ValidationSummary,
        displayRasterValidation: DisplayRasterValidation? = nil,
        clinicalValidationEvidence: ClinicalValidationEvidence? = nil,
        isValidated: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.profileVersion = profileVersion
        self.hardwareIdentifiers = hardwareIdentifiers
        self.marketingFamily = marketingFamily
        self.variant = variant
        self.nativePixelWidth = nativePixelWidth
        self.nativePixelHeight = nativePixelHeight
        self.displayScale = displayScale
        self.pixelsPerInch = pixelsPerInch
        self.expectedCameraType = expectedCameraType
        self.calibration = calibration
        self.qualityThresholds = qualityThresholds
        self.minimumValidatedDistance = minimumValidatedDistance
        self.maximumValidatedDistance = maximumValidatedDistance
        self.validationEvidence = validationEvidence
        self.displayRasterValidation = displayRasterValidation
        self.clinicalValidationEvidence = clinicalValidationEvidence
        self.isValidated = isValidated
    }
}

struct DistanceSample: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let rawARDistanceMetres: Double?
    let relativeScaleDistanceMetres: Double?
    let fusedDistanceMetres: Double?
    let correctedDistanceMetres: Double?
    let distanceStandardDeviation: Double?
    let trackingCoverage: Double
    let phoneStable: Bool
    let attitudeDriftDegrees: Double
    let accelerationRMS: Double
    let headYawDegrees: Double
    let headPitchDegrees: Double
    let gazeYawErrorDegrees: Double?
    let gazePitchErrorDegrees: Double?
    let luminance: Double
    let faceCount: Int
    let interEyePixels: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawARDistanceMetres: Double?,
        relativeScaleDistanceMetres: Double?,
        fusedDistanceMetres: Double?,
        correctedDistanceMetres: Double?,
        distanceStandardDeviation: Double?,
        trackingCoverage: Double,
        phoneStable: Bool,
        attitudeDriftDegrees: Double,
        accelerationRMS: Double,
        headYawDegrees: Double,
        headPitchDegrees: Double,
        gazeYawErrorDegrees: Double? = nil,
        gazePitchErrorDegrees: Double? = nil,
        luminance: Double,
        faceCount: Int,
        interEyePixels: Double?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawARDistanceMetres = rawARDistanceMetres
        self.relativeScaleDistanceMetres = relativeScaleDistanceMetres
        self.fusedDistanceMetres = fusedDistanceMetres
        self.correctedDistanceMetres = correctedDistanceMetres
        self.distanceStandardDeviation = distanceStandardDeviation
        self.trackingCoverage = trackingCoverage
        self.phoneStable = phoneStable
        self.attitudeDriftDegrees = attitudeDriftDegrees
        self.accelerationRMS = accelerationRMS
        self.headYawDegrees = headYawDegrees
        self.headPitchDegrees = headPitchDegrees
        self.gazeYawErrorDegrees = gazeYawErrorDegrees
        self.gazePitchErrorDegrees = gazePitchErrorDegrees
        self.luminance = luminance
        self.faceCount = faceCount
        self.interEyePixels = interEyePixels
    }
}

enum BlockDiscardReason: String, Codable, Hashable, Sendable {
    case trackingCoverage
    case phoneMoved
    case headPose
    case distanceUnstable
    case targetGeometry
    case audioLevel
    case responseCount
    case orientationChanged
    case multipleFaces
    case gazeUnavailable
    case gazeOffCentre
    case poorLighting
    case serviceUnavailable
}

struct BlockQuality: Codable, Equatable, Sendable {
    let trackingCoverage: Double
    let phoneStable: Bool
    let headPoseValid: Bool
    let distanceStable: Bool
    let audioLevelAdequate: Bool
    let targetGeometryValid: Bool
    let gazeCoverage: Double?
    let discardReasons: [BlockDiscardReason]

    init(
        trackingCoverage: Double,
        phoneStable: Bool,
        headPoseValid: Bool,
        distanceStable: Bool,
        audioLevelAdequate: Bool,
        targetGeometryValid: Bool,
        gazeCoverage: Double? = nil,
        discardReasons: [BlockDiscardReason]
    ) {
        self.trackingCoverage = trackingCoverage
        self.phoneStable = phoneStable
        self.headPoseValid = headPoseValid
        self.distanceStable = distanceStable
        self.audioLevelAdequate = audioLevelAdequate
        self.targetGeometryValid = targetGeometryValid
        self.gazeCoverage = gazeCoverage
        self.discardReasons = discardReasons
    }

    var isValid: Bool { discardReasons.isEmpty }
}

enum TrialOutcome: String, Codable, Sendable {
    case pass
    case fail
    case borderline
    case invalid
}

struct TrialBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eye: Eye
    let candidateDiopter: Double
    let targetDistanceMetres: Double
    let actualMedianDistanceMetres: Double
    let distanceStandardDeviation: Double
    let targets: [OptotypeDirection]
    let responses: [OptotypeResponse]
    let correctCount: Int
    let outcome: TrialOutcome
    let quality: BlockQuality
    let responseSource: ResponseSource
    let transcript: String?
    /// Geometry actually frozen on screen for this block. Optional fields keep
    /// sessions saved before schema v2 decodable.
    let presentationDistanceMetres: Double?
    let renderedPixelHeight: Int?
    let renderedPointHeight: Double?
    let renderedAngularSizeArcMinutes: Double?
    let actualAngularSizeArcMinutes: Double?
    let geometryDistanceDriftFraction: Double?
    let presentedGeometry: PresentedOptotypeGeometry?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        eye: Eye,
        candidateDiopter: Double,
        targetDistanceMetres: Double,
        actualMedianDistanceMetres: Double,
        distanceStandardDeviation: Double,
        targets: [OptotypeDirection],
        responses: [OptotypeResponse],
        correctCount: Int,
        outcome: TrialOutcome,
        quality: BlockQuality,
        responseSource: ResponseSource,
        transcript: String?,
        presentationDistanceMetres: Double? = nil,
        renderedPixelHeight: Int? = nil,
        renderedPointHeight: Double? = nil,
        renderedAngularSizeArcMinutes: Double? = nil,
        actualAngularSizeArcMinutes: Double? = nil,
        geometryDistanceDriftFraction: Double? = nil,
        presentedGeometry: PresentedOptotypeGeometry? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.eye = eye
        self.candidateDiopter = candidateDiopter
        self.targetDistanceMetres = targetDistanceMetres
        self.actualMedianDistanceMetres = actualMedianDistanceMetres
        self.distanceStandardDeviation = distanceStandardDeviation
        self.targets = targets
        self.responses = responses
        self.correctCount = correctCount
        self.outcome = outcome
        self.quality = quality
        self.responseSource = responseSource
        self.transcript = transcript
        self.presentationDistanceMetres = presentationDistanceMetres
        self.renderedPixelHeight = renderedPixelHeight
        self.renderedPointHeight = renderedPointHeight
        self.renderedAngularSizeArcMinutes = renderedAngularSizeArcMinutes
        self.actualAngularSizeArcMinutes = actualAngularSizeArcMinutes
        self.geometryDistanceDriftFraction = geometryDistanceDriftFraction
        self.presentedGeometry = presentedGeometry
        self.timestamp = timestamp
    }

    /// Source-compatible convenience for fixtures and operator-entered
    /// direction arrays. New persisted data still uses `OptotypeResponse`.
    init(
        id: UUID = UUID(),
        eye: Eye,
        candidateDiopter: Double,
        targetDistanceMetres: Double,
        actualMedianDistanceMetres: Double,
        distanceStandardDeviation: Double,
        targets: [OptotypeDirection],
        responses: [OptotypeDirection],
        correctCount: Int,
        outcome: TrialOutcome,
        quality: BlockQuality,
        responseSource: ResponseSource,
        transcript: String?,
        presentationDistanceMetres: Double? = nil,
        renderedPixelHeight: Int? = nil,
        renderedPointHeight: Double? = nil,
        renderedAngularSizeArcMinutes: Double? = nil,
        actualAngularSizeArcMinutes: Double? = nil,
        geometryDistanceDriftFraction: Double? = nil,
        presentedGeometry: PresentedOptotypeGeometry? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            eye: eye,
            candidateDiopter: candidateDiopter,
            targetDistanceMetres: targetDistanceMetres,
            actualMedianDistanceMetres: actualMedianDistanceMetres,
            distanceStandardDeviation: distanceStandardDeviation,
            targets: targets,
            responses: responses.map(OptotypeResponse.init),
            correctCount: correctCount,
            outcome: outcome,
            quality: quality,
            responseSource: responseSource,
            transcript: transcript,
            presentationDistanceMetres: presentationDistanceMetres,
            renderedPixelHeight: renderedPixelHeight,
            renderedPointHeight: renderedPointHeight,
            renderedAngularSizeArcMinutes: renderedAngularSizeArcMinutes,
            actualAngularSizeArcMinutes: actualAngularSizeArcMinutes,
            geometryDistanceDriftFraction: geometryDistanceDriftFraction,
            presentedGeometry: presentedGeometry,
            timestamp: timestamp
        )
    }
}

struct EyeScreeningResult: Codable, Equatable, Sendable {
    let eye: Eye
    let status: ScreeningStatus
    let lastFailDiopter: Double?
    let firstPassDiopter: Double?
    let displayedEstimateDiopter: Double?
    let thresholdDistanceMetres: Double?
    let sensorUncertaintyDiopter: Double?
    let repeatabilityDiopter: Double?
    let trackingQuality: QualityLabel
    let responseConsistency: QualityLabel
    let warnings: [ResultWarning]
    /// A qualitative, locally-derived action retained even when numeric
    /// measurements are stripped from an unvalidated result.
    let recommendedAction: ScreeningAction?

    init(
        eye: Eye,
        status: ScreeningStatus,
        lastFailDiopter: Double?,
        firstPassDiopter: Double?,
        displayedEstimateDiopter: Double?,
        thresholdDistanceMetres: Double?,
        sensorUncertaintyDiopter: Double?,
        repeatabilityDiopter: Double?,
        trackingQuality: QualityLabel,
        responseConsistency: QualityLabel,
        warnings: [ResultWarning],
        recommendedAction: ScreeningAction? = nil
    ) {
        self.eye = eye
        self.status = status
        self.lastFailDiopter = lastFailDiopter
        self.firstPassDiopter = firstPassDiopter
        self.displayedEstimateDiopter = displayedEstimateDiopter
        self.thresholdDistanceMetres = thresholdDistanceMetres
        self.sensorUncertaintyDiopter = sensorUncertaintyDiopter
        self.repeatabilityDiopter = repeatabilityDiopter
        self.trackingQuality = trackingQuality
        self.responseConsistency = responseConsistency
        self.warnings = warnings
        self.recommendedAction = recommendedAction
    }
}

struct ScreeningSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    var deviceProfile: DeviceProfile?
    /// True only after exact-model physical calibration and second-face
    /// detection gates pass. A missing value from an older session means false.
    var numericResultsAllowed: Bool?
    var baselineDistanceMetres: Double?
    var rightEyeTrials: [TrialBlock]
    var leftEyeTrials: [TrialBlock]
    var rightEyeResult: EyeScreeningResult?
    var leftEyeResult: EyeScreeningResult?
    var rightGaborTrials: [GaborTrial]?
    var leftGaborTrials: [GaborTrial]?
    var rightGaborResult: GaborScreeningResult?
    var leftGaborResult: GaborScreeningResult?

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        deviceProfile = nil
        numericResultsAllowed = false
        baselineDistanceMetres = nil
        rightEyeTrials = []
        leftEyeTrials = []
        rightEyeResult = nil
        leftEyeResult = nil
        rightGaborTrials = []
        leftGaborTrials = []
        rightGaborResult = nil
        leftGaborResult = nil
    }
}
