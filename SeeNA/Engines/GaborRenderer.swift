import SwiftUI
import UIKit

enum GaborRenderer {
    static func image(
        orientation: GaborOrientation,
        contrast: Double,
        pixelSize: Int = 112
    ) -> UIImage {
        let size = max(48, pixelSize)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let centre = Double(size - 1) / 2
        let sigma = Double(size) * 0.22
        let frequency = 4.2 / Double(size)
        let angle = (orientation == .left ? -45.0 : 45.0) * .pi / 180
        let boundedContrast = min(1, max(0, contrast))

        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - centre
                let dy = Double(y) - centre
                let rotatedX = dx * cos(angle) + dy * sin(angle)
                let envelope = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                let grating = cos(2 * .pi * frequency * rotatedX)
                let luminance = 0.5 + 0.5 * boundedContrast * envelope * grating
                let value = UInt8(min(255, max(0, (luminance * 255).rounded())))
                let offset = (y * size + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        let provider = CGDataProvider(data: data)!
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        let cgImage = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colourSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage, scale: 2, orientation: .up)
    }
}

struct GaborRowView: View {
    let orientations: [GaborOrientation]
    let contrast: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(orientations.enumerated()), id: \.offset) { _, orientation in
                Image(uiImage: GaborRenderer.image(orientation: orientation, contrast: contrast))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 43, height: 43)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven striped circles. Say whether each tilts left or right.")
    }
}
