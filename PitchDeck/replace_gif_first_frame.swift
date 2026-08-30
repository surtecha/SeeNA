import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: replace_gif_first_frame input.gif poster.jpg output.gif\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let posterURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3]) as CFURL

guard
    let source = CGImageSourceCreateWithURL(inputURL, nil),
    let posterSource = CGImageSourceCreateWithURL(posterURL, nil)
else {
    fputs("Unable to read source media.\n", stderr)
    exit(3)
}

let frameCount = CGImageSourceGetCount(source)
guard frameCount > 0 else {
    fputs("The input GIF has no frames.\n", stderr)
    exit(4)
}

let posterOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: 1400,
    kCGImageSourceCreateThumbnailWithTransform: true,
]

guard
    let poster = CGImageSourceCreateThumbnailAtIndex(
        posterSource,
        0,
        posterOptions as CFDictionary
    ),
    let destination = CGImageDestinationCreateWithURL(
        outputURL,
        UTType.gif.identifier as CFString,
        frameCount,
        nil
    )
else {
    fputs("Unable to prepare the output GIF.\n", stderr)
    exit(5)
}

if let globalProperties = CGImageSourceCopyProperties(source, nil) {
    CGImageDestinationSetProperties(destination, globalProperties)
}

for index in 0..<frameCount {
    guard let frame = index == 0 ? poster : CGImageSourceCreateImageAtIndex(source, index, nil) else {
        fputs("Unable to read a GIF frame.\n", stderr)
        exit(6)
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
    CGImageDestinationAddImage(destination, frame, properties)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write the output GIF.\n", stderr)
    exit(7)
}

print("Wrote \(frameCount) frames to \(CommandLine.arguments[3])")

