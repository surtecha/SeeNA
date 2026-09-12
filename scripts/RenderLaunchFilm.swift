import AppKit
import AVFoundation
import CryptoKit
import CoreText
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// Reproducible editorial composition of actual simulator captures.
// Usage: RenderLaunchFilm timeline.json output.mp4
private struct Shot: Codable {
    let source: String
    let sourceStart: Double
    let sourceDuration: Double
    let duration: Double
    let chapter: String
    let title: String
    let subtitle: String
}

@main
private enum RenderLaunchFilm {
    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: RenderLaunchFilm timeline.json output.mp4") }
        let timelineURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output exists; choose a new path") }
        let shots = try JSONDecoder().decode([Shot].self, from: Data(contentsOf: timelineURL))
        guard abs(shots.reduce(0) { $0 + $1.duration } - 90) < 0.0001 else { fatalError("Film must be exactly 90 seconds") }
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        var instructions: [AVMutableVideoCompositionInstruction] = []
        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        parent.backgroundColor = NSColor.black.cgColor
        let video = CALayer()
        video.frame = parent.bounds
        parent.addSublayer(video)
        let white = NSColor.white
        let soft = NSColor(white: 0.68, alpha: 1)

        func label(_ text: String, frame: CGRect, size: CGFloat, weight: NSFont.Weight,
                   colour: NSColor = .white) -> CALayer {
            let layer = CALayer()
            layer.frame = frame
            layer.contentsScale = 2
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: colour, .paragraphStyle: paragraph
            ])
            // CATextLayer does not reliably rasterise attributed strings in
            // a headless AVFoundation export. Render through Core Text first.
            let context = CGContext(data: nil, width: Int(frame.width * 2), height: Int(frame.height * 2),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: 2, y: 2)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: CGRect(origin: .zero, size: frame.size), transform: nil)
            let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            CTFrameDraw(textFrame, context)
            layer.contents = context.makeImage()
            return layer
        }
        parent.addSublayer(label("SeeNA", frame: CGRect(x: 132, y: 931, width: 600, height: 65), size: 38, weight: .bold))
        parent.addSublayer(label("SEE NOW AND ALWAYS", frame: CGRect(x: 132, y: 115, width: 900, height: 38),
                                size: 22, weight: .medium, colour: soft))
        let rule = CALayer()
        rule.frame = CGRect(x: 132, y: 88, width: 900, height: 2)
        rule.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        parent.addSublayer(rule)
        let progress = CALayer()
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.position = CGPoint(x: 132, y: 89)
        progress.bounds = CGRect(x: 0, y: 0, width: 900, height: 2)
        progress.backgroundColor = white.cgColor
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0
        grow.toValue = 1
        grow.beginTime = AVCoreAnimationBeginTimeAtZero
        grow.duration = 90
        grow.fillMode = .both
        grow.isRemovedOnCompletion = false
        progress.add(grow, forKey: "timeline")
        parent.addSublayer(progress)
        let screenRect = CGRect(x: 1370 - 940 * 1320 / 2868 / 2, y: 70, width: 940 * 1320 / 2868, height: 940)
        let mask = CAShapeLayer()
        mask.path = CGPath(roundedRect: screenRect, cornerWidth: 44, cornerHeight: 44, transform: nil)
        video.mask = mask
        let rim = CAShapeLayer()
        rim.path = mask.path
        rim.fillColor = NSColor.clear.cgColor
        rim.strokeColor = NSColor(white: 0.5, alpha: 1).cgColor
        rim.lineWidth = 2
        parent.addSublayer(rim)

        var cursor = 0.0
        for shot in shots {
            guard shot.sourceStart.isFinite, shot.sourceStart >= 0, shot.sourceDuration > 0,
                  shot.duration > 0 else { fatalError("Invalid clip range") }
            let asset = AVURLAsset(url: URL(fileURLWithPath: shot.source))
            let assetDuration = try await asset.load(.duration).seconds
            guard shot.sourceStart + shot.sourceDuration <= assetDuration + 0.03,
                  let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                fatalError("Clip range exceeds source: \(shot.source)")
            }
            try track.insertTimeRange(CMTimeRange(start: time(shot.sourceStart), duration: time(shot.sourceDuration)),
                                      of: sourceTrack, at: time(cursor))
            track.scaleTimeRange(CMTimeRange(start: time(cursor), duration: time(shot.sourceDuration)), toDuration: time(shot.duration))
            let size = try await sourceTrack.load(.naturalSize)
            let original = try await sourceTrack.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(original)
            let scale = min(500 / abs(rect.width), 940 / abs(rect.height))
            let x = 1370 - abs(rect.width) * scale / 2
            let y = (1080 - abs(rect.height) * scale) / 2
            let transform = original
                .concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: x, y: y))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(transform, at: time(cursor))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: time(cursor), duration: time(shot.duration))
            instruction.backgroundColor = NSColor.black.cgColor
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            let card = CALayer()
            card.frame = parent.bounds
            card.opacity = 0
            card.addSublayer(label(shot.chapter.uppercased(), frame: CGRect(x: 132, y: 769, width: 900, height: 40), size: 24, weight: .medium, colour: soft))
            card.addSublayer(label(shot.title, frame: CGRect(x: 126, y: 400, width: 950, height: 345), size: 88, weight: .bold))
            card.addSublayer(label(shot.subtitle, frame: CGRect(x: 132, y: 211, width: 865, height: 180), size: 34, weight: .regular, colour: soft))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.065, 0.95, 1]
            fade.beginTime = AVCoreAnimationBeginTimeAtZero + cursor
            fade.duration = shot.duration
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
            card.add(fade, forKey: "chapter")
            parent.addSublayer(card)
            cursor += shot.duration
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = parent.bounds.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080)!
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: time(90))
        try await exporter.export(to: output, as: .mp4)

        let final = AVURLAsset(url: output)
        let finalDuration = try await final.load(.duration).seconds
        let audioCount = try await final.loadTracks(withMediaType: .audio).count
        guard abs(finalDuration - 90) < 0.034, audioCount == 0 else { fatalError("Invalid final duration or audio tracks") }
        let bytes = try Data(contentsOf: output)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = ["durationSeconds": finalDuration, "width": 1920, "height": 1080,
            "fps": 30, "audioTracks": audioCount, "sha256": hash, "bytes": bytes.count,
            "provenance": "Actual SeeNA simulator recordings; synthetic QA responses and edited timing, not clinical evidence."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingPathExtension().appendingPathExtension("manifest.json"))
        let generator = AVAssetImageGenerator(asset: final)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 768, height: 432)
        let gifURL = output.deletingLastPathComponent().appendingPathComponent("SeeNA-Launch-Preview.gif")
        let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 90, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for second in 0..<90 {
            let frame = try await generator.image(at: time(Double(second) + 0.2)).image
            CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.15]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("Could not finalise preview") }
        print("Verified: 90.000 s, 1920 × 1080, 30 fps, no audio track. SHA256 \(hash)")
    }
}
