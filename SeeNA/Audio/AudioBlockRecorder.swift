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

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func record(maximumDuration: TimeInterval = 12) async throws -> AudioRecordingResult {
        guard await requestPermission() else { throw RecordingError.permissionDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

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
        guard recorder.record(forDuration: maximumDuration) else { throw RecordingError.couldNotStart }
        self.recorder = recorder
        isRecording = true

        let start = Date()
        var heardSpeech = false
        var lastSpeech = start
        var peak: Float = -80

        do {
            while recorder.isRecording {
                try Task.checkCancellation()
                recorder.updateMeters()
                level = recorder.averagePower(forChannel: 0)
                peak = max(peak, recorder.peakPower(forChannel: 0))
                if level > -38 {
                    heardSpeech = true
                    lastSpeech = Date()
                }
                if heardSpeech, Date().timeIntervalSince(lastSpeech) >= 1.2, Date().timeIntervalSince(start) >= 2 {
                    recorder.stop()
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            recorder.stop()
            cleanup(url: fileURL)
            isRecording = false
            self.recorder = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        isRecording = false
        self.recorder = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return AudioRecordingResult(
            fileURL: fileURL,
            adequateLevel: heardSpeech && peak > -32,
            duration: Date().timeIntervalSince(start)
        )
    }

    func stop() {
        recorder?.stop()
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum RecordingError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission is required for voice responses."
            case .couldNotStart: return "SEENA could not start the voice recording."
            }
        }
    }
}
