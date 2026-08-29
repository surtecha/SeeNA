import AVFoundation
import CryptoKit
import Foundation

private enum MergeFailure: LocalizedError {
    case usage(String)
    case invalidInput(String)
    case media(String)
    case export(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message),
             .invalidInput(let message),
             .media(let message),
             .export(let message):
            return message
        }
    }
}

private struct Clip {
    let url: URL
    let asset: AVURLAsset
    let track: AVAssetTrack
    let timeRange: CMTimeRange
    let preferredTransform: CGAffineTransform
    let naturalSize: CGSize
    let displayRect: CGRect

    var displaySize: CGSize {
        CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
    }
}

private struct FileRecord: Codable {
    let filename: String
    let bytes: Int64
    let sha256: String
    let sourceDurationSeconds: Double
    let timelineDurationSeconds: Double
}

private struct OutputRecord: Codable {
    let filename: String
    let bytes: Int64
    let sha256: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let framesPerSecond: Float
    let videoTrackCount: Int
    let audioTrackCount: Int
    let muted: Bool
}

private struct ExportManifest: Codable {
    let schemaVersion: Int
    let generatedAtUTC: String
    let composition: String
    let sources: [FileRecord]
    let output: OutputRecord
}

@main
private enum MergeMutedDemo {
    private static let timescale: CMTimeScale = 600
    private static let framesPerSecond: CMTimeScale = 30
    private static let journeySeconds = 60.0
    private static let journeyContentSeconds = 55.0
    private static let cleanResultHoldSeconds = journeySeconds - journeyContentSeconds
    private static let resultsMainStartSeconds = 5.5
    private static let resultsEndTrimSeconds = 0.4
    private static let resultsSeconds = 20.0
    private static let totalSeconds = journeySeconds + resultsSeconds
    private static let durationTolerance = 1.0 / 600.0

    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 3 || arguments.count == 4 else {
                throw MergeFailure.usage(
                    "Usage: MergeMutedDemo <60-second-journey.mp4> <results.mp4> <output.mp4> [--overwrite]"
                )
            }
            if arguments.count == 4, arguments[3] != "--overwrite" {
                throw MergeFailure.usage("The only supported optional flag is --overwrite.")
            }

            let journeyURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
            let resultsURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let outputURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
            try validatePaths(
                journeyURL: journeyURL,
                resultsURL: resultsURL,
                outputURL: outputURL,
                overwrite: arguments.count == 4
            )

            let journey = try await loadClip(at: journeyURL)
            let results = try await loadClip(at: resultsURL)
            try validateSources(journey: journey, results: results)
            try await export(journey: journey, results: results, to: outputURL)
            let manifestURL = try await validateAndWriteManifest(
                journey: journey,
                results: results,
                outputURL: outputURL
            )

            print("Export complete: \(outputURL.path)")
            print("Duration: 80.000 seconds")
            print("Audio tracks: 0")
            print("Manifest: \(manifestURL.path)")
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        }
    }

    private static func validatePaths(
        journeyURL: URL,
        resultsURL: URL,
        outputURL: URL,
        overwrite: Bool
    ) throws {
        let fileManager = FileManager.default
        for (url, label) in [(journeyURL, "journey video"), (resultsURL, "results video")] {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw MergeFailure.invalidInput("The \(label) does not exist: \(url.path)")
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw MergeFailure.invalidInput("The \(label) is empty: \(url.path)")
            }
        }

        guard outputURL.pathExtension.lowercased() == "mp4" else {
            throw MergeFailure.invalidInput("The output filename must end in .mp4.")
        }
        guard outputURL != journeyURL, outputURL != resultsURL else {
            throw MergeFailure.invalidInput("The output cannot overwrite either source video.")
        }

        let outputDirectory = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MergeFailure.invalidInput("The output directory does not exist: \(outputDirectory.path)")
        }

        let manifestURL = manifestURL(for: outputURL)
        for url in [outputURL, manifestURL] where fileManager.fileExists(atPath: url.path) {
            guard overwrite else {
                throw MergeFailure.invalidInput("Output already exists. Pass --overwrite to replace it: \(url.path)")
            }
            try fileManager.removeItem(at: url)
        }
    }

    private static func loadClip(at url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MergeFailure.media("Video track missing: \(url.path)")
        }
        let timeRange = try await track.load(.timeRange)
        let preferredTransform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard timeRange.start.isNumeric,
              timeRange.duration.isNumeric,
              timeRange.duration > .zero,
              abs(displayRect.height) > abs(displayRect.width) else {
            throw MergeFailure.media("The source must be a valid portrait video: \(url.path)")
        }
        return Clip(
            url: url,
            asset: asset,
            track: track,
            timeRange: timeRange,
            preferredTransform: preferredTransform,
            naturalSize: naturalSize,
            displayRect: displayRect
        )
    }

    private static func validateSources(journey: Clip, results: Clip) throws {
        let journeyDuration = CMTimeGetSeconds(journey.timeRange.duration)
        guard abs(journeyDuration - journeySeconds) <= durationTolerance else {
            throw MergeFailure.media(
                String(format: "Journey video is %.3f seconds; expected exactly %.3f.", journeyDuration, journeySeconds)
            )
        }
        guard CMTimeGetSeconds(results.timeRange.duration) >= resultsSeconds else {
            throw MergeFailure.media("The results source must be at least 20 seconds long.")
        }
        let journeySize = journey.displaySize
        let resultsSize = results.displaySize
        guard abs(journeySize.width - resultsSize.width) < 0.5,
              abs(journeySize.height - resultsSize.height) < 0.5 else {
            throw MergeFailure.media(
                "Source dimensions differ: \(Int(journeySize.width))x\(Int(journeySize.height)) and " +
                "\(Int(resultsSize.width))x\(Int(resultsSize.height))."
            )
        }
    }

    private static func export(journey: Clip, results: Clip, to outputURL: URL) async throws {
        let journeyDuration = CMTime(seconds: journeySeconds, preferredTimescale: timescale)
        let journeyContentDuration = CMTime(seconds: journeyContentSeconds, preferredTimescale: timescale)
        let cleanResultHoldDuration = CMTime(seconds: cleanResultHoldSeconds, preferredTimescale: timescale)
        let resultsMainStart = CMTime(seconds: resultsMainStartSeconds, preferredTimescale: timescale)
        let resultsEndTrim = CMTime(seconds: resultsEndTrimSeconds, preferredTimescale: timescale)
        let resultsDuration = CMTime(seconds: resultsSeconds, preferredTimescale: timescale)
        let totalDuration = CMTime(seconds: totalSeconds, preferredTimescale: timescale)
        let resultsMainRange = CMTimeRange(
            start: CMTimeAdd(results.timeRange.start, resultsMainStart),
            duration: CMTimeSubtract(
                CMTimeSubtract(results.timeRange.duration, resultsMainStart),
                resultsEndTrim
            )
        )
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MergeFailure.media("Could not create the composition video track.")
        }

        try videoTrack.insertTimeRange(
            CMTimeRange(start: journey.timeRange.start, duration: journeyContentDuration),
            of: journey.track,
            at: .zero
        )
        try videoTrack.insertTimeRange(
            CMTimeRange(
                start: results.timeRange.start,
                duration: cleanResultHoldDuration
            ),
            of: results.track,
            at: journeyContentDuration
        )
        try videoTrack.insertTimeRange(
            resultsMainRange,
            of: results.track,
            at: journeyDuration
        )
        videoTrack.scaleTimeRange(
            CMTimeRange(start: journeyDuration, duration: resultsMainRange.duration),
            toDuration: resultsDuration
        )

        let renderSize = CGSize(
            width: evenDimension(journey.displaySize.width),
            height: evenDimension(journey.displaySize.height)
        )
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layerConfiguration.setTransform(
            normalizedTransform(for: journey, renderSize: renderSize),
            at: .zero
        )
        layerConfiguration.setTransform(
            normalizedTransform(for: results, renderSize: renderSize),
            at: journeyContentDuration
        )
        let layer = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instruction = AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [layer],
                timeRange: CMTimeRange(start: .zero, duration: totalDuration)
            )
        )
        let videoComposition = AVVideoComposition(
            configuration: .init(
                frameDuration: CMTime(value: 1, timescale: framesPerSecond),
                instructions: [instruction],
                renderSize: renderSize,
                sourceTrackIDForFrameTiming: kCMPersistentTrackID_Invalid
            )
        )

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw MergeFailure.export("Could not create the video export session.")
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw MergeFailure.export("The merged composition cannot be exported as MP4.")
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw MergeFailure.export("AVFoundation export failed: \(error.localizedDescription)")
        }
    }

    private static func normalizedTransform(
        for clip: Clip,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let normalization = CGAffineTransform(
            translationX: -clip.displayRect.minX,
            y: -clip.displayRect.minY
        )
        var transform = clip.preferredTransform.concatenating(normalization)
        transform = transform.concatenating(
            CGAffineTransform(
                scaleX: renderSize.width / clip.displaySize.width,
                y: renderSize.height / clip.displaySize.height
            )
        )
        return transform
    }

    private static func validateAndWriteManifest(
        journey: Clip,
        results: Clip,
        outputURL: URL
    ) async throws -> URL {
        let outputAsset = AVURLAsset(url: outputURL)
        let duration = try await outputAsset.load(.duration)
        let videoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        guard videoTracks.count == 1, let videoTrack = videoTracks.first else {
            throw MergeFailure.export("The output must contain exactly one video track.")
        }
        guard audioTracks.isEmpty else {
            throw MergeFailure.export("The output must contain no audio tracks.")
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard abs(durationSeconds - totalSeconds) <= durationTolerance else {
            throw MergeFailure.export(
                String(format: "Output is %.3f seconds; expected exactly %.3f.", durationSeconds, totalSeconds)
            )
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let width = Int(abs(displayRect.width).rounded())
        let height = Int(abs(displayRect.height).rounded())
        guard height > width, abs(nominalFrameRate - Float(framesPerSecond)) < 0.01 else {
            throw MergeFailure.export("The output must be portrait at a true 30 fps.")
        }

        let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let journeyAttributes = try FileManager.default.attributesOfItem(atPath: journey.url.path)
        let resultsAttributes = try FileManager.default.attributesOfItem(atPath: results.url.path)
        let manifest = ExportManifest(
            schemaVersion: 1,
            generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
            composition: "60-second product journey with a clean final result hold, followed by the complete results walkthrough fitted to 20 seconds; all audio removed",
            sources: [
                FileRecord(
                    filename: journey.url.lastPathComponent,
                    bytes: (journeyAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                    sha256: try sha256(of: journey.url),
                    sourceDurationSeconds: CMTimeGetSeconds(journey.timeRange.duration),
                    timelineDurationSeconds: journeyContentSeconds
                ),
                FileRecord(
                    filename: results.url.lastPathComponent,
                    bytes: (resultsAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                    sha256: try sha256(of: results.url),
                    sourceDurationSeconds: CMTimeGetSeconds(results.timeRange.duration),
                    timelineDurationSeconds: cleanResultHoldSeconds + resultsSeconds
                )
            ],
            output: OutputRecord(
                filename: outputURL.lastPathComponent,
                bytes: (outputAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                sha256: try sha256(of: outputURL),
                durationSeconds: durationSeconds,
                width: width,
                height: height,
                framesPerSecond: nominalFrameRate,
                videoTrackCount: videoTracks.count,
                audioTrackCount: audioTracks.count,
                muted: true
            )
        )

        let manifestURL = manifestURL(for: outputURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private static func manifestURL(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension().appendingPathExtension("manifest.json")
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded())
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded - 1)
    }
}
