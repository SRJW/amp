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
        plate
            .overlay {
                if frame.minY > 0 {
                    ZStack {
                        ForEach(Self.levels.indices, id: \.self) { index in
                            plate
                                .blur(radius: size.width * Self.levels[index].radiusW)
                                .mask(blurMask(index: index))
                        }
                    }
                }
            }
    }

    private var plate: some View {
        Canvas { context, _ in
            guard frame.width > 0, frame.height > 0 else { return }
            let source = context.resolve(Image(uiImage: image).interpolation(.high))
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            let count = Int(ceil(max(frame.minY, 0) / frame.height))
            for index in (0..<count).reversed() {
                let tile = frame.offsetBy(dx: 0, dy: -frame.height * CGFloat(index + 1))
                var reflected = context
                if index.isMultiple(of: 2) {
                    reflected.translateBy(x: 0, y: tile.minY + tile.maxY)
                    reflected.scaleBy(x: 1, y: -1)
                }
                reflected.draw(source, in: tile)
            }
            context.draw(source, in: frame)
        }
        .frame(width: size.width, height: size.height)
    }

    private func blurMask(index: Int) -> LinearGradient {
        let start = size.width * (index == 0 ? Self.sharpEdgeW : Self.levels[index - 1].endW)
        let end = size.width * Self.levels[index].endW
        let points = ([CGFloat(0), size.height] + (0...8).map {
            (frame.minY - start - (end - start) * CGFloat($0) / 8).clamped(0, size.height)
        }).sorted()
        let stops = points.map { y in
            let amount = Double(((frame.minY - y - start) / max(end - start, 1)).clamped(0, 1))
            return Gradient.Stop(color: .white.opacity(Self.smoothstep(amount)), location: y / max(size.height, 1))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}
