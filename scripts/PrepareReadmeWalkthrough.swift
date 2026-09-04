import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum WalkthroughFailure: LocalizedError {
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

private struct Options {
    let sourceURL: URL
    let outputURL: URL
    let startSeconds: Double
    let endSeconds: Double?
    let overwrite: Bool
}

private struct SourceRecord: Codable {
    let filename: String
    let bytes: Int64
    let sha256: String
    let sourceDurationSeconds: Double
    let trimStartSeconds: Double
    let trimEndSeconds: Double
    let selectedDurationSeconds: Double
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
}

private struct PreviewRecord: Codable {
    let filename: String
    let bytes: Int64
    let sha256: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let framesPerSecond: Double
    let frameCount: Int
    let loopCount: Int
}

private struct ExportManifest: Codable {
    let schemaVersion: Int
    let generatedAtUTC: String
    let composition: String
    let source: SourceRecord
    let output: OutputRecord
    let preview: PreviewRecord
}

private struct Clip {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let timeRange: CMTimeRange
    let preferredTransform: CGAffineTransform
    let displayRect: CGRect

    var displaySize: CGSize {
        CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
    }
}

@main
private enum PrepareReadmeWalkthrough {
    private static let outputSeconds = 60.0
    private static let framesPerSecond: CMTimeScale = 30
    private static let previewFramesPerSecond = 4.0
    private static let previewWidth = 360
    private static let maximumPreviewBytes: Int64 = 20_000_000
    private static let timescale: CMTimeScale = 600
    private static let durationTolerance = 1.0 / 600.0

    static func main() async {
        var temporaryURLs: [URL] = []

        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            try validatePaths(options)

            let clip = try await loadClip(at: options.sourceURL)
            let selectedRange = try selectedRange(for: clip, options: options)
            let temporaryOutputURL = temporaryURL(
                beside: options.outputURL,
                extension: "mp4"
            )
            let finalPreviewURL = previewURL(for: options.outputURL)
            let temporaryPreviewURL = temporaryURL(
                beside: finalPreviewURL,
                extension: "gif"
            )
            let finalManifestURL = manifestURL(for: options.outputURL)
            let temporaryManifestURL = temporaryURL(
                beside: finalManifestURL,
                extension: "json"
            )
            temporaryURLs = [temporaryOutputURL, temporaryPreviewURL, temporaryManifestURL]

            try await export(
                clip: clip,
                selectedRange: selectedRange,
                to: temporaryOutputURL
            )
            try await generatePreviewGIF(
                from: temporaryOutputURL,
                to: temporaryPreviewURL
            )
            let manifest = try await validateAndBuildManifest(
                options: options,
                clip: clip,
                selectedRange: selectedRange,
                outputURL: temporaryOutputURL,
                previewURL: temporaryPreviewURL
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: temporaryManifestURL, options: .atomic)

            try install(
                temporaryURL: temporaryOutputURL,
                at: options.outputURL,
                overwrite: options.overwrite
            )
            try install(
                temporaryURL: temporaryPreviewURL,
                at: finalPreviewURL,
                overwrite: options.overwrite
            )
            try install(
                temporaryURL: temporaryManifestURL,
                at: finalManifestURL,
                overwrite: options.overwrite
            )
            temporaryURLs.removeAll()

            print("Export complete: \(options.outputURL.path)")
            print("Duration: 60.000 seconds")
            print("Video tracks: 1")
            print("Audio tracks: 0")
            print("GIF preview: \(finalPreviewURL.path)")
            print("Manifest: \(finalManifestURL.path)")
        } catch {
            for url in temporaryURLs {
                try? FileManager.default.removeItem(at: url)
            }
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        guard arguments.count >= 2 else {
            throw WalkthroughFailure.usage(usage)
        }

        let sourceURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        var startSeconds = 0.0
        var endSeconds: Double?
        var overwrite = false
        var index = 2

        while index < arguments.count {
            switch arguments[index] {
            case "--start-seconds":
                guard index + 1 < arguments.count,
                      let value = Double(arguments[index + 1]),
                      value.isFinite,
                      value >= 0 else {
                    throw WalkthroughFailure.usage("--start-seconds requires a finite, non-negative number.\n\(usage)")
                }
                startSeconds = value
                index += 2
            case "--end-seconds":
                guard index + 1 < arguments.count,
                      let value = Double(arguments[index + 1]),
                      value.isFinite,
                      value > 0 else {
                    throw WalkthroughFailure.usage("--end-seconds requires a finite, positive number.\n\(usage)")
                }
                endSeconds = value
                index += 2
            case "--overwrite":
                overwrite = true
                index += 1
            default:
                throw WalkthroughFailure.usage("Unknown option: \(arguments[index])\n\(usage)")
            }
        }

        if let endSeconds, endSeconds <= startSeconds {
            throw WalkthroughFailure.usage("--end-seconds must be greater than --start-seconds.")
        }

        return Options(
            sourceURL: sourceURL,
            outputURL: outputURL,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            overwrite: overwrite
        )
    }

    private static var usage: String {
        "Usage: PrepareReadmeWalkthrough <source.mp4> <output.mp4> " +
        "[--start-seconds N] [--end-seconds N] [--overwrite]"
    }

    private static func validatePaths(_ options: Options) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: options.sourceURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw WalkthroughFailure.invalidInput(
                "Source video does not exist: \(options.sourceURL.path)"
            )
        }
        let sourceAttributes = try fileManager.attributesOfItem(atPath: options.sourceURL.path)
        guard (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw WalkthroughFailure.invalidInput("Source video is empty: \(options.sourceURL.path)")
        }
        guard options.outputURL.pathExtension.lowercased() == "mp4" else {
            throw WalkthroughFailure.invalidInput("The output filename must end in .mp4.")
        }
        guard options.outputURL != options.sourceURL else {
            throw WalkthroughFailure.invalidInput("The source and output paths must be different.")
        }

        let outputDirectory = options.outputURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WalkthroughFailure.invalidInput(
                "Output directory does not exist: \(outputDirectory.path)"
            )
        }

        for url in [
            options.outputURL,
            previewURL(for: options.outputURL),
            manifestURL(for: options.outputURL)
        ]
        where fileManager.fileExists(atPath: url.path) && !options.overwrite {
            throw WalkthroughFailure.invalidInput(
                "Output already exists. Pass --overwrite to replace it: \(url.path)"
            )
        }
    }

    private static func loadClip(at url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard videoTracks.count == 1, let track = videoTracks.first else {
            throw WalkthroughFailure.media(
                "Source must contain exactly one video track; found \(videoTracks.count)."
            )
        }

        let timeRange = try await track.load(.timeRange)
        let preferredTransform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard timeRange.start.isNumeric,
              timeRange.duration.isNumeric,
              timeRange.duration > .zero,
              abs(displayRect.height) > abs(displayRect.width) else {
            throw WalkthroughFailure.media("Source must be a valid portrait video.")
        }

        return Clip(
            asset: asset,
            track: track,
            timeRange: timeRange,
            preferredTransform: preferredTransform,
            displayRect: displayRect
        )
    }

    private static func selectedRange(
        for clip: Clip,
        options: Options
    ) throws -> CMTimeRange {
        let sourceDurationSeconds = CMTimeGetSeconds(clip.timeRange.duration)
        let endSeconds = min(options.endSeconds ?? sourceDurationSeconds, sourceDurationSeconds)
        guard options.startSeconds < sourceDurationSeconds else {
            throw WalkthroughFailure.media(
                String(
                    format: "Trim start %.3f is outside the %.3f-second source.",
                    options.startSeconds,
                    sourceDurationSeconds
                )
            )
        }
        guard endSeconds > options.startSeconds else {
            throw WalkthroughFailure.media("The selected source range is empty.")
        }

        let start = CMTimeAdd(
            clip.timeRange.start,
            CMTime(seconds: options.startSeconds, preferredTimescale: timescale)
        )
        let duration = CMTime(
            seconds: endSeconds - options.startSeconds,
            preferredTimescale: timescale
        )
        guard duration >= CMTime(seconds: outputSeconds, preferredTimescale: timescale) else {
            throw WalkthroughFailure.media(
                String(
                    format: "Selected source is %.3f seconds; at least %.3f seconds is required.",
                    CMTimeGetSeconds(duration),
                    outputSeconds
                )
            )
        }
        return CMTimeRange(start: start, duration: duration)
    }

    private static func export(
        clip: Clip,
        selectedRange: CMTimeRange,
        to outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw WalkthroughFailure.media("Could not create the composition video track.")
        }

        try videoTrack.insertTimeRange(selectedRange, of: clip.track, at: .zero)
        let outputDuration = CMTime(seconds: outputSeconds, preferredTimescale: timescale)
        videoTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: selectedRange.duration),
            toDuration: outputDuration
        )

        let renderSize = CGSize(
            width: evenDimension(clip.displaySize.width),
            height: evenDimension(clip.displaySize.height)
        )
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(
            assetTrack: videoTrack
        )
        layerConfiguration.setTransform(
            normalizedTransform(for: clip, renderSize: renderSize),
            at: .zero
        )
        let layer = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instruction = AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [layer],
                timeRange: CMTimeRange(start: .zero, duration: outputDuration)
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
            throw WalkthroughFailure.export("Could not create the video export session.")
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw WalkthroughFailure.export("The composition cannot be exported as MP4.")
        }

        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: .zero, duration: outputDuration)

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw WalkthroughFailure.export(
                "AVFoundation export failed: \(error.localizedDescription)"
            )
        }
    }

    private static func validateAndBuildManifest(
        options: Options,
        clip: Clip,
        selectedRange: CMTimeRange,
        outputURL: URL,
        previewURL: URL
    ) async throws -> ExportManifest {
        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration = try await outputAsset.load(.duration)
        let videoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        guard videoTracks.count == 1, let videoTrack = videoTracks.first else {
            throw WalkthroughFailure.export(
                "Output must contain exactly one video track; found \(videoTracks.count)."
            )
        }
        guard audioTracks.isEmpty else {
            throw WalkthroughFailure.export(
                "Output must contain no audio tracks; found \(audioTracks.count)."
            )
        }

        let durationSeconds = CMTimeGetSeconds(outputDuration)
        guard abs(durationSeconds - outputSeconds) <= durationTolerance else {
            throw WalkthroughFailure.export(
                String(
                    format: "Output is %.6f seconds; expected exactly %.3f.",
                    durationSeconds,
                    outputSeconds
                )
            )
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let width = Int(abs(displayRect.width).rounded())
        let height = Int(abs(displayRect.height).rounded())
        guard height > width else {
            throw WalkthroughFailure.export("Output must remain portrait.")
        }
        guard abs(nominalFrameRate - Float(framesPerSecond)) < 0.01 else {
            throw WalkthroughFailure.export(
                String(
                    format: "Output is %.3f fps; expected %.3f fps.",
                    nominalFrameRate,
                    Float(framesPerSecond)
                )
            )
        }

        let fileManager = FileManager.default
        let sourceAttributes = try fileManager.attributesOfItem(atPath: options.sourceURL.path)
        let outputAttributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        let preview = try validatePreview(at: previewURL)
        let sourceDurationSeconds = CMTimeGetSeconds(clip.timeRange.duration)
        let trimEndSeconds = options.startSeconds + CMTimeGetSeconds(selectedRange.duration)

        return ExportManifest(
            schemaVersion: 2,
            generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
            composition: "Complete SeeNA product walkthrough fitted into an exact 60-second, video-only README asset",
            source: SourceRecord(
                filename: options.sourceURL.lastPathComponent,
                bytes: (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                sha256: try sha256(of: options.sourceURL),
                sourceDurationSeconds: sourceDurationSeconds,
                trimStartSeconds: options.startSeconds,
                trimEndSeconds: trimEndSeconds,
                selectedDurationSeconds: CMTimeGetSeconds(selectedRange.duration),
                timelineDurationSeconds: outputSeconds
            ),
            output: OutputRecord(
                filename: options.outputURL.lastPathComponent,
                bytes: (outputAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                sha256: try sha256(of: outputURL),
                durationSeconds: durationSeconds,
                width: width,
                height: height,
                framesPerSecond: nominalFrameRate,
                videoTrackCount: videoTracks.count,
                audioTrackCount: audioTracks.count
            ),
            preview: preview
        )
    }

    private static func generatePreviewGIF(
        from videoURL: URL,
        to outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: previewWidth, height: previewWidth * 3)
        let tolerance = CMTime(
            seconds: 1.0 / (previewFramesPerSecond * 2.0),
            preferredTimescale: timescale
        )
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let frameCount = Int(outputSeconds * previewFramesPerSecond)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw WalkthroughFailure.export("Could not create the GIF preview destination.")
        }
        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary
        )

        let delay = 1.0 / previewFramesPerSecond
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
        ] as CFDictionary

        for index in 0..<frameCount {
            let second = Double(index) / previewFramesPerSecond
            let time = CMTime(seconds: second, preferredTimescale: timescale)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw WalkthroughFailure.export("Could not finalize the GIF preview.")
        }
    }

    private static func validatePreview(at url: URL) throws -> PreviewRecord {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw WalkthroughFailure.export("Could not read the exported GIF preview.")
        }
        let expectedFrameCount = Int(outputSeconds * previewFramesPerSecond)
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == expectedFrameCount else {
            throw WalkthroughFailure.export(
                "GIF contains \(frameCount) frames; expected \(expectedFrameCount)."
            )
        }

        guard let firstProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
              let width = firstProperties[kCGImagePropertyPixelWidth] as? Int,
              let height = firstProperties[kCGImagePropertyPixelHeight] as? Int,
              height > width,
              width <= previewWidth else {
            throw WalkthroughFailure.export("GIF preview dimensions are invalid.")
        }

        var duration = 0.0
        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
                  let gif = properties[kCGImagePropertyGIFDictionary]
                    as? [CFString: Any] else {
                throw WalkthroughFailure.export(
                    "GIF frame \(index) does not contain timing metadata."
                )
            }
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                ?? 0
            duration += delay
        }
        guard abs(duration - outputSeconds) <= 0.01 else {
            throw WalkthroughFailure.export(
                String(
                    format: "GIF duration is %.3f seconds; expected %.3f.",
                    duration,
                    outputSeconds
                )
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0, bytes <= maximumPreviewBytes else {
            throw WalkthroughFailure.export(
                "GIF preview is \(bytes) bytes; expected 1...\(maximumPreviewBytes)."
            )
        }

        return PreviewRecord(
            filename: "SeeNA-Product-Walkthrough.gif",
            bytes: bytes,
            sha256: try sha256(of: url),
            durationSeconds: duration,
            width: width,
            height: height,
            framesPerSecond: previewFramesPerSecond,
            frameCount: frameCount,
            loopCount: 0
        )
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

    private static func install(
        temporaryURL: URL,
        at destinationURL: URL,
        overwrite: Bool
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard overwrite else {
                throw WalkthroughFailure.invalidInput(
                    "Output already exists: \(destinationURL.path)"
                )
            }
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private static func temporaryURL(beside destinationURL: URL, extension: String) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".seena-\(UUID().uuidString)")
            .appendingPathExtension(`extension`)
    }

    private static func manifestURL(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension().appendingPathExtension("manifest.json")
    }

    private static func previewURL(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension().appendingPathExtension("gif")
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
