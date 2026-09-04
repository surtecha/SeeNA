import AVFoundation
import Combine
import Foundation

struct AudioRecordingResult: Sendable {
    let fileURL: URL
    let adequateLevel: Bool
    let duration: TimeInterval
}

@MainActor
final class AudioBlockRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = -80

    private var recorder: AVAudioRecorder?
    private var recordingRequestActive = false
    private var stopWasRequested = false
    private let activityConfiguration: VoiceActivityConfiguration

    init(activityConfiguration: VoiceActivityConfiguration = .screeningAnswer) {
        self.activityConfiguration = activityConfiguration
        super.init()
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func record(maximumDuration: TimeInterval = 12) async throws -> AudioRecordingResult {
        guard !recordingRequestActive, recorder == nil, !isRecording else {
            throw RecordingError.alreadyRecording
        }
        recordingRequestActive = true
        stopWasRequested = false
        defer { recordingRequestActive = false }
        guard await requestPermission() else { throw RecordingError.permissionDenied }
        try Task.checkCancellation()
        guard !stopWasRequested else {
            stopWasRequested = false
            throw CancellationError()
        }
        let session = AVAudioSession.sharedInstance()
        var sessionIsActive = false
        defer {
            if sessionIsActive {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        sessionIsActive = true

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seena-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record(forDuration: min(max(maximumDuration, 1), 20)) else {
            cleanup(url: fileURL)
            throw RecordingError.couldNotStart
        }
        self.recorder = recorder
        isRecording = true

        let start = Date()
        var activityDetector = VoiceActivityDetector(configuration: activityConfiguration)

        do {
            while recorder.isRecording {
                try Task.checkCancellation()
                recorder.updateMeters()
                level = recorder.averagePower(forChannel: 0)
                let decision = activityDetector.observe(
                    averagePowerDB: level,
                    peakPowerDB: recorder.peakPower(forChannel: 0),
                    elapsed: Date().timeIntervalSince(start)
                )
                if case .stop = decision {
                    recorder.stop()
                }
                let interval = max(activityConfiguration.sampleIntervalHint, 0.04)
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        } catch {
            recorder.stop()
            cleanup(url: fileURL)
            isRecording = false
            level = -80
            self.recorder = nil
            stopWasRequested = false
            throw error
        }

        isRecording = false
        level = -80
        self.recorder = nil
        if stopWasRequested || Task.isCancelled {
            stopWasRequested = false
            cleanup(url: fileURL)
            throw CancellationError()
        }
        return AudioRecordingResult(
            fileURL: fileURL,
            adequateLevel: activityDetector.capturedPlausibleSpeech,
            duration: Date().timeIntervalSince(start)
        )
    }

    func stop() {
        stopWasRequested = recordingRequestActive || recorder != nil
        recorder?.stop()
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum RecordingError: LocalizedError {
        case permissionDenied
        case couldNotStart
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission is required for voice responses."
            case .couldNotStart: return "SeeNA could not start the voice recording."
            case .alreadyRecording: return "A voice response is already being recorded."
            }
        }
    }
}
