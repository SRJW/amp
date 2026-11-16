import SwiftUI
import UIKit

/// One coordinate system for the source and its extended upper edge. The texture
/// matches at the join; blur only increases as it travels away from the real image.
struct PlayerArtworkTopExtension: View {
    let image: UIImage
    let size: CGSize
    let frame: CGRect

    private struct BlurLevel {
        let radiusW: CGFloat
        let endW: CGFloat
    }
    private static let sharpEdgeW: CGFloat = 0.01
    private static let levels = [BlurLevel(radiusW: 0.018, endW: 0.03),
                                 BlurLevel(radiusW: PlayerArtworkComposition.extensionBlurFraction, endW: 0.08)]

    var body: some View {
        plate(padding: 0)
            .overlay {
                if frame.minY > 0 {
                    ZStack {
                        ForEach(Self.levels.indices, id: \.self) { index in
                            let radius = size.width * Self.levels[index].radiusW
                            plate(padding: radius * 3)
                                .blur(radius: radius)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .mask(blurMask(index: index))
                        }
                    }
                }
            }
    }

    private func plate(padding: CGFloat) -> some View {
        let canvasSize = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
        let origin = frame.offsetBy(dx: padding, dy: padding)
        return Canvas { context, _ in
            guard frame.width > 0, frame.height > 0 else { return }
            let source = context.resolve(Image(uiImage: image).interpolation(.high))
            context.clip(to: Path(CGRect(origin: .zero, size: canvasSize)))
            let firstColumn = Int(floor(-origin.minX / frame.width))
            let lastColumn = Int(ceil((canvasSize.width - origin.minX) / frame.width)) - 1
            let firstRow = Int(floor(-origin.minY / frame.height))
            let lastRow = Int(ceil((canvasSize.height - origin.minY) / frame.height)) - 1
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let tile = origin.offsetBy(dx: frame.width * CGFloat(column), dy: frame.height * CGFloat(row))
                    var reflected = context
                    if !column.isMultiple(of: 2) {
                        reflected.translateBy(x: tile.minX + tile.maxX, y: 0)
                        reflected.scaleBy(x: -1, y: 1)
                    }
                    if !row.isMultiple(of: 2) {
                        reflected.translateBy(x: 0, y: tile.minY + tile.maxY)
                        reflected.scaleBy(x: 1, y: -1)
                    }
                    reflected.draw(source, in: tile)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func blurMask(index: Int) -> LinearGradient {
        let start = size.width * (index == 0 ? Self.sharpEdgeW : Self.levels[index - 1].endW)
        let nominalEnd = size.width * Self.levels[index].endW
        let end = index == Self.levels.count - 1 ? max(nominalEnd, frame.minY) : nominalEnd
        let range: CGFloat = end - start
        var points: [CGFloat] = [0, size.height]
        for step in 0...8 {
            let fraction: CGFloat = CGFloat(step) / 8
            let distance: CGFloat = start + range * fraction
            let y: CGFloat = (frame.minY - distance).clamped(0, size.height)
            points.append(y)
        }
        points.sort()
        var stops: [Gradient.Stop] = []
        for y in points {
            let distance: CGFloat = frame.minY - y - start
            let fraction: CGFloat = (distance / max(range, 1)).clamped(0, 1)
            let opacity: Double = Self.smoothstep(Double(fraction))
            let color: Color = Color.white.opacity(opacity)
            let location: CGFloat = y / max(size.height, 1)
            stops.append(Gradient.Stop(color: color, location: location))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}
