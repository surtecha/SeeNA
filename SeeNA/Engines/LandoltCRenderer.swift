import SwiftUI
import UIKit

enum LandoltCRenderer {
    static func image(geometry: OptotypeGeometry, direction: OptotypeDirection) -> UIImage {
        let side = geometry.pixelHeight
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setShouldAntialias(false)
            context.setAllowsAntialiasing(false)
            context.interpolationQuality = .none
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            context.saveGState()
            context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
            context.rotate(by: CGFloat(direction.rotationDegrees * .pi / 180))
            context.translateBy(x: -CGFloat(side) / 2, y: -CGFloat(side) / 2)

            context.setFillColor(UIColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))

            let stroke = geometry.strokePixels
            let inner = geometry.innerDiameterPixels
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(
                in: CGRect(x: stroke, y: stroke, width: inner, height: inner)
            )

            let gapY = (side - geometry.gapPixels) / 2
            context.fill(
                CGRect(
                    x: side / 2,
                    y: gapY,
                    width: side - side / 2,
                    height: geometry.gapPixels
                )
            )
            context.restoreGState()
        }
    }
}

struct LandoltCView: View {
    let geometry: OptotypeGeometry
    let direction: OptotypeDirection

    var body: some View {
        Image(uiImage: LandoltCRenderer.image(geometry: geometry, direction: direction))
            .interpolation(.none)
            .resizable()
            .frame(width: geometry.pointHeight, height: geometry.pointHeight)
            .accessibilityLabel("Opening (direction.rawValue)")
    }
}

/// The POC presentation surface: one large, stable target centred on the phone.
/// Response sequencing remains outside the renderer so the target changes only
/// after the response controller accepts the user's answer.
struct LandoltSingleTargetView: View {
    let geometry: OptotypeGeometry
    let direction: OptotypeDirection

    var body: some View {
        LandoltCView(geometry: geometry, direction: direction)
            .frame(
                maxWidth: .infinity,
                minHeight: max(220, geometry.pointHeight * 1.35),
                alignment: .center
            )
            .background(Color.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Landolt C target. Say the direction of the opening.")
    }
}

struct LandoltRowView: View {
    let geometry: OptotypeGeometry
    let directions: [OptotypeDirection]

    var body: some View {
        HStack(spacing: max(geometry.pointHeight * 0.75, 5)) {
            ForEach(Array(directions.enumerated()), id: \.offset) { _, direction in
                LandoltCView(geometry: geometry, direction: direction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: max(80, geometry.pointHeight * 1.5))
        .background(Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven Landolt C targets. Read the opening directions from left to right.")
    }
}
