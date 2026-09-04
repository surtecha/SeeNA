import SwiftUI
import UIKit

enum GaborRenderer {
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func image(
        orientation: GaborOrientation,
        contrast: Double,
        geometry: GaborPresentationGeometry
    ) -> UIImage {
        guard geometry.isValidCurrentEvidence, contrast.isFinite else { return UIImage() }
        let size = geometry.rasterPixelDiameter
        let imageScale = geometry.displayScale
        let cacheKey = "\(orientation.rawValue)-\(String(format: "%.4f", contrast))-\(size)-\(String(format: "%.3f", imageScale))" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let centre = Double(size - 1) / 2
        let sigma = Double(size) * GaborPresentationGeometry.currentGaussianSigmaFraction
        let frequency = GaborPresentationGeometry.currentCarrierCyclesPerPatch / Double(size)
        let orientationDegrees = orientation == .left
            ? -GaborPresentationGeometry.currentOrientationMagnitudeDegrees
            : GaborPresentationGeometry.currentOrientationMagnitudeDegrees
        let angle = orientationDegrees * .pi / 180
        let boundedContrast = min(1, max(0, contrast))
        let gaussian = (0..<size).map { coordinate in
            let delta = Double(coordinate) - centre
            return exp(-(delta * delta) / (2 * sigma * sigma))
        }
        let xPhases = (0..<size).map { coordinate in
            2 * .pi * frequency * (Double(coordinate) - centre) * cos(angle)
        }
        let yPhases = (0..<size).map { coordinate in
            2 * .pi * frequency * (Double(coordinate) - centre) * sin(angle)
        }
        let xCosines = xPhases.map { cos($0) }
        let xSines = xPhases.map { sin($0) }
        let yCosines = yPhases.map { cos($0) }
        let ySines = yPhases.map { sin($0) }
        let phaseCosine = cos(GaborPresentationGeometry.currentCarrierPhaseRadians)
        let phaseSine = sin(GaborPresentationGeometry.currentCarrierPhaseRadians)

        for y in 0..<size {
            for x in 0..<size {
                let envelope = gaussian[x] * gaussian[y]
                let zeroPhaseGrating = xCosines[x] * yCosines[y] - xSines[x] * ySines[y]
                let grating = zeroPhaseGrating * phaseCosine
                    - (xSines[x] * yCosines[y] + xCosines[x] * ySines[y]) * phaseSine
                let luminance = GaborPresentationGeometry.currentMeanLuminance
                    + GaborPresentationGeometry.currentContrastAmplitudeScale
                        * boundedContrast * envelope * grating
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
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let image = UIImage(cgImage: cgImage, scale: CGFloat(imageScale), orientation: .up)
        imageCache.setObject(image, forKey: cacheKey, cost: pixels.count)
        return image
    }
}

/// A single phone-scale Gabor patch.
struct GaborSingleTargetView: View {
    let orientation: GaborOrientation
    let contrast: Double
    let geometry: GaborPresentationGeometry

    var body: some View {
        Image(uiImage: GaborRenderer.image(
            orientation: orientation,
            contrast: contrast,
            geometry: geometry
        ))
        .resizable()
        // The source raster is generated at the exact displayed pixel diameter,
        // avoiding an extra interpolation pass that can alter the stripe edges.
        .interpolation(.none)
        .frame(
            width: CGFloat(geometry.pointDiameter),
            height: CGFloat(geometry.pointDiameter)
        )
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Striped circle")
    }
}
