import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class WelcomeViewModel {
    private(set) var distanceMetres = 0.72
    private(set) var pulse = false
    private var lastHapticStep = -1

    var progress: Double {
        min(1, max(0, (distanceMetres - 0.40) / 1.60))
    }

    var distanceLabel: String {
        distanceMetres < 1
            ? "\(Int((distanceMetres * 100).rounded())) cm"
            : String(format: "%.2f m", distanceMetres)
    }

    var targetDiameter: Double {
        42 + progress * 72
    }

    func setDistance(progress: Double) {
        let bounded = min(1, max(0, progress))
        distanceMetres = 0.40 + bounded * 1.60
        let hapticStep = Int((bounded * 8).rounded(.down))
        if hapticStep != lastHapticStep {
            lastHapticStep = hapticStep
            HapticFeedback.selection()
        }
    }

    func startMotion(reduceMotion: Bool) {
        guard !reduceMotion else { return }
        pulse = true
    }

    func begin(session: AppSession) {
        HapticFeedback.impact(.medium)
        session.navigate(to: .eligibility)
    }
}

@MainActor
@Observable
final class PermissionsViewModel {
    private(set) var cameraGranted: Bool
    private(set) var microphoneGranted: Bool
    private(set) var requestCompleted = false
    private(set) var isRequesting = false

    private let audioRecorder: AudioBlockRecorder

    init(audioRecorder: AudioBlockRecorder) {
        self.audioRecorder = audioRecorder
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVAudioApplication.shared.recordPermission
        cameraGranted = cameraStatus == .authorized
        microphoneGranted = microphoneStatus == .granted
        requestCompleted = cameraStatus != .notDetermined && microphoneStatus != .undetermined
    }

    var primaryTitle: String {
        if isRequesting { return "Requesting access" }
        return requestCompleted ? "Continue" : "Allow camera & voice"
    }

    var primarySystemImage: String {
        requestCompleted ? "arrow.right" : "lock.open"
    }

    func primaryAction(session: AppSession) async {
        if requestCompleted {
            if !cameraGranted {
                session.isAccessibilityOnly = true
            }
            HapticFeedback.impact()
            session.navigate(to: .deviceCheck)
            return
        }
        await requestPermissions(session: session)
    }

    private func requestPermissions(session: AppSession) async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }

        microphoneGranted = await audioRecorder.requestPermission()
        requestCompleted = true

        if !cameraGranted {
            session.isAccessibilityOnly = true
        }

        if cameraGranted && microphoneGranted {
            HapticFeedback.success()
        } else {
            HapticFeedback.warning()
        }
    }
}

@MainActor
@Observable
final class PhoneSetupViewModel {
    private(set) var sample: DistanceSample?
    private(set) var isLocked = false
    private var announcedReady = false

    private let sensors: SensorCoordinator
    private let prompts: SpokenPromptService

    init(sensors: SensorCoordinator, prompts: SpokenPromptService) {
        self.sensors = sensors
        self.prompts = prompts
    }

    var faceReady: Bool { sample?.faceCount == 1 }
    var phoneReady: Bool { sample?.phoneStable == true }
    var gazeReady: Bool {
        guard let sample else { return false }
        return abs(sample.headYawDegrees) <= 10 && abs(sample.headPitchDegrees) <= 10
    }
    var lightReady: Bool { (sample?.luminance ?? 0) >= 0.12 }

    var isReady: Bool {
        faceReady && phoneReady && gazeReady && lightReady
    }

    var readinessProgress: Double {
        let checks = [faceReady, phoneReady, gazeReady, lightReady]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    var distanceLabel: String {
        measuredDistance.map { String(format: "%.2f m", $0) } ?? "—"
    }

    var instruction: String {
        guard sample != nil else { return "Finding you" }
        if !faceReady { return "One face in frame" }
        if !phoneReady { return "Stop touching the phone" }
        if !gazeReady { return "Look at the centre" }
        if !lightReady { return "Add more light" }
        return isLocked ? "Position locked" : "Ready to lock"
    }

    var primaryTitle: String { isLocked ? "Continue" : "Lock position" }
    var primarySystemImage: String { isLocked ? "arrow.right" : "lock" }
    var primaryEnabled: Bool { isReady }

    var gazeOffset: CGSize {
        guard let sample else { return .zero }
        return CGSize(
            width: min(18, max(-18, sample.headYawDegrees * 1.25)),
            height: min(12, max(-12, sample.headPitchDegrees * 0.9))
        )
    }

    func start() {
        sensors.start()
    }

    func observe(_ sample: DistanceSample?) {
        self.sample = sample
        if isReady && !announcedReady {
            announcedReady = true
            HapticFeedback.success()
        } else if !isReady {
            announcedReady = false
        }
    }

    func primaryAction(session: AppSession) {
        if isLocked {
            HapticFeedback.impact()
            session.navigate(to: .calibration)
            return
        }

        guard isReady else {
            HapticFeedback.warning()
            return
        }
        sensors.lockPhoneReference()
        isLocked = true
        HapticFeedback.impact(.rigid)
        prompts.speak("Phone position locked. Move to forty centimetres.")
    }

    func replayGuide() {
        HapticFeedback.selection()
        prompts.speak("Set the phone upright at eye level. Keep it still, centre one face, and look at the middle.")
    }

    func stopIfLeavingSetup(nextRoute: AppRoute?) {
        if nextRoute != .calibration {
            sensors.stop()
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
    private var announcedReady = false

    private let sensors: SensorCoordinator
    private let prompts: SpokenPromptService
    private let brightness: BrightnessManager

    init(sensors: SensorCoordinator, prompts: SpokenPromptService, brightness: BrightnessManager) {
        self.sensors = sensors
        self.prompts = prompts
        self.brightness = brightness
    }

    var measuredDistance: Double? {
        sample?.correctedDistanceMetres ?? sample?.fusedDistanceMetres ?? sample?.rawARDistanceMetres
    }

    var distanceLabel: String {
        measuredDistance.map { String(format: "%.2f m", $0) } ?? "—"
    }

    var headReady: Bool {
        guard let sample else { return false }
        return sample.faceCount == 1
            && abs(sample.headYawDegrees) <= 10
            && abs(sample.headPitchDegrees) <= 10
    }

    var trackingReady: Bool {
        sample?.phoneStable == true && headReady && (sample?.luminance ?? 0) >= 0.12
    }

    var isReady: Bool {
        guard let measuredDistance else { return false }
        return (0.37...0.43).contains(measuredDistance) && trackingReady
    }

    var proximityProgress: Double {
        guard let measuredDistance else { return 0 }
        return min(1, max(0, 1 - abs(measuredDistance - 0.40) / 0.30))
    }

    var instruction: String {
        guard let measuredDistance else { return "Step into view" }
        if !headReady { return "Look at the centre" }
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
    var primaryEnabled: Bool { didCapture || isReady }

    func start() {
        brightness.applyScreeningBrightness()
        sensors.start()
        prompts.speak("Move slowly until the ring closes at forty centimetres.")
    }

    func observe(_ sample: DistanceSample?) {
        self.sample = sample
        if isReady && !announcedReady {
            announcedReady = true
            HapticFeedback.success()
        } else if !isReady {
            announcedReady = false
        }
    }

    func primaryAction(session: AppSession) {
        if didCapture {
            HapticFeedback.impact()
            session.navigate(to: .rightEyeInstructions)
            return
        }
        capture(session: session)
    }

    func replayGuide() {
        HapticFeedback.selection()
        prompts.speak("Move to forty centimetres, look at the centre, and keep the phone completely still.")
    }

    private func capture(session: AppSession) {
        guard isReady, sensors.captureBaseline() else {
            HapticFeedback.warning()
            session.appError = .invalidState
            return
        }
        session.activeSession.baselineDistanceMetres = measuredDistance
        didCapture = true
        HapticFeedback.success()
        prompts.speak("Baseline saved. Cover your left eye next.")
    }
}
