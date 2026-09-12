import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Extract specified film frames and report the actual media properties.
/// Usage: InspectLaunchMedia source.mp4 output-directory 0 10 30 60 89
@main
enum InspectLaunchMedia {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { fatalError("Expected source, output directory and seconds") }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for value in args.dropFirst(3) {
            guard let seconds = Double(value), seconds >= 0 else { fatalError("Invalid timestamp") }
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let url = output.appendingPathComponent("frame-\(value).jpg")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { fatalError("Image write failed") }
        }
        let duration = try await asset.load(.duration).seconds
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let audio = try await asset.loadTracks(withMediaType: .audio).count
        print("Duration \(duration); size \(size); fps \(fps); audio tracks \(audio)")
        if audio > 0 {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
            var peak: Float = 0
            var squares = 0.0
            var samples = 0
            while file.framePosition < file.length {
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        let value = buffer.floatChannelData![channel][frame]
                        guard value.isFinite else { fatalError("Non-finite audio sample") }
                        peak = max(peak, abs(value))
                        squares += Double(value * value)
                        samples += 1
                    }
                }
            }
            guard samples > 0, peak > 0, peak < 1 else { fatalError("Silent or clipped decoded audio") }
            print("Decoded audio: \(file.processingFormat.channelCount) channels; \(file.processingFormat.sampleRate) Hz; peak \(20 * log10(Double(peak))) dBFS; RMS \(20 * log10(sqrt(squares / Double(samples)))) dBFS")
        }
    }
}
