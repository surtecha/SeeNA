import AVFoundation
import CryptoKit
import Foundation

// Original procedural music and editorial sound design. No samples or speech.
// Usage: ScoreLaunchFilm silent-film.mp4 scored-film.mp4
@main
enum ScoreLaunchFilm {
    static let rate = 48_000.0
    static let duration = 90.0
    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Supply input and new output paths") }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output already exists") }
        let count = Int(rate * duration)
        var left = [Float](repeating: 0, count: count)
        var right = left
        var seed: UInt64 = 0x5345454E41
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64.max >> 11) * 2 - 1
        }
        func add(start: Double, length: Double, gain: Double, pan: Double = 0,
                 wave: (Double) -> Double) {
            let first = max(0, Int(start * rate))
            let end = min(count, Int((start + length) * rate))
            guard end > first else { return }
            let l = gain * sqrt((1 - pan) * 0.5)
            let r = gain * sqrt((1 + pan) * 0.5)
            for i in first..<end {
                let t = Double(i) / rate - start
                let value = wave(t)
                left[i] += Float(value * l)
                right[i] += Float(value * r)
            }
        }
        func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        func pluck(at: Double, note: Int, gain: Double, pan: Double) {
            let f = frequency(note)
            for (delay, level, position) in [(0.0, 1.0, pan), (0.375, 0.25, -pan), (0.75, 0.10, pan)] {
                add(start: at + delay, length: 2, gain: gain * level, pan: position) { t in
                    let envelope = (1 - exp(-t * 220)) * exp(-t * 3.8)
                    return envelope * (sin(2 * .pi * f * t) + 0.20 * sin(4 * .pi * f * t) * exp(-t * 5))
                }
            }
        }
        // 120 BPM: warm extended chords, soft pulse, sparse stereo plucks.
        let chords = [[50, 57, 61, 66, 69], [47, 54, 57, 62, 66],
                      [43, 50, 57, 59, 66], [45, 52, 57, 62, 64]]
        for bar in 0..<21 {
            let at = Double(bar) * 4
            let chord = chords[bar % 4]
            let energy = at < 8 ? 0.65 : (at >= 64 && at < 76 ? 0.7 : 1.0)
            for (index, note) in chord.enumerated() {
                let f = frequency(note)
                add(start: at, length: 5.2, gain: 0.038 * energy, pan: Double(index - 2) * 0.22) { t in
                    let envelope = min(1, t / 0.7) * min(1, max(0, (5.2 - t) / 1.4))
                    return envelope * (sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 1.002 * t))
                }
            }
            for beat in 0..<8 {
                let onset = at + Double(beat) * 0.5
                if at >= 8 {
                    add(start: onset, length: 0.24, gain: 0.12 * energy) { t in
                        (1 - exp(-t * 700)) * exp(-t * 22) * sin(2 * .pi * (48 * t + 1.9 * (1 - exp(-t * 32))))
                    }
                    if beat % 2 == 1 {
                        add(start: onset, length: 0.065, gain: 0.023 * energy, pan: 0.2) { t in
                            noise() * (1 - exp(-t * 1400)) * exp(-t * 90)
                        }
                    }
                }
            }
            for (index, offset) in [0.0, 0.75, 1.5, 2.75].enumerated() {
                pluck(at: at + offset, note: chord[[2, 4, 3, 4][index]] + 12,
                      gain: 0.095 * energy, pan: index % 2 == 0 ? -0.35 : 0.35)
            }
        }
        // A gentle air transition and tonal tick at actual chapter edits.
        let cuts = [8.0, 16, 30, 42, 47, 52, 58, 64, 76, 84]
        for cut in cuts {
            var filtered = 0.0
            add(start: cut - 0.4, length: 0.7, gain: 0.044, pan: -0.1) { t in
                filtered = filtered * 0.87 + noise() * 0.13
                return filtered * pow(sin(.pi * t / 0.7), 2) * 3
            }
            pluck(at: cut, note: cut == 84 ? 78 : 81, gain: 0.05, pan: 0.15)
        }
        for (index, note) in [50, 57, 62, 66, 69, 76].enumerated() {
            let f = frequency(note)
            add(start: 84 + Double(index) * 0.035, length: 6, gain: 0.065,
                pan: Double(index) * 0.15 - 0.375) { t in
                (1 - exp(-t * 15)) * exp(-t * 0.7) * sin(2 * .pi * f * t)
            }
        }
        // Fade all tails gracefully. Peak normalise to -3 dBFS, without clipping.
        var peak: Float = 0
        for i in 0..<count {
            let t = Double(i) / rate
            let fade = Float(min(1, t / 1.25) * min(1, max(0, (duration - t) / 2.5)))
            left[i] *= fade; right[i] *= fade
            peak = max(peak, abs(left[i]), abs(right[i]))
        }
        let scale = Float(pow(10, -3.0 / 20)) / max(peak, 0.0001)
        var sum = 0.0
        for i in 0..<count {
            left[i] *= scale; right[i] *= scale
            sum += Double(left[i] * left[i] + right[i] * right[i])
        }
        let rms = 20 * log10(sqrt(sum / Double(count * 2)))
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = buffer.frameCapacity
        left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: count) }
        right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: count) }
        let wav = output.deletingPathExtension().appendingPathExtension("wav")
        guard !FileManager.default.fileExists(atPath: wav.path) else { fatalError("Soundtrack path already exists") }
        do {
            let audio = try AVAudioFile(forWriting: wav, settings: format.settings)
            try audio.write(from: buffer)
        }
        let composition = AVMutableComposition()
        let source = AVURLAsset(url: input)
        guard abs(try await source.load(.duration).seconds - duration) < 0.034 else { fatalError("Input must be 90 seconds") }
        let videoSource = try await source.loadTracks(withMediaType: .video)[0]
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: time(duration)), of: videoSource, at: .zero)
        video.preferredTransform = try await videoSource.load(.preferredTransform)
        let audioAsset = AVURLAsset(url: wav)
        let audioSource = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: time(duration)), of: audioSource, at: .zero)
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080)!
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: time(duration))
        try await exporter.export(to: output, as: .mp4)
        let final = AVURLAsset(url: output)
        let seconds = try await final.load(.duration).seconds
        let audioTracks = try await final.loadTracks(withMediaType: .audio).count
        guard abs(seconds - duration) < 0.001, audioTracks == 1 else { fatalError("Invalid final export") }
        let data = try Data(contentsOf: output)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = ["durationSeconds": seconds, "width": 1920, "height": 1080,
            "fps": 30, "audioTracks": audioTracks, "voiceover": false,
            "soundtrack": "Original procedural instrumental and chapter-synchronised effects; no external samples.",
            "sourceAudioPeakDBFS": -3, "sourceAudioRMSDBFS": rms, "sha256": hash, "bytes": data.count,
            "provenance": "Actual SeeNA simulator recordings; synthetic QA responses and edited timing, not clinical evidence."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingPathExtension().appendingPathExtension("manifest.json"))
        print("Verified 90 seconds, one instrumental stereo track, no voiceover. PCM RMS: \(rms) dBFS. SHA256: \(hash)")
    }
}
