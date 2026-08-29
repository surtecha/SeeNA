import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class PermissionsViewModel {
    private(set) var cameraGranted: Bool
    private(set) var microphoneGranted: Bool
    private(set) var requestCompleted = false
    private(set) var isRequesting = false

    private let audioRecorder: AudioBlockRecorder
    private let prompts: SpokenPromptService
    let guideDescription: String

    init(
        audioRecorder: AudioBlockRecorder,
        prompts: SpokenPromptService,
        guideDescription: String = "Natural female guide, with an on-device fallback"
    ) {
        self.audioRecorder = audioRecorder
        self.prompts = prompts
        self.guideDescription = guideDescription
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVAudioApplication.shared.recordPermission
        cameraGranted = cameraStatus == .authorized
        microphoneGranted = microphoneStatus == .granted
        requestCompleted = cameraStatus != .notDetermined && microphoneStatus != .undetermined
    }

    var primaryTitle: String {
        if isRequesting { return "Requesting access" }
        if cameraGranted && microphoneGranted { return "Continue with voice" }
        if cameraGranted { return "Continue with operator input" }
        if cameraPermanentlyDenied { return "Open Settings" }
        return requestCompleted ? "Try again" : "Allow camera & voice"
    }

    var primarySystemImage: String {
        requestCompleted ? "arrow.right" : "lock.open"
    }

    var cameraPermanentlyDenied: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .denied }
    var microphonePermanentlyDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }
    var isPermanentlyDenied: Bool { cameraPermanentlyDenied || microphonePermanentlyDenied }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func cancel() {
        prompts.stop()
        audioRecorder.stop()
    }

    func primaryAction(session: AppSession) async {
        guard session.didTapStart else { return }
        refreshAuthorizationState()
        if cameraGranted {
            HapticFeedback.impact()
            session.responseMode = microphoneGranted ? .voicePreferred : .operatorOnly
            session.navigate(to: .deviceCheck)
            return
        }
        if cameraPermanentlyDenied {
            openSettings()
            prompts.speak("Camera access is required. Use Open Settings, then return to SeeNA. Microphone access is optional because operator input is available.")
            return
        }
        await requestPermissions(session: session)
    }

    func begin(session: AppSession) async {
        guard session.didTapStart else { return }
        refreshAuthorizationState()
        if cameraGranted {
            return
        }
        guard !requestCompleted else { return }
        prompts.speak("Tap Allow for camera, then microphone.")
        await requestPermissions(session: session)
    }

    private func requestPermissions(session: AppSession) async {
        guard session.didTapStart, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }

        microphoneGranted = await audioRecorder.requestPermission()
        requestCompleted = true

        if cameraGranted {
            HapticFeedback.success()
            session.responseMode = microphoneGranted ? .voicePreferred : .operatorOnly
            session.navigate(to: .deviceCheck)
        } else {
            HapticFeedback.warning()
            prompts.speak(
                cameraPermanentlyDenied
                    ? "Camera access is off. Open Settings to enable it. Microphone access is optional because operator input is available."
                    : "Camera access is required for this screening. You can try again."
            )
        }
    }

    func refreshAuthorizationState() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVAudioApplication.shared.recordPermission
        cameraGranted = cameraStatus == .authorized
        microphoneGranted = microphoneStatus == .granted
        requestCompleted = cameraStatus != .notDetermined && microphoneStatus != .undetermined
    }
}

@MainActor
@Observable
final class DeviceCheckViewModel {
    private(set) var tier: DeviceCapabilityTier?
    private(set) var networkConnected = false
    private(set) var networkExpensive = false
    private(set) var microphoneGranted = false

    private let registry: DeviceProfileRegistry
    private let sensors: SensorCoordinator
    private let prompts: SpokenPromptService
    private let network: NetworkReachabilityService
    private let allowMockSensors: Bool

    init(
        registry: DeviceProfileRegistry,
        sensors: SensorCoordinator,
        prompts: SpokenPromptService,
        network: NetworkReachabilityService
    ) {
        self.registry = registry
        self.sensors = sensors
        self.prompts = prompts
        self.network = network
#if DEBUG
        allowMockSensors = sensors.isUsingMockData
#else
        allowMockSensors = false
#endif
    }

    var hardwareIdentifier: String {
        allowMockSensors ? "iPhone simulator" : registry.hardwareIdentifier
    }
    var isMockJourney: Bool { allowMockSensors }

    var activeProfile: DeviceProfile? {
        if case .fullScreening(let profile) = tier { return profile }
        return registry.profile()
    }

    var faceTrackingReady: Bool { allowMockSensors || sensors.faceTrackingSupported }
    var motionReady: Bool { allowMockSensors || sensors.motionSupported }
    var secondFaceReady: Bool { sensors.supportsSecondFaceDetection }

    var heading: String {
        switch tier {
        case .fullScreening: return "Device ready"
        case .accessibilityOnly, .unsupported: return "Screening unavailable"
        case nil: return "Checking this iPhone"
        }
    }

    var microphoneDetail: String {
        microphoneGranted ? "Ready" : "Use touch responses"
    }

    var networkDetail: String {
        networkConnected ? "Ready" : "Use touch responses"
    }

    var outcomeText: String {
        switch tier {
        case .fullScreening:
            return "All checks passed. You’re ready to begin."
        case .accessibilityOnly, .unsupported:
            return "This device cannot run the full screening yet."
        case nil: return "Checking device capabilities…"
        }
    }

    var continueTitle: String {
        if case .fullScreening = tier { return "Continue" }
        return "Back to start"
    }

    var canContinue: Bool {
        if case .fullScreening = tier { return true }
        return false
    }

    func begin(session: AppSession) async {
        refreshRuntimeRows()
        assess(session: session)
        guard case .fullScreening = tier else { return }
        _ = await prompts.speakForTransition(
            "Device ready. Set the phone upright at eye level."
        )
#if DEBUG
        if sensors.isSimulatorVoiceAutomationEnabled,
           session.path.last == .deviceCheck {
            continueJourney(session: session)
        }
#endif
    }

    func assess(session: AppSession) {
        let assessment = registry.capabilityTier(allowMockSensors: allowMockSensors)
        tier = assessment
        session.capabilityTier = assessment
        guard case .fullScreening(let profile) = assessment else { return }
        session.activeSession.deviceProfile = profile
        session.activeSession.numericResultsAllowed = NumericResultEligibility.allowsNumericResults(
            profile: profile,
            supportsSecondFaceDetection: secondFaceReady,
            matchesExactRuntimeDevice: !allowMockSensors && registry.isExactRuntimeProfile(profile)
        )
    }

    func continueJourney(session: AppSession) {
        if case .fullScreening = tier {
            prompts.stop()
            session.navigate(to: .phoneSetup)
        } else {
            session.appError = .sensorUnavailable("A supported TrueDepth iPhone")
        }
    }

    func cancel() {
        prompts.stop()
    }

    func refreshRuntimeRows() {
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        networkConnected = network.isConnected
        networkExpensive = network.usesExpensiveInterface
    }
}

@MainActor
@Observable
final class PhoneSetupViewModel {
    private(set) var sample: DistanceSample?
    private(set) var isLocked = false
    private var announcedReady = false
    private var readySince: Date?
    private var isAdvancing = false
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = UUID()
    private var hasStarted = false
    private var gazeTracker = GazeReadinessTracker()
    private(set) var gazeState: GazeReadiness = .unavailable

    private let sensors: SensorCoordinator
    private let prompts: SpokenPromptService

    init(sensors: SensorCoordinator, prompts: SpokenPromptService) {
        self.sensors = sensors
        self.prompts = prompts
    }

    var faceReady: Bool { sample?.faceCount == 1 }
    var phoneReady: Bool { sample?.phoneStable == true }
    var lightReady: Bool { (sample?.luminance ?? 0) >= 0.12 }
    var gazeReady: Bool { gazeState == .aligned }

    var isReady: Bool {
        faceReady && phoneReady && lightReady && gazeReady
    }

    var readinessProgress: Double {
        let checks = [faceReady, phoneReady, lightReady, gazeReady]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    var distanceLabel: String {
        measuredDistance.map { String(format: "%.2f m", $0) } ?? "—"
    }

    var instruction: String {
        guard sample != nil else { return "Finding you" }
        if !faceReady { return "One face in frame" }
        if !phoneReady { return "Let the phone settle" }
        if !lightReady { return "Add more light" }
        if gazeState == .unavailable { return "Look at the centre" }
        if !gazeReady { return "Look at the centre" }
        return isLocked ? "Position locked" : "Ready to lock"
    }

    var primaryTitle: String { isLocked ? "Continue" : "Lock position" }
    var primarySystemImage: String { isLocked ? "arrow.right" : "lock" }
    var primaryEnabled: Bool { isReady && !isAdvancing }

    var gazeOffset: CGSize {
        guard let sample else { return .zero }
        return CGSize(
            width: min(18, max(-18, (sample.gazeYawErrorDegrees ?? 18) * 1.1)),
            height: min(12, max(-12, (sample.gazePitchErrorDegrees ?? 12) * 0.8))
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        sensors.start()
        prompts.preloadNavigationGuidance(additionalTexts: [
            "Distance saved. Cover your left eye."
        ])
        prompts.speak("Set the phone upright at eye level. Step into view, then let go.")
    }

    func observe(_ sample: DistanceSample?, session: AppSession) {
        self.sample = sample
        gazeState = gazeTracker.update(
            yawErrorDegrees: sample?.gazeYawErrorDegrees,
            pitchErrorDegrees: sample?.gazePitchErrorDegrees
        )
        if isReady && !announcedReady {
            announcedReady = true
            HapticFeedback.success()
        } else if !isReady {
            announcedReady = false
        }

        if isReady, !isLocked, !isAdvancing {
            readySince = readySince ?? Date()
            if Date().timeIntervalSince(readySince ?? Date()) >= 0.6 {
                isAdvancing = true
                sensors.lockPhoneReference()
                isLocked = true
                HapticFeedback.impact(.rigid)
                advanceAfterLock(session: session)
            }
        } else if !isReady {
            readySince = nil
        }
    }

    func primaryAction(session: AppSession) {
        if isLocked {
            HapticFeedback.impact()
            session.navigate(to: .calibration)
            return
        }

        guard isReady, !isAdvancing else {
            HapticFeedback.warning()
            return
        }
        isAdvancing = true
        sensors.lockPhoneReference()
        isLocked = true
        HapticFeedback.impact(.rigid)
        advanceAfterLock(session: session)
    }

    func replayGuide() {
        HapticFeedback.selection()
        prompts.speak("Set the phone upright at eye level. Keep it still, centre one face, and look at the middle.")
    }

    func stopIfLeavingSetup(nextRoute: AppRoute?) {
        transitionGeneration = UUID()
        transitionTask?.cancel()
        transitionTask = nil
        isAdvancing = false
        prompts.stop()
        if nextRoute != .calibration {
            sensors.stop()
        }
    }

    func sensorStreamInvalidated() {
        transitionGeneration = UUID()
        transitionTask?.cancel()
        transitionTask = nil
        sample = nil
        readySince = nil
        announcedReady = false
        isLocked = false
        isAdvancing = false
        gazeTracker.reset()
        gazeState = .unavailable
        prompts.stop()
        prompts.speak("Tracking paused. Reposition the phone and look at the centre.")
    }

    private func advanceAfterLock(session: AppSession) {
        transitionTask?.cancel()
        let generation = UUID()
        transitionGeneration = generation
        transitionTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await prompts.speakForTransition("Phone locked. Move close.")
            let shouldAdvance = CompletionNavigationPolicy.shouldAdvance(
                after: outcome,
                expectedRoute: AppRoute.phoneSetup,
                currentRoute: session.path.last,
                expectedGeneration: generation,
                currentGeneration: transitionGeneration,
                taskIsCancelled: Task.isCancelled
            )
            guard generation == transitionGeneration else { return }
            transitionTask = nil
            isAdvancing = false
            guard shouldAdvance else { return }
            session.navigate(to: .calibration)
        }
    }

    private var measuredDistance: Double? {
        sample?.correctedDistanceMetres ?? sample?.fusedDistanceMetres ?? sample?.rawARDistanceMetres
    }
}

@MainActor
@Observable
final class CalibrationViewModel {
    private(set) var sample: DistanceSample?
    private(set) var didCapture = false
    private(set) var guidedDistance: Double?
    private(set) var isInTargetZone = false
    private var announcedReady = false
    private var targetReady = false
    private var isAdvancing = false
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = UUID()
    private var distanceFilter = RobustDistanceFilter()
    private var targetTracker = DistanceTargetTracker()
    private var voiceScheduler = VoiceGuidanceScheduler()
    private var hasStarted = false
    private var gazeTracker = GazeReadinessTracker()
    private(set) var gazeState: GazeReadiness = .unavailable

    private let sensors: SensorCoordinator
    private let prompts: SpokenPromptService
    private let brightness: BrightnessManager

    init(sensors: SensorCoordinator, prompts: SpokenPromptService, brightness: BrightnessManager) {
        self.sensors = sensors
        self.prompts = prompts
        self.brightness = brightness
    }

    var measuredDistance: Double? {
        guidedDistance
    }

    var distanceLabel: String {
        measuredDistance.map { String(format: "%.2f m", $0) } ?? "—"
    }

    var headReady: Bool {
        guard let sample else { return false }
        return sample.faceCount == 1
            && abs(sample.headYawDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            && abs(sample.headPitchDegrees) <= FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
    }

    var trackingReady: Bool {
        sample?.phoneStable == true
            && headReady
            && (sample?.luminance ?? 0) >= 0.12
            && gazeState == .aligned
    }

    var isReady: Bool {
        targetReady && trackingReady
    }

    var proximityProgress: Double {
        guard let measuredDistance else { return 0 }
        return min(1, max(0, 1 - abs(measuredDistance - 0.40) / 0.30))
    }

    var instruction: String {
        guard let measuredDistance else { return "Step into view" }
        if !headReady { return "Face the phone" }
        if sample?.phoneStable != true { return "Keep the phone still" }
        if measuredDistance < 0.37 {
            return "Move back \(Int(((0.40 - measuredDistance) * 100).rounded())) cm"
        }
        if measuredDistance > 0.43 {
            return "Move closer \(Int(((measuredDistance - 0.40) * 100).rounded())) cm"
        }
        return didCapture ? "Baseline saved" : "Hold still"
    }

    var primaryTitle: String { didCapture ? "Continue" : "Capture 40 cm" }
    var primarySystemImage: String { didCapture ? "arrow.right" : "scope" }
    var primaryEnabled: Bool { didCapture ? !isAdvancing : isReady && !isAdvancing }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        brightness.applyScreeningBrightness()
        sensors.start()
        prompts.preloadNavigationGuidance()
        prompts.beginNavigationGuidance()
        voiceScheduler.begin(at: Date().timeIntervalSinceReferenceDate)
        prompts.speak("Step into view. I will guide you to forty centimetres.")
    }

    func observe(_ sample: DistanceSample?, session: AppSession) {
        self.sample = sample
        gazeState = gazeTracker.update(
            yawErrorDegrees: sample?.gazeYawErrorDegrees,
            pitchErrorDegrees: sample?.gazePitchErrorDegrees
        )
        let measured = sample.flatMap {
            $0.correctedDistanceMetres ?? $0.fusedDistanceMetres ?? $0.rawARDistanceMetres
        }
        guidedDistance = distanceFilter.update(measured)
        guard !didCapture, !isAdvancing else { return }
        let timestamp = sample?.timestamp.timeIntervalSinceReferenceDate
            ?? Date().timeIntervalSinceReferenceDate
        let state = targetTracker.update(
            distance: guidedDistance,
            target: 0.40,
            conditionsReady: trackingReady,
            timestamp: timestamp
        )
        let cue = conditionCue(for: sample)
            ?? (state.isInTargetZone ? .stop : guidedDistance.map {
                DistanceGuidanceEngine.cue(currentDistance: $0, targetDistance: 0.40)
            })
            ?? .findFace
        if voiceScheduler.shouldAnnounce(cue, at: timestamp) {
            prompts.queueNavigationCue(cue.spokenText)
        }
        isInTargetZone = state.isInTargetZone
        targetReady = state.isReady

        if isInTargetZone && !announcedReady {
            announcedReady = true
            HapticFeedback.success()
        } else if !isInTargetZone {
            announcedReady = false
        }

        if isReady, !didCapture, !isAdvancing {
            isAdvancing = true
            capture(session: session, shouldAdvance: true)
        }
    }

    func primaryAction(session: AppSession) {
        if didCapture {
            guard !isAdvancing else { return }
            HapticFeedback.impact()
            session.navigate(to: .rightEyeInstructions)
            return
        }
        capture(session: session, shouldAdvance: false)
    }

    func replayGuide() {
        HapticFeedback.selection()
        voiceScheduler.begin(at: Date().timeIntervalSinceReferenceDate)
        prompts.beginNavigationGuidance()
        prompts.speak("I will guide you to forty centimetres. Face the phone and follow the voice.")
    }

    private func conditionCue(for sample: DistanceSample?) -> DistanceGuidanceCue? {
        guard let sample, sample.faceCount == 1 else { return .findFace }
        if !sample.phoneStable { return .waitForPhone }
        if sample.luminance < 0.12 { return .addLight }
        if gazeState != .aligned { return .lookAtCentre }
        if abs(sample.headYawDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees
            || abs(sample.headPitchDegrees) > FaceAlignmentPolicy.maximumMeasurementHeadAngleDegrees {
            return .facePhone
        }
        return nil
    }

    private func capture(session: AppSession, shouldAdvance: Bool) {
        guard isReady, !didCapture else {
            HapticFeedback.warning()
            return
        }
        isAdvancing = true
        guard sensors.captureBaseline() else {
            isAdvancing = false
            targetReady = false
            isInTargetZone = false
            targetTracker.reset()
            HapticFeedback.warning()
            prompts.speak("Hold still. I will try the distance again.")
            return
        }
        session.activeSession.baselineDistanceMetres = measuredDistance
        didCapture = true
        voiceScheduler.acceptTarget()
        HapticFeedback.success()
        transitionTask?.cancel()
        let generation = UUID()
        transitionGeneration = generation
        transitionTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await prompts.speakAfterNavigationForTransition(
                "Distance saved. Cover your left eye."
            )
            let shouldNavigate = CompletionNavigationPolicy.shouldAdvance(
                after: outcome,
                expectedRoute: AppRoute.calibration,
                currentRoute: session.path.last,
                expectedGeneration: generation,
                currentGeneration: transitionGeneration,
                taskIsCancelled: Task.isCancelled
            )
            guard generation == transitionGeneration else { return }
            transitionTask = nil
            isAdvancing = false
            guard shouldAdvance, shouldNavigate else { return }
            session.navigate(to: .rightEyeInstructions)
        }
    }

    func cancel() {
        transitionGeneration = UUID()
        transitionTask?.cancel()
        transitionTask = nil
        isAdvancing = false
        prompts.stop()
    }

    func sensorStreamInvalidated() {
        transitionGeneration = UUID()
        transitionTask?.cancel()
        transitionTask = nil
        sample = nil
        guidedDistance = nil
        didCapture = false
        targetReady = false
        isInTargetZone = false
        isAdvancing = false
        distanceFilter.reset()
        targetTracker.reset()
        gazeTracker.reset()
        gazeState = .unavailable
        prompts.stop()
        prompts.beginNavigationGuidance()
        prompts.speak("Tracking paused. I will guide you back to forty centimetres.")
    }
}
